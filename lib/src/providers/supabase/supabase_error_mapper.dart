import 'package:supabase/supabase.dart'
    show AuthException, PostgrestException, StorageException;

import '../../errors/backend_error_mapper.dart';
import '../../errors/backend_error_type.dart';
import '../../errors/backend_failure.dart';

/// Converts Supabase exceptions into `BackendFailure`s.
///
/// This is the **only** class in the package that knows what a
/// `PostgrestException`, an `AuthException` or a `StorageException` is. It is
/// what keeps those types from reaching the public API, and it is where the
/// classification table in `BackendErrorClassifier` gets its vendor inputs.
///
/// The mapping rules are deliberately conservative:
///
/// * a 401/403 is never retryable, because a retry cannot change the answer;
/// * PostgREST `PGRST116` (no rows returned) becomes `notFound`, not a generic
///   database error, so a `getById` miss produces the right typed failure;
/// * RLS denials are surfaced as `forbidden`, which makes "this record is not
///   yours" indistinguishable from "this record does not exist" - the correct
///   behaviour, since distinguishing them would leak row existence.
class SupabaseErrorMapper implements BackendErrorMapper {
  /// Creates a mapper.
  const SupabaseErrorMapper();

  /// PostgREST's code for "the query returned no rows".
  static const String noRowsReturned = 'PGRST116';

  @override
  BackendFailure map(
    Object error,
    StackTrace stackTrace, {
    BackendErrorType fallbackType = BackendErrorType.unknown,
    Map<String, Object?> context = const {},
  }) {
    if (error is PostgrestException) {
      return _mapPostgrest(error, stackTrace, fallbackType);
    }
    if (error is AuthException) {
      return _mapAuth(error, stackTrace);
    }
    if (error is StorageException) {
      return _mapStorage(error, stackTrace);
    }
    return BackendErrorClassifier.fromException(
      error,
      stackTrace,
      fallbackType: fallbackType,
    );
  }

  BackendFailure _mapPostgrest(
    PostgrestException error,
    StackTrace stackTrace,
    BackendErrorType fallbackType,
  ) {
    final code = error.code;
    final type = switch (code) {
      noRowsReturned => BackendErrorType.notFound,
      _ => BackendErrorClassifier.resolve(
          code: code,
          statusCode: null,
          fallbackType: fallbackType,
        ),
    };
    return BackendErrorClassifier.build(
      type: type,
      message: 'The database request failed${code == null ? '' : ' ($code)'}.',
      code: code,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  BackendFailure _mapAuth(AuthException error, StackTrace stackTrace) {
    final statusCode = int.tryParse(error.statusCode ?? '');
    final resolved = BackendErrorClassifier.resolve(
      code: error.code,
      statusCode: statusCode,
      // Auth has no generic "backend error" category: an unclassified auth
      // problem is a credential problem, and must not be retried.
      fallbackType: BackendErrorType.unauthorized,
    );

    // Auth is deliberately excluded from retry, including for a 5xx. A repeated
    // sign-in attempt cannot change the answer and can trip account lockout, so
    // a server hiccup during authentication is reported as an unauthorized
    // failure the user can act on rather than as a transient one we loop on.
    final type = resolved == BackendErrorType.server
        ? BackendErrorType.unauthorized
        : resolved;

    // Supabase returns "Invalid login credentials" for both an unknown email
    // and a wrong password. Keep the vendor message internally, but give the UI
    // a single non-enumerating message so the screen cannot be used to discover
    // which addresses are registered.
    final userMessage = switch (type) {
      BackendErrorType.unauthorized =>
        'Incorrect email or password, or your session has expired.',
      BackendErrorType.conflict => 'An account with this email already exists.',
      BackendErrorType.validation =>
        'That email address could not be verified. Check it and try again.',
      BackendErrorType.rateLimited =>
        'Too many attempts. Please wait a moment and try again.',
      _ => null,
    };

    return BackendErrorClassifier.build(
      type: type,
      message: error.message,
      userMessage: userMessage,
      code: error.code,
      statusCode: statusCode,
      cause: error,
      stackTrace: stackTrace,
      isRetryable: type.isRetryable && type != BackendErrorType.unauthorized,
    );
  }

  BackendFailure _mapStorage(
    StorageException error,
    StackTrace stackTrace,
  ) {
    final statusCode = int.tryParse(error.statusCode ?? '');
    final type = BackendErrorClassifier.resolve(
      code: error.statusCode,
      statusCode: statusCode,
      fallbackType: BackendErrorType.storage,
    );
    return BackendErrorClassifier.build(
      type: type,
      message: 'The file operation failed: ${error.message}',
      code: error.statusCode,
      statusCode: statusCode,
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
