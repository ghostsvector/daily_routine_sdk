import 'package:daily_routine_sdk/security/app_check_http_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage has no unit-test-environment fake of its own —
  // fake its method channel with a simple in-memory map instead of hitting
  // a real OS keystore that doesn't exist under `flutter test`.
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final fakeStorage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async {
      switch (call.method) {
        case 'read':
          return fakeStorage[call.arguments['key']];
        case 'write':
          fakeStorage[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'readAll':
          return fakeStorage;
        default:
          return null;
      }
    },
  );

  test('attaches the same debug token to every request', () async {
    final seenTokens = <String?>[];
    final mock = MockClient((request) async {
      seenTokens.add(request.headers['X-Firebase-AppCheck']);
      return http.Response('{}', 200);
    });

    final client = AppCheckHttpClient(inner: mock);
    await client.get(Uri.parse('https://example.com/a'));
    await client.get(Uri.parse('https://example.com/b'));

    expect(seenTokens, hasLength(2));
    expect(seenTokens[0], isNotNull);
    expect(seenTokens[0], seenTokens[1]); // stable across requests
  });

  test('debug token store generates a UUID-v4-shaped token', () async {
    final token = await const AppCheckDebugTokenStore().getOrCreate();
    expect(
      token,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
  });
}
