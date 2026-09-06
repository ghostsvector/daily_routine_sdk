/// Reports uncaught errors/crashes and breadcrumb-style log lines to a
/// crash-reporting backend (Firebase Crashlytics — see
/// [FirebaseCrashReportingService]) so issues that only show up on a real
/// user's device are visible somewhere, not just in a terminal they'd have
/// to be watching at the exact moment it happened.
abstract class CrashReportingService {
  /// Records a caught or uncaught error. [fatal] marks it as having
  /// crashed/would have crashed the app (an uncaught exception), as
  /// opposed to a handled error worth knowing about but that the app
  /// recovered from on its own.
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  });

  /// A breadcrumb log line attached to whatever error report comes next —
  /// for context ("about to poll X", "user tapped Y") rather than an error
  /// in itself.
  Future<void> log(String message);

  /// Tags subsequent reports with the signed-in user's id, so reports from
  /// the same account can be correlated — never anything more identifying
  /// than the uid itself.
  Future<void> setUserId(String? uid);

  /// Whether to actually send reports. Off by default in most apps'
  /// debug/development runs; the composing app decides when to enable it.
  Future<void> setCollectionEnabled(bool enabled);
}
