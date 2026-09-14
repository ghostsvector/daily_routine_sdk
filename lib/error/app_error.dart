/// Typed error contract every SDK service returns instead of a raw platform
/// exception, so app code never has to catch `FirebaseException`,
/// `PlatformException`, etc. directly.
sealed class AppError {
  const AppError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

class AuthError extends AppError {
  const AuthError(super.message, {this.code, super.cause, super.stackTrace});

  final String? code;
}

class DatabaseError extends AppError {
  const DatabaseError(super.message, {super.cause, super.stackTrace});
}

class PermissionError extends AppError {
  const PermissionError(super.message, {super.cause, super.stackTrace});
}

/// The requested document/collection doesn't exist (HTTP 404 /
/// `not-found`). Distinct from [DatabaseError] since a missing document is
/// often an expected, handleable case (e.g. "no summary for this date yet")
/// rather than a genuine failure.
class NotFoundError extends AppError {
  const NotFoundError(super.message, {super.cause, super.stackTrace});
}

/// The request itself was malformed for the endpoint — wrong HTTP method
/// (405), an invalid argument, or a failed precondition. A client-side bug
/// to fix, not something worth retrying like a transient server error.
class RequestError extends AppError {
  const RequestError(super.message, {super.cause, super.stackTrace});
}

/// Firestore quota exceeded (HTTP 429 / `resource-exhausted`) — retrying
/// immediately only makes it worse; callers should back off.
class QuotaError extends AppError {
  const QuotaError(super.message, {super.cause, super.stackTrace});
}

class UnknownError extends AppError {
  const UnknownError(super.message, {super.cause, super.stackTrace});
}
