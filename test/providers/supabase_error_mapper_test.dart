import 'dart:async';

import 'package:backend_sdk/src/errors/backend_error_mapper.dart';
import 'package:backend_sdk/src/errors/backend_error_type.dart';
import 'package:backend_sdk/src/providers/supabase/supabase_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart'
    show AuthException, PostgrestException, StorageException;

/// The only place in the test suite that is allowed to name Supabase types.
///
/// It verifies that the provider mapper converts them into vendor-neutral
/// failures. Nothing outside `lib/src/providers/supabase/` may do this, which is
/// asserted by `test/public_api_test.dart`.
void main() {
  const mapper = SupabaseErrorMapper();

  group('SupabaseErrorMapper - PostgREST', () {
    test('maps "no rows returned" to a typed notFound', () {
      final failure = mapper.map(
        const PostgrestException(
          message: 'JSON object requested, multiple (or no) rows returned',
          code: 'PGRST116',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.notFound);
      expect(failure.code, 'PGRST116');
      expect(failure.isRetryable, isFalse);
    });

    test('maps a unique violation to conflict', () {
      final failure = mapper.map(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.conflict);
      expect(failure.isRetryable, isFalse);
    });

    test('maps an RLS / privilege denial to forbidden', () {
      final failure = mapper.map(
        const PostgrestException(
          message: 'permission denied for table products',
          code: '42501',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.forbidden);
      expect(failure.isRetryable, isFalse);
    });

    test('falls back to the operation category for an unknown SQLSTATE', () {
      final failure = mapper.map(
        const PostgrestException(message: 'boom', code: 'XX999'),
        StackTrace.current,
        fallbackType: BackendErrorType.database,
      );

      expect(failure.type, BackendErrorType.database);
    });

    test('preserves the provider exception and stack trace', () {
      const error = PostgrestException(message: 'boom', code: '23505');
      final stack = StackTrace.current;
      final failure = mapper.map(error, stack);

      expect(failure.cause, same(error));
      expect(failure.stackTrace, same(stack));
    });
  });

  group('SupabaseErrorMapper - Auth', () {
    test('maps invalid credentials to a non-enumerating unauthorized failure',
        () {
      final failure = mapper.map(
        const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.unauthorized);
      expect(failure.statusCode, 400);
      expect(failure.isRetryable, isFalse);
    });

    test('keeps the vendor message internal', () {
      final failure = mapper.map(
        const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
        StackTrace.current,
      );

      // The vendor message stays available for logs.
      expect(failure.message, 'Invalid login credentials');
      // The user-safe message never reveals which half of the pair was wrong.
      expect(failure.safeMessage, isNot(contains('Invalid login credentials')));
      expect(failure.safeMessage, contains('Incorrect email or password'));
    });

    test('maps an already-registered email to conflict', () {
      final failure = mapper.map(
        const AuthException(
          'User already registered',
          statusCode: '422',
          code: 'email_exists',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.conflict);
      expect(failure.safeMessage, contains('already exists'));
    });

    test('maps an unverified email to validation', () {
      final failure = mapper.map(
        const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.validation);
      expect(failure.isRetryable, isFalse);
    });

    test('maps an expired session to unauthorized', () {
      final failure = mapper.map(
        const AuthException(
          'Invalid Refresh Token: Already Used',
          statusCode: '401',
          code: 'refresh_token_already_used',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.unauthorized);
    });

    test('maps a rate limit to a retryable rateLimited failure', () {
      final failure = mapper.map(
        const AuthException(
          'Too many requests',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.rateLimited);
      expect(failure.isRetryable, isTrue);
    });

    test('never classifies an unknown auth error as retryable', () {
      final failure = mapper.map(
        const AuthException('something unexpected', statusCode: '500'),
        StackTrace.current,
      );

      expect(failure.type, BackendErrorType.unauthorized);
      expect(failure.isRetryable, isFalse);
    });
  });

  group('SupabaseErrorMapper - Storage', () {
    test('maps a missing object to notFound', () {
      final failure = mapper.map(
        const StorageException(
          'Object not found',
          statusCode: '404',
        ),
        StackTrace.current,
        fallbackType: BackendErrorType.storage,
      );

      expect(failure.type, BackendErrorType.notFound);
    });

    test('maps an existing object to conflict', () {
      final failure = mapper.map(
        const StorageException(
          'The resource already exists',
          statusCode: '409',
        ),
        StackTrace.current,
        fallbackType: BackendErrorType.storage,
      );

      expect(failure.type, BackendErrorType.conflict);
    });

    test('maps an oversized payload to a validation failure', () {
      final failure = mapper.map(
        const StorageException('Payload too large', statusCode: '413'),
        StackTrace.current,
        fallbackType: BackendErrorType.storage,
      );

      expect(failure.type, BackendErrorType.validation);
    });

    test('defaults an unrecognised storage error to the storage category', () {
      final failure = mapper.map(
        const StorageException('weird'),
        StackTrace.current,
        fallbackType: BackendErrorType.storage,
      );

      expect(failure.type, BackendErrorType.storage);
    });
  });

  group('SupabaseErrorMapper - non-provider errors', () {
    test('falls back to the generic transport classifier', () {
      final failure = mapper.map(
        TimeoutException('took too long'),
        StackTrace.current,
        fallbackType: BackendErrorType.storage,
      );

      expect(failure.type, BackendErrorType.timeout);
      expect(failure.isRetryable, isTrue);
    });
  });

  group('BackendErrorClassifier reuse', () {
    test('the shared table is what the provider delegates to', () {
      expect(
        BackendErrorClassifier.resolve(
          code: 'PGRST116',
          statusCode: null,
          fallbackType: BackendErrorType.database,
        ),
        BackendErrorType.database,
        reason: 'PGRST116 is provider-specific, so it must be handled by the '
            'mapper rather than the shared table',
      );
    });
  });
}
