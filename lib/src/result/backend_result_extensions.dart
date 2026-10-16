part of 'backend_result.dart';

/// Provider-neutral conveniences for consuming a [BackendResult].
extension BackendResultX<T> on BackendResult<T> {
  /// Returns the successful value or throws its [BackendFailure].
  ///
  /// Use this only inside an SDK adapter boundary that is already executed by
  /// a request executor. Application-facing calls should keep the result and
  /// handle both branches with [when] or [whenAsync].
  T unwrapOrThrow() {
    return when(success: (data) => data, failure: (failure) => throw failure);
  }

  /// Resolves either branch when one or both callbacks are asynchronous.
  ///
  /// This is the asynchronous equivalent of [when]. It does not catch errors
  /// raised by either callback; those are application errors and should remain
  /// visible to the caller.
  Future<R> whenAsync<R>({
    required FutureOr<R> Function(T data) success,
    required FutureOr<R> Function(BackendFailure failure) failure,
  }) async {
    return await when(success: success, failure: failure);
  }
}
