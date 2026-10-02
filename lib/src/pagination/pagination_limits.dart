/// Hard limits applied to every paginated request.
///
/// These limits are enforced before any query is sent, which is what prevents
/// an unbounded fetch from reaching the backend.
abstract final class PaginationLimits {
  /// The smallest page size that may be requested.
  static const int minPageSize = 1;

  /// The default page size used when none is supplied.
  static const int defaultPageSize = 20;

  /// The largest page size that may be requested.
  ///
  /// Requests above this are rejected locally with a validation failure instead
  /// of being silently clamped, so a bug cannot quietly turn into a
  /// hundred-thousand-row download.
  static const int maxPageSize = 200;

  /// The largest page index that may be requested.
  ///
  /// Deep offset pagination is slow, so the SDK refuses to compute an offset
  /// beyond this point and directs callers to cursor pagination.
  static const int maxPage = 10000;

  /// The largest `limit` accepted by a `CursorRequest`.
  static const int maxCursorLimit = 500;
}
