import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// A stable per-install App Check "debug token" for platforms
/// `firebase_app_check`'s native plugin doesn't support (Linux, Windows —
/// the same platforms without a native Firebase SDK at all, hence the REST
/// auth/Firestore path). Android/iOS/macOS/web get real attestation
/// (Play Integrity / App Attest / reCAPTCHA) via the native plugin instead —
/// this class exists specifically for the REST path.
///
/// Generated once and kept in the OS keystore, same pattern as every other
/// device-bound secret in this SDK (Murthy's key, the TOTP secret). A debug
/// token only proves "this exact device asked for one" — it does not
/// attest anything about a genuine app binary the way Play Integrity does.
/// You register it once, per install, in Firebase console → App Check →
/// your app → "Manage debug tokens", after which Firestore will accept
/// requests carrying it even with App Check enforcement turned on.
class AppCheckDebugTokenStore {
  const AppCheckDebugTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'app_check_debug_token_v1';

  final FlutterSecureStorage _storage;

  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) return existing;

    final token = _generateUuidV4();
    await _storage.write(key: _key, value: token);
    return token;
  }

  static String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    String hex(int start, int end) =>
        bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

/// Wraps an [http.Client], attaching the App Check debug token to every
/// request's `X-Firebase-AppCheck` header. Firebase ignores this header
/// entirely until App Check enforcement is turned on for Firestore in the
/// console — so adding this is safe before that switch is flipped, and
/// required after.
class AppCheckHttpClient extends http.BaseClient {
  AppCheckHttpClient({http.Client? inner, AppCheckDebugTokenStore? tokenStore})
    : _inner = inner ?? http.Client(),
      _tokenStore = tokenStore ?? const AppCheckDebugTokenStore();

  final http.Client _inner;
  final AppCheckDebugTokenStore _tokenStore;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _tokenStore.getOrCreate();
    request.headers['X-Firebase-AppCheck'] = token;
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
