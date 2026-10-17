/// Provider-neutral paging input used by application state managers.
///
/// Backends convert this into their own provider request type.
/// It intentionally contains no query-string or provider-specific behaviour.
class PaginationParams {
  final int? page;
  final int? perPage;
  final String? search;

  const PaginationParams({this.page, this.perPage, this.search});

  PaginationParams copyWith({int? page, int? perPage, String? search}) {
    return PaginationParams(
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      search: search ?? this.search,
    );
  }

  /// Converts generic pagination input to query parameters for an HTTP API.
  Map<String, Object?> toQueryParameters({
    String pageKey = 'page',
    String perPageKey = 'perPage',
    String searchKey = 'search',
  }) =>
      {
        if (page != null) pageKey: page,
        if (perPage != null) perPageKey: perPage,
        if (search?.trim().isNotEmpty == true) searchKey: search,
      };
}
