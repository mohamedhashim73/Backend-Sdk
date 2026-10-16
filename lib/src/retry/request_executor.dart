import 'dart:async';

import '../core/backend_logger.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import '../result/backend_result.dart';
import 'backend_request.dart';
import 'cancellation_token.dart';
import 'retry_policy.dart';

/// Runs a backend call with a timeout, bounded retries, and cancellation.
///
/// The executor is the only place in the SDK that loops over a failing
/// operation, so retry semantics are uniform across auth, data, storage and
/// realtime. It converts *every* thrown object into a [BackendFailure]; callers
/// therefore never need a `try`/`catch` around SDK calls.
///
/// ```dart
/// final result = await executor.run(
///   operation: 'products.getPage',
///   action: () => client.queryPage(request),
///   fallbackErrorType: BackendErrorType.database,
/// );
/// ```
class RequestExecutor {
  /// The policy governing how often a retryable failure is retried.
  final RetryPolicy retryPolicy;

  /// The maximum duration of a single attempt.
  final Duration requestTimeout;

  /// The logger used for attempt and retry diagnostics.
  final BackendLogger logger;

  /// The sleep implementation used between retries.
  final RetryDelay delay;

  /// Creates a request executor.
  const RequestExecutor({
    required this.retryPolicy,
    required this.requestTimeout,
    this.logger = const NoopBackendLogger(),
    RetryDelay? delay,
  }) : delay = delay ?? _defaultDelay;

  static Future<void> _defaultDelay(Duration duration) =>
      Future<void>.delayed(duration);

  /// Executes [action], applying timeout, retry and cancellation.
  ///
  /// [operation] is a short, non-sensitive label used for logging, for example
  /// `'products.update'`. [fallbackErrorType] classifies errors that carry no
  /// HTTP context. [cancellationToken] aborts the call before the next attempt.
  Future<BackendResult<T>> run<T>({
    required String operation,
    required Future<T> Function() action,
    BackendErrorType fallbackErrorType = BackendErrorType.unknown,
    CancellationToken? cancellationToken,
  }) =>
      execute<T>(
        request: BackendRequest(
          operation: operation,
          fallbackErrorType: fallbackErrorType,
          cancellationToken: cancellationToken,
        ),
        action: action,
      );

  /// Executes [action] using provider-neutral [request] metadata.
  ///
  /// New SDK clients should use this overload so the same executor can serve
  /// Supabase, Firebase and REST adapters without provider-specific APIs.
  Future<BackendResult<T>> execute<T>({
    required BackendRequest request,
    required Future<T> Function() action,
  }) async {
    final operation = request.operation;
    final fallbackErrorType = request.fallbackErrorType;
    final cancellationToken = request.cancellationToken;
    var attempt = 0;
    BackendFailure? lastFailure;

    while (true) {
      attempt++;
      if (cancellationToken?.isCancelled ?? false) {
        return BackendFailureResult<T>(
          error: BackendErrorClassifier.build(
            type: BackendErrorType.cancelled,
            message: 'The request "$operation" was cancelled.',
            cause: const BackendCancellationException(),
          ),
        );
      }

      try {
        final value = await _withTimeout(operation, action);
        if (attempt > 1) {
          logger.info(
            'Request succeeded after retry.',
            context: {'operation': operation, 'attempt': attempt},
          );
        }
        return BackendSuccess<T>(value);
      } on BackendCancellationException catch (error, stackTrace) {
        return BackendFailureResult<T>(
          error: BackendErrorClassifier.build(
            type: BackendErrorType.cancelled,
            message: 'The request "$operation" was cancelled.',
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      } catch (error, stackTrace) {
        final failure =
            _classify(operation, error, stackTrace, fallbackErrorType);
        lastFailure = failure;

        if (!retryPolicy.shouldRetry(failure: failure, attempt: attempt)) {
          return BackendFailureResult<T>(error: failure);
        }

        final backoff = retryPolicy.delayFor(attempt);
        logger.warn(
          'Retrying after a retryable failure.',
          context: {
            'operation': operation,
            'attempt': attempt,
            'errorType': failure.type.name,
            'backoffMs': backoff.inMilliseconds,
          },
        );

        if (cancellationToken?.isCancelled ?? false) {
          return BackendFailureResult<T>(
            error: failure.copyWith(
              type: BackendErrorType.cancelled,
              message: 'The request "$operation" was cancelled while retrying.',
            ),
          );
        }

        try {
          await delay(backoff);
        } on Object {
          // A failing sleep function must not abort the retry loop; fall back
          // to the real delay implementation.
          await _defaultDelay(backoff);
        }
      }
    }
    // Unreachable: the loop only exits by returning.
    // ignore: dead_code
    return BackendFailureResult<T>(
      error: lastFailure ??
          BackendErrorClassifier.build(
            type: fallbackErrorType,
            message: 'The request "$operation" failed.',
          ),
    );
  }

  /// Executes an action that already returns a [BackendResult].
  ///
  /// A failure result is unwrapped inside the retry pipeline, so retryable
  /// provider failures preserve the same timeout/retry semantics as thrown
  /// transport failures.
  Future<BackendResult<T>> executeResult<T>({
    required BackendRequest request,
    required Future<BackendResult<T>> Function() action,
  }) =>
      execute<T>(
        request: request,
        action: () async => unwrap(await action()),
      );

  Future<T> _withTimeout<T>(String operation, Future<T> Function() action) {
    if (requestTimeout <= Duration.zero) {
      return action();
    }
    return action().timeout(
      requestTimeout,
      onTimeout: () => throw TimeoutException(
        'The request "$operation" exceeded '
        '${requestTimeout.inMilliseconds}ms.',
        requestTimeout,
      ),
    );
  }

  BackendFailure _classify(
    String operation,
    Object error,
    StackTrace stackTrace,
    BackendErrorType fallbackErrorType,
  ) {
    // Provider adapters already throw a fully classified `BackendFailure`; the
    // generic classifier below is only the safety net for anything else.
    if (error is BackendFailure) {
      logger.error(
        'Backend request failed.',
        cause: error,
        stackTrace: stackTrace,
        context: {
          'operation': operation,
          'errorType': error.type.name,
        },
      );
      return error;
    }
    logger.error(
      'Backend request failed.',
      cause: error,
      stackTrace: stackTrace,
      context: {
        'operation': operation,
        'errorType': error.runtimeType.toString()
      },
    );
    return BackendErrorClassifier.fromException(
      error,
      stackTrace,
      fallbackType: fallbackErrorType,
    );
  }
}
