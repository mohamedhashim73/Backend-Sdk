import '../errors/backend_failure.dart';

part 'backend_success.dart';
part 'backend_failure_result.dart';

/// The result of every operation performed by this SDK.
///
/// A `BackendResult` is either a success carrying a `T`, or a failure carrying
/// a `BackendFailure`. It never throws provider exceptions and never exposes
/// provider types, so application code can exhaustively handle every outcome.
sealed class BackendResult<T> {
  const BackendResult();

  /// Whether this result carries a value.
  bool get isSuccess => this is BackendSuccess<T>;

  /// Whether this result carries a `BackendFailure`.
  bool get isFailure => this is BackendFailureResult<T>;

  /// The value of a successful result, or `null` for a failure.
  ///
  /// Prefer [when] or pattern matching over reading this directly; the getter
  /// exists for convenience at call sites that already checked [isSuccess].
  T? get data {
    final self = this;
    return self is BackendSuccess<T> ? self.value : null;
  }

  /// The failure of an unsuccessful result, or `null` for a success.
  BackendFailure? get failure {
    final self = this;
    return self is BackendFailureResult<T> ? self.error : null;
  }

  /// Collapses both branches of this result into a single value.
  ///
  /// ```dart
  /// final label = await sdk.products.getById(id).when(
  ///   success: (product) => product.name,
  ///   failure: (failure) => failure.safeMessage,
  /// );
  /// ```
  R when<R>({
    required R Function(T data) success,
    required R Function(BackendFailure failure) failure,
  }) {
    final self = this;
    if (self is BackendSuccess<T>) {
      return success(self.value);
    }
    return failure((self as BackendFailureResult<T>).error);
  }

  /// Transforms a successful value while preserving a failure unchanged.
  ///
  /// This is the supported way to convert an SDK model into an application
  /// model at the edge of a data source. `R` is inferred from [transform], so no
  /// explicit type argument is needed:
  ///
  /// ```dart
  /// final BackendResult<BackendUser> result =
  ///     await BackendSdk.instance.auth.currentUser();
  /// final BackendResult<AppUser> appUserResult =
  ///     result.map(AppUser.fromBackendUser);
  /// ```
  ///
  /// ## Behaviour
  ///
  /// * On success, [transform] is applied to the value and a `BackendSuccess<R>`
  ///   is returned.
  /// * On failure, [transform] is **not** invoked and the *same* [BackendFailure]
  ///   instance is carried over into a `BackendFailureResult<R>`. Nothing is
  ///   re-classified, re-mapped or copied, so `identical(before.failure,
  ///   after.failure)` holds.
  /// * The receiver is never mutated; `BackendResult` is immutable.
  ///
  /// ## Nullability
  ///
  /// When `T` is nullable and the result carries `null`, [transform] is invoked
  /// with `null` rather than being skipped. Declare the parameter as nullable to
  /// accept that:
  ///
  /// ```dart
  /// // T is BackendUser?
  /// result.map((BackendUser? user) => user == null ? null : user.id);
  /// ```
  ///
  /// Note that a `null` success value and a failure are different states:
  /// `isSuccess` is `true` for a successful `null`.
  ///
  /// ## Exceptions from [transform]
  ///
  /// [transform] is **not** wrapped in a `try`/`catch`. An exception it throws
  /// propagates to the caller unchanged and is never converted into a
  /// [BackendFailure].
  ///
  /// This is deliberate. A mapping function is application code, and a bug in it
  /// is not a backend failure: reporting it as `BackendResult` failure would
  /// turn a programming error into an apparent outage, and would mark it with a
  /// retry policy that could never help. If you need a total mapping, return a
  /// `null`-able or `Result`-like model, or catch at the call site.
  BackendResult<R> map<R>(R Function(T data) transform) {
    final self = this;
    if (self is BackendSuccess<T>) {
      return BackendSuccess<R>(transform(self.value));
    }
    return BackendFailureResult<R>(
      error: (self as BackendFailureResult<T>).error,
    );
  }

  /// Returns the value of a successful result, or the result of [orElse] for a
  /// failure.
  T getOrElse(T Function(BackendFailure failure) orElse) {
    final self = this;
    if (self is BackendSuccess<T>) {
      return self.value;
    }
    return orElse((self as BackendFailureResult<T>).error);
  }
}

/// Returns the value of a successful [BackendResult], or throws its
/// [BackendFailure].
///
/// This is the bridge used by repositories: a provider adapter returns a
/// `BackendResult`, and the repository re-throws the failure so the
/// `RequestExecutor` can apply timeout, retry and logging uniformly. Nothing
/// throws past the repository, because the repository converts the thrown
/// failure back into a failed result.
T unwrap<T>(BackendResult<T> result) {
  final value = result.data;
  if (value != null || result is BackendSuccess<T?>) {
    return value as T;
  }
  throw (result as BackendFailureResult<T>).error;
}
