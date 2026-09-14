import 'app_error.dart';

/// Maps a Firestore REST API HTTP response to the right [AppError] subtype
/// instead of lumping every non-2xx status into a generic [DatabaseError] —
/// callers can then react differently (e.g. re-authenticate on 401, surface
/// "access denied" distinctly from "not found" or a transient server error).
///
/// [operation] is a short label (e.g. `'watchTasks'`) folded into the
/// message for logs/debugging; it isn't part of the classification itself.
AppError classifyFirestoreRestError(
  int statusCode,
  String body, {
  required String operation,
}) {
  final message = 'Firestore REST $operation failed: $statusCode $body';
  switch (statusCode) {
    case 401:
      return AuthError(message, code: 'unauthenticated');
    case 403:
      // Firestore returns this when firestore.rules denies the request —
      // a real security signal (wrong/expired token, or a query trying to
      // read another user's data), not a generic failure.
      return PermissionError(message);
    case 404:
      return NotFoundError(message);
    case 405:
      // Wrong HTTP verb for the endpoint — a client bug (this SDK sending
      // a request Firestore's REST API doesn't support that way), not a
      // data or auth problem, but still worth distinguishing from a
      // generic 5xx so it doesn't get silently retried like a transient
      // failure would be.
      return RequestError(message);
    case 429:
      return QuotaError(message);
    default:
      return DatabaseError(message);
  }
}

/// Maps a `FirebaseException.code` (native `cloud_firestore` plugin) to the
/// same [AppError] taxonomy [classifyFirestoreRestError] uses for the REST
/// fallback, so callers get consistent typed errors regardless of which
/// backend answered.
AppError classifyFirebaseExceptionCode(
  String code,
  String? message, {
  required String operation,
  Object? cause,
  StackTrace? stackTrace,
}) {
  final fallbackMessage = message ?? 'Firestore $operation failed: $code';
  switch (code) {
    case 'unauthenticated':
      return AuthError(fallbackMessage, code: code, cause: cause, stackTrace: stackTrace);
    case 'permission-denied':
      return PermissionError(fallbackMessage, cause: cause, stackTrace: stackTrace);
    case 'not-found':
      return NotFoundError(fallbackMessage, cause: cause, stackTrace: stackTrace);
    case 'invalid-argument':
    case 'failed-precondition':
      return RequestError(fallbackMessage, cause: cause, stackTrace: stackTrace);
    case 'resource-exhausted':
      return QuotaError(fallbackMessage, cause: cause, stackTrace: stackTrace);
    default:
      return DatabaseError(fallbackMessage, cause: cause, stackTrace: stackTrace);
  }
}
