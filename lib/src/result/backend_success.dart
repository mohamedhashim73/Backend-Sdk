part of 'backend_result.dart';

/// A successful `BackendResult` carrying a value of type `T`.
final class BackendSuccess<T> extends BackendResult<T> {
  /// The value produced by the operation.
  final T value;

  /// Creates a successful result.
  const BackendSuccess(this.value);

  @override
  String toString() => 'BackendSuccess<$T>($value)';
}
