import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 (TOTP) on top of RFC 4226 (HOTP) — the algorithm behind
/// authenticator apps like Google Authenticator and Authy. Implemented
/// directly against `package:crypto`'s HMAC rather than pulling in a
/// dedicated TOTP package, since the algorithm itself is short and this
/// keeps the dependency footprint the same as everything else in the SDK.
///
/// Stateless: callers own secret storage (see the app's TwoFactorService,
/// which keeps the secret in the OS keystore the same way Murthy's
/// encryption key is kept).
class TotpService {
  const TotpService({this.digits = 6, this.period = const Duration(seconds: 30)});

  final int digits;
  final Duration period;

  static const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// A fresh random secret (160 bits — the size every authenticator app
  /// assumes), base32-encoded for both storage and display/enrollment.
  String generateSecret({Random? random}) {
    final rng = random ?? Random.secure();
    final bytes = Uint8List.fromList(List.generate(20, (_) => rng.nextInt(256)));
    return _base32Encode(bytes);
  }

  /// The `otpauth://` URI an authenticator app's "scan a QR code" or
  /// "enter manually" flow expects.
  String buildProvisioningUri({
    required String base32Secret,
    required String accountName,
    String issuer = 'Daily Routine',
  }) {
    final label = Uri.encodeComponent('$issuer:$accountName');
    final params = {
      'secret': base32Secret,
      'issuer': issuer,
      'algorithm': 'SHA1',
      'digits': '$digits',
      'period': '${period.inSeconds}',
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return 'otpauth://totp/$label?$query';
  }

  /// The code valid right now (or at [now], for tests).
  String currentCode(String base32Secret, {DateTime? now}) {
    final counter = _counterFor(now ?? DateTime.now());
    return _hotp(base32Secret, counter);
  }

  /// Checks [code] against the current time step and up to [window] steps
  /// on either side, so a slow typist or a slightly-off device clock still
  /// verifies — the same tolerance every TOTP implementation allows.
  bool verifyCode(String base32Secret, String code, {DateTime? now, int window = 1}) {
    final normalized = code.trim();
    if (normalized.length != digits) return false;

    final currentCounter = _counterFor(now ?? DateTime.now());
    for (var offset = -window; offset <= window; offset++) {
      if (_hotp(base32Secret, currentCounter + offset) == normalized) return true;
    }
    return false;
  }

  int _counterFor(DateTime time) => time.toUtc().millisecondsSinceEpoch ~/ period.inMilliseconds;

  String _hotp(String base32Secret, int counter) {
    final key = _base32Decode(base32Secret);
    final counterBytes = ByteData(8)..setInt64(0, counter, Endian.big);
    final hmac = Hmac(sha1, key).convert(counterBytes.buffer.asUint8List()).bytes;

    final offset = hmac.last & 0x0f;
    final binary = ((hmac[offset] & 0x7f) << 24) |
        ((hmac[offset + 1] & 0xff) << 16) |
        ((hmac[offset + 2] & 0xff) << 8) |
        (hmac[offset + 3] & 0xff);

    final code = binary % pow(10, digits).toInt();
    return code.toString().padLeft(digits, '0');
  }

  static String _base32Encode(Uint8List bytes) {
    final buffer = StringBuffer();
    var bitBuffer = 0;
    var bitCount = 0;
    for (final byte in bytes) {
      bitBuffer = (bitBuffer << 8) | byte;
      bitCount += 8;
      while (bitCount >= 5) {
        bitCount -= 5;
        buffer.write(_base32Alphabet[(bitBuffer >> bitCount) & 0x1f]);
      }
    }
    if (bitCount > 0) {
      buffer.write(_base32Alphabet[(bitBuffer << (5 - bitCount)) & 0x1f]);
    }
    return buffer.toString();
  }

  static Uint8List _base32Decode(String encoded) {
    final clean = encoded.toUpperCase().replaceAll('=', '');
    final bytes = <int>[];
    var bitBuffer = 0;
    var bitCount = 0;
    for (final char in clean.codeUnits) {
      final value = _base32Alphabet.indexOf(String.fromCharCode(char));
      if (value == -1) continue;
      bitBuffer = (bitBuffer << 5) | value;
      bitCount += 5;
      if (bitCount >= 8) {
        bitCount -= 8;
        bytes.add((bitBuffer >> bitCount) & 0xff);
      }
    }
    return Uint8List.fromList(bytes);
  }
}
