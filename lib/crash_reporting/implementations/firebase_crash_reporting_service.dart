import 'package:daily_routine_sdk/crash_reporting/crash_reporting_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;

/// [CrashReportingService] backed by Firebase Crashlytics — or, on
/// platforms Crashlytics has no native SDK for at all (Linux, Windows,
/// web — unlike this SDK's other Firebase-backed services, there's no
/// REST fallback available for a crash reporter, since there's nothing
/// meaningful to "poll" or "PATCH"), a no-op that logs via [debugPrint]
/// instead of silently discarding reports.
class FirebaseCrashReportingService implements CrashReportingService {
  factory FirebaseCrashReportingService() {
    if (_isSupported) {
      return FirebaseCrashReportingService._(_RealCrashReportingService());
    }
    return FirebaseCrashReportingService._(_NoOpCrashReportingService());
  }

  FirebaseCrashReportingService._(this._impl);

  final CrashReportingService _impl;

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) => _impl.recordError(error, stackTrace, reason: reason, fatal: fatal);

  @override
  Future<void> log(String message) => _impl.log(message);

  @override
  Future<void> setUserId(String? uid) => _impl.setUserId(uid);

  @override
  Future<void> setCollectionEnabled(bool enabled) => _impl.setCollectionEnabled(enabled);
}

class _RealCrashReportingService implements CrashReportingService {
  static const _logName = 'CrashReporting';

  /// Every call is wrapped defensively: this can run before
  /// `Firebase.initializeApp()` has completed (e.g. an error during startup
  /// itself), in which case `FirebaseCrashlytics.instance` throws — better
  /// to drop that one report than crash the crash reporter.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[$_logName] Not ready yet, dropping a report: $e');
    }
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) => _guard(
    () => FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason, fatal: fatal),
  );

  @override
  Future<void> log(String message) => _guard(() => FirebaseCrashlytics.instance.log(message));

  @override
  Future<void> setUserId(String? uid) =>
      _guard(() => FirebaseCrashlytics.instance.setUserIdentifier(uid ?? ''));

  @override
  Future<void> setCollectionEnabled(bool enabled) =>
      _guard(() => FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled));
}

class _NoOpCrashReportingService implements CrashReportingService {
  static const _logName = 'CrashReporting';

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    debugPrint(
      '[$_logName] (no Crashlytics on this platform) '
      '${fatal ? 'FATAL ' : ''}error${reason != null ? ' ($reason)' : ''}: $error',
    );
  }

  @override
  Future<void> log(String message) async {
    debugPrint('[$_logName] $message');
  }

  @override
  Future<void> setUserId(String? uid) async {}

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}
}
