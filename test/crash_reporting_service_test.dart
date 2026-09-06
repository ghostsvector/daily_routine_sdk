import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebaseCrashReportingService', () {
    // The test runner's platform (Linux/whatever CI uses) has no native
    // Crashlytics SDK, so this always exercises the no-op fallback — which
    // is exactly what needs covering: it must never throw just because
    // Firebase/Crashlytics isn't available.
    test('recordError/log/setUserId/setCollectionEnabled never throw without Firebase', () async {
      final service = FirebaseCrashReportingService();
      await service.recordError(Exception('boom'), StackTrace.current, reason: 'test');
      await service.log('breadcrumb');
      await service.setUserId('uid-123');
      await service.setUserId(null);
      await service.setCollectionEnabled(true);
    });
  });
}
