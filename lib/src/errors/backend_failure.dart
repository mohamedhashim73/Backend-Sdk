import 'backend_error_type.dart';

/// A vendor-neutral, immutable description of a backend failure.
///
/// A [BackendFailure] is the *only* error type that crosses the public API of
/// this package. Provider exceptions (for example `PostgrestException` or
/// `AuthException`) are never returned to callers; they are converted into a
/// [BackendFailure] by a provider error mapper and retained as [cause] for
/// diagnostics only.
class BackendFailure implements Exception {
  /// The vendor-neutral classification of this failure.
  final BackendErrorType type;

  /// A developer-facing message. Never contains credentials or tokens.
  final String message;

  /// A message that is safe to render directly in a user interface.
  ///
  /// When `null`, callers should fall back to [BackendFailure.defaultUserMessage].
  final String? userMessage;

  /// The provider-specific error code, when one was reported.
  ///
  /// This is a diagnostic string such as a PostgREST `23505` or a GoTrue
  /// `invalid_credentials`. It is not a vendor type.
  final String? code;

  /// The HTTP status code returned by the backend, when the failure originated
  /// from an HTTP response.
  final int? statusCode;

  /// The original provider exception, preserved for logging and debugging.
  ///
  /// This value is never rendered to end users. Do not include it in
  /// user-visible strings.
  final Object? cause;

  /// The stack trace captured when [cause] was thrown.
  final StackTrace? stackTrace;

  /// Whether the SDK is allowed to retry the operation that produced this
  /// failure.
  final bool isRetryable;

  /// Creates a backend failure.
  const BackendFailure({
    required this.type,
    required this.message,
    required this.isRetryable,
    this.userMessage,
    this.code,
    this.statusCode,
    this.cause,
    this.stackTrace,
  });

  /// A safe, generic message shown to end users when no [userMessage] was
  /// supplied by the provider mapper.
  static String defaultUserMessage(BackendErrorType type) {
    switch (type) {
      case BackendErrorType.configuration:
        return 'The app is not configured correctly. Please contact support.';
      case BackendErrorType.network:
        return 'No internet connection. Please check your network and try again.';
      case BackendErrorType.timeout:
        return 'The request took too long. Please try again.';
      case BackendErrorType.cancelled:
        return 'The request was cancelled.';
      case BackendErrorType.unauthorized:
        return 'Your session has expired. Please sign in again.';
      case BackendErrorType.forbidden:
        return 'You do not have permission to perform this action.';
      case BackendErrorType.validation:
        return 'Some of the provided values are invalid.';
      case BackendErrorType.notFound:
        return 'The requested item could not be found.';
      case BackendErrorType.conflict:
        return 'This action conflicts with the current state. Please refresh '
            'and try again.';
      case BackendErrorType.rateLimited:
        return 'Too many requests. Please wait a moment and try again.';
      case BackendErrorType.database:
      case BackendErrorType.storage:
      case BackendErrorType.realtime:
      case BackendErrorType.server:
        return 'Something went wrong on our side. Please try again.';
      case BackendErrorType.unsupportedProvider:
        return 'This feature is not available in the current build.';
      case BackendErrorType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }

  /// Returns a copy of this failure with the given fields replaced.
  ///
  /// Passing `null` keeps the existing value; use [clearUserMessage] to reset
  /// a nullable field to `null`.
  BackendFailure copyWith({
    BackendErrorType? type,
    String? message,
    String? userMessage,
    String? code,
    int? statusCode,
    Object? cause,
    StackTrace? stackTrace,
    bool? isRetryable,
    bool clearUserMessage = false,
  }) {
    return BackendFailure(
      type: type ?? this.type,
      message: message ?? this.message,
      userMessage: clearUserMessage ? null : (userMessage ?? this.userMessage),
      code: code ?? this.code,
      statusCode: statusCode ?? this.statusCode,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      isRetryable: isRetryable ?? this.isRetryable,
    );
  }

  /// The user-safe message for this failure.
  ///
  /// Falls back to [defaultUserMessage] when no explicit [userMessage] was
  /// provided.
  String get safeMessage => userMessage ?? defaultUserMessage(type);

  @override
  String toString() {
    return 'BackendFailure(type: ${type.name}, code: $code, '
        'statusCode: $statusCode, message: $message, '
        'isRetryable: $isRetryable)';
  }
}
