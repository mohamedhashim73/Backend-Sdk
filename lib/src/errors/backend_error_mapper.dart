import 'dart:async';

import 'backend_error_type.dart';
import 'backend_failure.dart';

/// Converts a provider-specific exception into a [BackendFailure].
///
/// Every backend provider owns exactly one implementation of this contract. It
/// is the single place where vendor knowledge about errors is allowed to live.
abstract interface class BackendErrorMapper {
  /// Converts [error] into a [BackendFailure].
  ///
  /// [fallbackType] is used when the error cannot be classified and is normally
  /// the category of the operation that failed, for example
  /// [BackendErrorType.storage] for a file upload.
  ///
  /// [context] carries short, non-sensitive key/value pairs describing the
  /// operation, such as `{'operation': 'upload'}`.
  BackendFailure map(
    Object error,
    StackTrace stackTrace, {
    BackendErrorType fallbackType = BackendErrorType.unknown,
    Map<String, Object?> context = const {},
  });
}

/// Maps a provider error code and/or HTTP status code onto a
/// [BackendErrorType].
///
/// This is the shared classification table used by all providers. Provider
/// mappers only need to supply the vendor-specific bits (the exception type and
/// the raw code string) and delegate the rest here, which keeps error semantics
/// identical no matter which backend is active.
class BackendErrorClassifier {
  const BackendErrorClassifier._();

  /// Maps an HTTP [statusCode] to a [BackendErrorType].
  ///
  /// Returns `null` when [statusCode] is absent or is not an HTTP failure.
  static BackendErrorType? fromStatusCode(int? statusCode) {
    switch (statusCode) {
      case 400:
        return BackendErrorType.validation;
      case 401:
        return BackendErrorType.unauthorized;
      case 403:
        return BackendErrorType.forbidden;
      case 404:
        return BackendErrorType.notFound;
      case 409:
        return BackendErrorType.conflict;
      case 408:
        return BackendErrorType.timeout;
      case 413:
        return BackendErrorType.validation;
      case 415:
        return BackendErrorType.validation;
      case 422:
        return BackendErrorType.validation;
      case 429:
        return BackendErrorType.rateLimited;
      default:
        if (statusCode != null && statusCode >= 500) {
          return BackendErrorType.server;
        }
        return null;
    }
  }

  /// Maps a provider error [code] string onto a [BackendErrorType].
  ///
  /// Recognises both HTTP status strings (`'401'`) and vendor code names such
  /// as `'invalid_credentials'` or PostgreSQL SQLSTATE values (`'23505'`).
  /// Returns `null` when [code] is not recognised, so callers can fall back to
  /// the status code or the operation category.
  static BackendErrorType? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;

    final normalized = code.trim().toLowerCase();

    // A provider code may be a bare HTTP status string ('401') or something
    // entirely different such as a PostgreSQL SQLSTATE ('23505'). Only treat it
    // as a status when it really is one: `23505` parses to a number, but it is
    // a unique-violation SQLSTATE, not "HTTP 23505".
    final parsedStatus = int.tryParse(normalized);
    if (parsedStatus != null && parsedStatus >= 100 && parsedStatus <= 599) {
      final fromStatus = fromStatusCode(parsedStatus);
      if (fromStatus != null) return fromStatus;
    }

    // PostgreSQL SQLSTATE. Two classes matter here: class 23 (integrity
    // constraint violation) and `42501`, which is what PostgREST returns when a
    // row level security policy denies access.
    if (normalized.length == 5) {
      return switch (normalized) {
        '23505' => BackendErrorType.conflict, // unique_violation
        '23503' => BackendErrorType.validation, // foreign_key_violation
        '23514' => BackendErrorType.validation, // check_violation
        '42501' => BackendErrorType.forbidden, // insufficient_privilege (RLS)
        _ when normalized.startsWith('23') => BackendErrorType.database,
        _ => null,
      };
    }

