/// One page of records returned by an offset-paginated query.
///
/// [hasMore] is computed by the SDK from the requested page size and the
/// number of records the backend returned, so applications do not implement
/// pagination arithmetic.
class PageResult<T> {
  /// The records of this page. Empty when the page is past the end.
  final List<T> items;

  /// The 1-based index of this page.
  final int page;

  /// The page size that was requested.
  final int pageSize;

  /// Whether more records exist after this page.
  ///
  /// Derived from a full page being returned, and refined to `false` when
  /// [totalCount] is known.
  final bool hasMore;

  /// The exact number of records matching the query, when requested.
  ///
  /// `null` unless `PageRequest.includeTotalCount` was `true`, because an
  /// exact count requires an extra database pass.
  final int? totalCount;

  /// Creates a page result.
  const PageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.totalCount,
  });

  /// Creates a page from raw records and the `PageRequest` that produced it.
  ///
  /// The total record count is only trusted when it is supplied and
  /// non-negative, which is what the provider guarantees.
  factory PageResult.fromItems({
    required List<T> items,
    required int page,
    required int pageSize,
    int? totalCount,
  }) {
    final safeTotal =
        (totalCount != null && totalCount >= 0) ? totalCount : null;
    final hasMore = safeTotal != null
        ? (page * pageSize) < safeTotal
        : items.length >= pageSize;
    return PageResult(
      items: List<T>.unmodifiable(items),
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
      totalCount: safeTotal,
    );
  }

  /// The number of records in this page.
  int get length => items.length;

  /// Alias for [length] used by common API pagination contracts.
  int get count => length;

  /// Alias for [page], matching common API pagination terminology.
  int get currentPage => page;

  /// Alias for [pageSize], matching common API pagination terminology.
  int get perPage => pageSize;

  /// Alias for [totalCount], when the backend was asked for an exact total.
  int? get total => totalCount;

  /// The total number of pages when [totalCount] is available.
  int? get totalPages =>
      totalCount == null ? null : (totalCount! / pageSize).ceil();

  /// Alias for [hasMore], matching common API pagination terminology.
  bool get hasNext => hasMore;

  /// Whether this page contains no records.
  bool get isEmpty => items.isEmpty;

  /// Whether this page contains at least one record.
  bool get isNotEmpty => items.isNotEmpty;

  /// Returns a copy of this page whose items are the results of applying
  /// [transform] to each of them.
  ///
  /// Every piece of pagination metadata is carried over unchanged: [page],
  /// [pageSize], [hasMore] and [totalCount] describe the *query*, not the items,
  /// so recomputing them here would silently change pagination behaviour. In
  /// particular [hasMore] is copied verbatim rather than re-derived from the
  /// mapped list.
  ///
  /// ```dart
  /// final result = await BackendSdk.instance.products.getPage(request: request);
  /// final models = result.map(
  ///   (page) => page.mapItems(ProductModel.fromProduct),
  /// );
  /// ```
  ///
  /// The returned [items] list is unmodifiable, and the receiver's own [items]
  /// list is never mutated: this is a pure transformation of an immutable value.
  ///
  /// An empty page maps to an empty page, still carrying its metadata.
  ///
  /// ## Exceptions from [transform]
  ///
  /// [transform] is **not** wrapped in a `try`/`catch`, and an exception it
  /// throws propagates to the caller unchanged. This matches
  /// [BackendResult.map][../result/backend_result.dart], and it is deliberate:
  /// silently substituting a `BackendFailure` would make a programming error in a
  /// mapper look like a backend outage. Handle mapping errors by returning a
  /// `null`-able model or by catching at the call site.
  PageResult<R> mapItems<R>(R Function(T item) transform) {
    return PageResult<R>(
      items: List<R>.unmodifiable(items.map(transform)),
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
      totalCount: totalCount,
    );
  }

  /// Returns an empty page for the given request.
  factory PageResult.empty({
    required int page,
    required int pageSize,
    int? totalCount,
  }) {
    return PageResult<T>(
      items: const [],
      page: page,
      pageSize: pageSize,
      hasMore: false,
      totalCount: totalCount,
    );
  }

  @override
  String toString() {
    return 'PageResult<$T>(page: $page, pageSize: $pageSize, '
        'items: ${items.length}, hasMore: $hasMore, totalCount: $totalCount)';
  }
}
