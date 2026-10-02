import '../filters/filter_condition.dart';
import '../filters/sort_condition.dart';
import 'pagination_limits.dart';

/// An offset-paginated query.
///
/// Pages are **1-based**: the first page is `page: 1`. The SDK converts the
/// request into an inclusive backend range itself, so callers never deal with
/// offsets.
///
/// ```dart
/// const request = PageRequest(page: 1, pageSize: 20);
/// ```
///
/// For very large or frequently changing datasets prefer `CursorRequest`:
/// offset pagination degrades linearly because the database must skip every
/// preceding row.
class PageRequest {
  /// The 1-based page index. Must be greater than or equal to `1`.
  final int page;

  /// The number of records requested per page.
  ///
  /// Must be between [PaginationLimits.minPageSize] and
  /// [PaginationLimits.maxPageSize].
  final int pageSize;

  /// A free-text search term.
  ///
  /// The provider decides which columns are searched; for the shipped Supabase
  /// provider each module declares its searchable columns, so the application
  /// never writes a raw `ilike` filter.
  final String? search;

  /// Typed filters applied to the query.
  final List<FilterCondition> filters;

  /// Typed sort instructions.
  ///
  /// When empty, the repository's default ordering is used.
  final List<SortCondition> sorting;

  /// Whether the exact total number of matching records should be returned.
  ///
  /// A count query is comparatively expensive, so it is opt-in. Leave this
  /// `false` for infinite-scroll lists.
  final bool includeTotalCount;

  /// Creates a page request.
  const PageRequest({
    required this.page,
    this.pageSize = PaginationLimits.defaultPageSize,
    this.search,
    this.filters = const [],
    this.sorting = const [],
    this.includeTotalCount = false,
  });

  /// The number of records to skip before the first returned record.
  int get offset => (page - 1) * pageSize;

  /// The **inclusive** index of the last record of this page.
  ///
  /// Supabase/PostgREST `range(from, to)` is inclusive on both ends, so
  /// `range(0, 19)` returns 20 records.
  int get inclusiveEnd => offset + pageSize - 1;

  /// The **inclusive** index of the first record of this page.
  int get inclusiveStart => offset;

  /// Validates the numeric bounds of this request.
  ///
  /// Returns `null` when the request is valid, otherwise a developer-facing
  /// description of the problem.
  String? validate() {
    if (page < 1) {
      return 'page must be 1 or greater, but was $page.';
    }
    if (pageSize < PaginationLimits.minPageSize) {
      return 'pageSize must be at least ${PaginationLimits.minPageSize}, '
          'but was $pageSize.';
    }
    if (pageSize > PaginationLimits.maxPageSize) {
      return 'pageSize must not exceed ${PaginationLimits.maxPageSize}, '
          'but was $pageSize. Use cursor pagination for large result sets.';
    }
    return null;
  }

  /// A stable identity for this request, used to de-duplicate concurrent loads.
  String get cacheKey => [
        'page:$page',
        'size:$pageSize',
        'search:${search ?? ''}',
        'count:$includeTotalCount',
        for (final filter in filters) filter.cacheKey,
        for (final sort in sorting) sort.cacheKey,
      ].join('|');

  /// Returns a copy of this request with the given fields replaced.
  PageRequest copyWith({
    int? page,
    int? pageSize,
    String? search,
    List<FilterCondition>? filters,
    List<SortCondition>? sorting,
    bool? includeTotalCount,
  }) {
    return PageRequest(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      filters: filters ?? this.filters,
      sorting: sorting ?? this.sorting,
      includeTotalCount: includeTotalCount ?? this.includeTotalCount,
    );
  }

  @override
  String toString() {
    return 'PageRequest(page: $page, pageSize: $pageSize, '
        'search: $search, filters: ${filters.length}, '
        'sorting: ${sorting.length}, includeTotalCount: $includeTotalCount)';
  }
}
