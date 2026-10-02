/// The vendor-neutral classification of every failure that can be produced by
/// this SDK.
///
/// Application code should branch on these values instead of on provider
/// exception types. No Supabase (or any other vendor) type is ever exposed
/// through this enum.
enum BackendErrorType {
  /// The SDK was used before `BackendSdk.initialize` was awaited, or the
  /// supplied `BackendConfiguration` was missing or malformed.
  configuration,

  /// The request never reached the backend: no connectivity, DNS failure,
  /// TLS failure, or the connection was dropped.
  network,

  /// The request exceeded the configured request timeout.
  timeout,

  /// The caller cancelled the request before it completed.
  cancelled,

  /// Credentials are missing, invalid, or the session has expired.
  unauthorized,

  /// The caller is authenticated but not allowed to perform the operation.
  forbidden,

  /// The request failed local or server-side validation.
  validation,

  /// The requested resource does not exist.
  notFound,

  /// The operation conflicts with the current state of the resource, for
  /// example a unique constraint violation.
  conflict,

  /// The backend rejected the request because a rate limit was exceeded.
  rateLimited,

  /// The database layer failed (constraint violation, RLS denial surfaced as a
  /// database error, malformed query, and similar).
  database,

  /// A file storage operation failed.
  storage,

  /// A realtime subscription or stream failed.
  realtime,

  /// The backend returned a 5xx response.
  server,

  /// The requested `BackendProvider` is declared but not implemented yet.
  unsupportedProvider,

  /// The failure could not be classified.
  unknown,
}

/// Returns `true` when a failure of `type` may be retried automatically.
///
/// Only transient transport-level problems are considered retryable. Business
/// and authorization failures are never retried, because a retry cannot change
/// their outcome and would only amplify load or lock accounts.
extension BackendErrorTypeRetryable on BackendErrorType {
  /// Whether operations failing with this [BackendErrorType] can be retried.
  bool get isRetryable {
    switch (this) {
      case BackendErrorType.network:
      case BackendErrorType.timeout:
      case BackendErrorType.rateLimited:
      case BackendErrorType.server:
        return true;
      case BackendErrorType.configuration:
      case BackendErrorType.cancelled:
      case BackendErrorType.unauthorized:
      case BackendErrorType.forbidden:
      case BackendErrorType.validation:
      case BackendErrorType.notFound:
      case BackendErrorType.conflict:
      case BackendErrorType.database:
      case BackendErrorType.storage:
      case BackendErrorType.realtime:
      case BackendErrorType.unsupportedProvider:
      case BackendErrorType.unknown:
        return false;
    }
  }
}