    return switch (normalized) {
      // GoTrue auth codes.
      'invalid_credentials' ||
      'bad_jwt' ||
      'session_expired' ||
      'session_not_found' ||
      'session_missing' ||
      'refresh_token_not_found' ||
      'refresh_token_already_used' ||
      'user_not_found' ||
      'otp_expired' =>
        BackendErrorType.unauthorized,
      'email_exists' ||
      'user_already_exists' ||
      'phone_exists' =>
        BackendErrorType.conflict,
      'email_not_confirmed' ||
      'phone_not_confirmed' ||
      'validation_failed' ||
      'weak_password' ||
      'signup_disabled' ||
      'over_email_send_rate_limit' ||
      'over_sms_send_rate_limit' =>
        BackendErrorType.validation,
      'over_request_rate_limit' ||
      'hook_timeout' =>
        BackendErrorType.rateLimited,
      'unexpected_failure' || 'bad_json' => BackendErrorType.server,
      // Storage codes.
      '404' || 'not_found' || 'no_such_key' => BackendErrorType.notFound,
      '409' || 'key_already_exists' => BackendErrorType.conflict,
      '413' || 'payload_too_large' => BackendErrorType.validation,
      _ => null,
    };
  }

  /// Builds a [BackendFailure] from the parts of a provider error.
  ///
  /// [isRetryable] is derived from the resolved [BackendErrorType] unless it is
  /// explicitly overridden, so a failure is never accidentally marked
  /// retryable for a business reason.
  static BackendFailure build({
    required BackendErrorType type,
    required String message,
    String? userMessage,
    String? code,
    int? statusCode,
    Object? cause,
    StackTrace? stackTrace,
    bool? isRetryable,
  }) {
    return BackendFailure(
      type: type,
      message: message,
      userMessage: userMessage,
      code: code,
      statusCode: statusCode,
      cause: cause,
      stackTrace: stackTrace,
      isRetryable: isRetryable ?? type.isRetryable,
    );
  }

  /// Resolves the effective error type for a failure.
  ///
  /// Precedence: explicit provider [code] mapping, then HTTP [statusCode]
  /// mapping, then [fallbackType].
  static BackendErrorType resolve({
    String? code,
    int? statusCode,
    required BackendErrorType fallbackType,
  }) {
    return fromCode(code) ?? fromStatusCode(statusCode) ?? fallbackType;
  }

  /// Classifies an arbitrary runtime error that has no HTTP context.
  ///
  /// This is transport-level classification only: it is shared by every
  /// provider so that, for example, a `TimeoutException` always becomes
  /// [BackendErrorType.timeout] regardless of which SDK surface produced it.
  static BackendFailure fromException(
    Object error,
    StackTrace stackTrace, {
    required BackendErrorType fallbackType,
  }) {
    if (error is TimeoutException) {
      return build(
        type: BackendErrorType.timeout,
        message: 'The request timed out.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // `dart:io` is not available on the web, so socket-level failures are
    // detected by type name instead of by `is SocketException`. This keeps the
    // package web-safe.
    final typeName = error.runtimeType.toString();
    if (typeName.contains('SocketException') ||
        typeName.contains('HandshakeException') ||
        typeName.contains('ClientException') ||
        typeName.contains('HttpException') ||
        typeName.contains('TlsException')) {
      return build(
        type: BackendErrorType.network,
        message: 'The request could not reach the server.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    // A body that is not the shape the SDK expects means the response could not
    // be interpreted. That is neither the caller's fault nor worth retrying, so
    // it is reported as a validation failure rather than falling through to the
    // caller's category, which would usually be `database` or `storage`.
    if (error is FormatException) {
      return build(
        type: BackendErrorType.validation,
        message: 'The server returned an unexpected response.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is TypeError || error is StateError) {
      return build(
        type: fallbackType,
        message: 'The operation could not be completed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return build(
      type: fallbackType,
      message: 'The operation failed: $error',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
