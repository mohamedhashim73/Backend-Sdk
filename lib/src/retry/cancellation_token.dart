import 'dart:async';

/// A cooperative cancellation signal that can be passed to any SDK operation.
///
/// Cancellation is cooperative: a cancelled request stops before the *next*
/// retry attempt and completes with
/// `BackendErrorType.cancelled` if it has not
/// already finished. It cannot abort a socket read that is already in flight.
class CancellationToken {
  final Completer<void> _completer = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// The future that completes when this token is cancelled.
  ///
  /// Never completes with an error.
  Future<void> get whenCancelled => _completer.future;

  /// Signals that the associated operation should stop.
  ///
  /// Calling this more than once is a no-op.
  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Throws a [BackendCancellationException] if this token was cancelled.
  ///
  /// @throws BackendCancellationException when [isCancelled] is `true`.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const BackendCancellationException();
    }
  }
}

/// Thrown internally when a [CancellationToken] is cancelled.
///
/// The `RequestExecutor` converts this into a
/// typed cancellation failure; it never reaches callers as a thrown exception.
class BackendCancellationException implements Exception {
  /// Creates a cancellation exception.
  const BackendCancellationException([
    this.message = 'The request was cancelled.',
  ]);

  /// A developer-facing description of the cancellation.
  final String message;

  @override
  String toString() => 'BackendCancellationException($message)';
}
