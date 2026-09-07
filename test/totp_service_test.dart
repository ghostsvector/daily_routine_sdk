import 'package:daily_routine_sdk/security/totp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // RFC 6238 Appendix B's SHA1 test vectors use this exact ASCII secret,
  // base32-encoded ("12345678901234567890" -> secret below) — verifying
  // against the RFC's own published (time, code) pairs is what proves this
  // implementation actually is RFC 6238, not just "produces 6 digits".
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  final totp = TotpService();

  test('matches RFC 6238 Appendix B SHA1 test vectors', () {
    expect(
      totp.currentCode(secret, now: DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true)),
      '287082',
    );
    expect(
      totp.currentCode(
        secret,
        now: DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true),
      ),
      '081804',
    );
    expect(
      totp.currentCode(
        secret,
        now: DateTime.fromMillisecondsSinceEpoch(1111111111 * 1000, isUtc: true),
      ),
      '050471',
    );
    expect(
      totp.currentCode(
        secret,
        now: DateTime.fromMillisecondsSinceEpoch(1234567890 * 1000, isUtc: true),
      ),
      '005924',
    );
  });

  test('verifyCode accepts the current code and rejects a wrong one', () {
    final secret2 = totp.generateSecret();
    final code = totp.currentCode(secret2);
    expect(totp.verifyCode(secret2, code), isTrue);
    expect(totp.verifyCode(secret2, '000000' == code ? '111111' : '000000'), isFalse);
  });

  test('verifyCode tolerates one step of clock skew but not two', () {
    final secret2 = totp.generateSecret();
    final now = DateTime.now();
    final oneStepAgo = now.subtract(const Duration(seconds: 30));
    final twoStepsAgo = now.subtract(const Duration(seconds: 60));

    final codeOneStepAgo = totp.currentCode(secret2, now: oneStepAgo);
    final codeTwoStepsAgo = totp.currentCode(secret2, now: twoStepsAgo);

    expect(totp.verifyCode(secret2, codeOneStepAgo, now: now), isTrue);
    expect(totp.verifyCode(secret2, codeTwoStepsAgo, now: now), isFalse);
  });

  test('generateSecret produces a valid base32 string usable as a secret', () {
    final secret2 = totp.generateSecret();
    expect(secret2, matches(RegExp(r'^[A-Z2-7]+$')));
    expect(secret2.length, 32); // 20 bytes -> 32 base32 chars, no padding
  });

  test('buildProvisioningUri encodes account/issuer for authenticator apps', () {
    final uri = totp.buildProvisioningUri(
      base32Secret: secret,
      accountName: 'me@example.com',
    );
    expect(uri, startsWith('otpauth://totp/'));
    expect(uri, contains('secret=$secret'));
    expect(uri, contains('issuer=Daily'));
  });
}
