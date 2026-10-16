/// One page of records returned by a cursor-paginated query.
class CursorPageResult<T> {
  /// The records of this page. Empty when the cursor is past the end.
  final List<T> items;

  /// The cursor to pass to the next request, or `null` when the result set is
  /// exhausted.
  ///
  /// This value is opaque and must not be parsed or constructed by callers.
  final String? nextCursor;

  /// Whether more records exist after this page.
  final bool hasMore;

  /// The exact number of records matching the query, when requested.
  final int? totalCount;

  /// Creates a cursor page.
  const CursorPageResult({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.totalCount,
  });

  /// The number of records in this page.
  int get length => items.length;

  /// Alias for [length] used by common API pagination contracts.
  int get count => length;

  /// Alias for [totalCount], when the backend was asked for an exact total.
  int? get total => totalCount;

  /// Alias for [hasMore], matching common API cursor terminology.
  bool get hasNext => hasMore;

  /// Whether this page contains no records.
  bool get isEmpty => items.isEmpty;

  /// Whether this page contains at least one record.
  bool get isNotEmpty => items.isNotEmpty;

  /// Returns a copy of this page whose items are the results of applying
  /// [transform] to each of them.
  ///
  /// All cursor metadata is carried over unchanged: [nextCursor], [hasMore] and
  /// [totalCount] describe the *query position*, not the items, so recomputing
  /// them here would silently break keyset pagination.
  ///
  /// ```dart
  /// final result = await BackendSdk.instance.products.getCursorPage(
  ///   request: request,
  /// );
  /// final models = result.map(
  ///   (page) => page.mapItems(ProductModel.fromProduct),
  /// );
  /// ```
  ///
  /// The returned [items] list is unmodifiable, and the receiver's own [items]
  /// list is never mutated. An empty page maps to an empty page, still carrying
  /// its cursor metadata.
  ///
  /// ## Exceptions from [transform]
  ///
  /// [transform] is **not** wrapped in a `try`/`catch`, and an exception it
  /// throws propagates to the caller unchanged, matching
  /// [BackendResult.map][../result/backend_result.dart]. Handle mapping errors by
  /// returning a `null`-able model or by catching at the call site.
  CursorPageResult<R> mapItems<R>(R Function(T item) transform) {
    return CursorPageResult<R>(
      items: List<R>.unmodifiable(items.map(transform)),
      nextCursor: nextCursor,
      hasMore: hasMore,
      totalCount: totalCount,
    );
  }

  @override
  String toString() {
    return 'CursorPageResult<$T>(items: ${items.length}, '
        'hasMore: $hasMore, nextCursor: ${nextCursor == null ? 'null' : '***'})';
  }
}
