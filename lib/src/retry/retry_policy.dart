import 'dart:async';
import 'dart:math' as math;

import '../errors/backend_failure.dart';

/// Describes when and how often a failed operation is retried.
///
/// A retry only ever happens for a failure whose
/// [BackendFailure.isRetryable] is `true`, which by construction excludes
/// invalid credentials, validation errors, permission errors, missing records,
/// conflicts, configuration problems and unimplemented providers.
///
/// The delay before attempt `n` (1-based) is
/// `retryDelay * retryBackoffMultiplier^(n-1)`, clamped to `maxRetryDelay` and
/// multiplied by a random jitter factor in `[1 - jitter, 1 + jitter]` to avoid
/// synchronised retry storms across clients.
class RetryPolicy {
  /// How many *additional* attempts are made after the initial one.
  final int maxRetries;

  /// The base delay before the first retry.
  final Duration baseDelay;

  /// The exponential growth factor applied to [baseDelay].
  final double backoffMultiplier;

  /// The hard upper bound for a single backoff delay.
  final Duration maxDelay;

  /// The random jitter fraction applied to each delay, in `[0, 1]`.
  ///
  /// `0.2` means the actual delay lands within 20% of the computed value.
  final double jitter;

  /// A policy that never retries.
  static const RetryPolicy noRetries = RetryPolicy(maxRetries: 0);

  /// Creates a retry policy.
  const RetryPolicy({
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 200),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 10),
    this.jitter = 0.2,
  })  : assert(maxRetries >= 0, 'maxRetries must not be negative'),
        assert(backoffMultiplier >= 1.0, 'backoffMultiplier must be >= 1.0'),
        assert(jitter >= 0.0 && jitter <= 1.0, 'jitter must be within [0, 1]');

  /// The total number of attempts, including the first one.
  int get maxAttempts => maxRetries + 1;

  /// Whether a failure justifies another attempt on [attempt].
  ///
  /// [attempt] is 1-based: the initial call is attempt `1`. A `maxRetries` of
  /// `2` therefore allows attempts 1, 2 and 3.
  bool shouldRetry({
    required BackendFailure failure,
    required int attempt,
  }) {
    if (attempt >= maxAttempts) return false;
    return failure.isRetryable;
  }

  /// Computes the delay to wait before the attempt that follows [attempt].
  ///
  /// [random] is injectable so the backoff schedule can be asserted in tests.
  Duration delayFor(int attempt, {math.Random? random}) {
    if (attempt < 1) {
      throw ArgumentError.value(attempt, 'attempt', 'must be 1-based');
    }
    final exponent = attempt - 1;
    final scaledMicros =
        baseDelay.inMicroseconds * math.pow(backoffMultiplier, exponent);
    if (!scaledMicros.isFinite) {
      return maxDelay;
    }
    final capped =
        math.min(scaledMicros.toDouble(), maxDelay.inMicroseconds.toDouble());
    final jitterFactor = 1.0 +
        ((random?.nextDouble() ?? math.Random().nextDouble()) * 2 - 1) * jitter;
    final jittered = capped * jitterFactor;
    return Duration(
      microseconds: jittered.clamp(0, maxDelay.inMicroseconds).round(),
    );
  }

  /// Returns a copy of this policy with the given fields replaced.
  RetryPolicy copyWith({
    int? maxRetries,
    Duration? baseDelay,
    double? backoffMultiplier,
    Duration? maxDelay,
    double? jitter,
  }) {
    return RetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      baseDelay: baseDelay ?? this.baseDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      maxDelay: maxDelay ?? this.maxDelay,
      jitter: jitter ?? this.jitter,
    );
  }

  @override
  String toString() {
    return 'RetryPolicy(maxRetries: $maxRetries, baseDelay: '
        '${baseDelay.inMilliseconds}ms, backoffMultiplier: '
        '$backoffMultiplier, maxDelay: ${maxDelay.inMilliseconds}ms, '
        'jitter: $jitter)';
  }
}

/// The signature of the sleep function used between retries.
///
/// Injected so that tests can run the full retry path instantly.
typedef RetryDelay = Future<void> Function(Duration duration);
