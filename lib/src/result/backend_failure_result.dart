part of 'backend_result.dart';

/// A failed `BackendResult` carrying a `BackendFailure`.
final class BackendFailureResult<T> extends BackendResult<T> {
  /// The vendor-neutral description of what went wrong.
  final BackendFailure error;

  /// Creates a failed result.
  const BackendFailureResult({required this.error});

  @override
  String toString() => 'BackendFailureResult<$T>($error)';
}

/// Returns a failed `BackendResult` of type `T` carrying [failure].
///
/// Used by local validation, which produces a `BackendFailure` independently of
/// the success type of the operation it guards.
BackendResult<T> failureOf<T>(BackendFailure failure) {
  return BackendFailureResult<T>(error: failure);
}
