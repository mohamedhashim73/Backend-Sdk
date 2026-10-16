import 'loadable_response.dart';
import 'pagination_params.dart';

/// Pagination-related conveniences shared by provider-neutral response models.
extension LoadableResponsePaginationX on LoadableResponse<Object?>? {
  /// Whether a page request should be sent for this response state.
  ///
  /// A refresh or reset always requests data. Otherwise, an empty response
  /// requests its first page and a paginated response requests only when a next
  /// page exists.
  bool shouldLoad({bool refresh = false, bool reset = false}) {
    if (refresh || reset || this == null || this!.data == null) return true;

    return this is PaginatedResponse<List<Object?>, Object?>
        ? (this as PaginatedResponse<List<Object?>, Object?>)
                .pagination
                ?.hasNext ??
            false
        : false;
  }

  /// Whether an incoming response replaces the current response.
  bool shouldReplace({required bool refresh, required bool reset}) {
    return this == null || refresh || reset;
  }

  /// The page following the current one, or the first page when empty.
  int get nextPage {
    final currentPage = this is PaginatedResponse<List<Object?>, Object?>
        ? (this as PaginatedResponse<List<Object?>, Object?>)
            .pagination
            ?.currentPage
        : null;
    return (currentPage ?? 0) + 1;
  }

  /// Builds the next provider-neutral pagination request.
  ///
  /// [defaultPageSize] belongs to the application configuration, allowing each
  /// app to choose its own default while the page arithmetic remains shared.
  PaginationParams paginationParams({
    required bool refresh,
    required int defaultPageSize,
    String? search,
  }) {
    final loadedItems = this?.data is List<Object?>
        ? (this!.data as List<Object?>).length
        : defaultPageSize;

    return PaginationParams(
      page: refresh ? 1 : nextPage,
      perPage: refresh ? loadedItems : defaultPageSize,
      search: search,
    );
  }

  /// Merges [incoming] into this response when it represents a later page.
  ///
  /// Non-paginated responses always replace the current value.
  T mergeIncoming<T extends LoadableResponse<Object?>>(
    T incoming, {
    required bool refresh,
    required bool reset,
  }) {
    if (incoming is! PaginatedResponse<List<Object?>, Object?>) {
      return incoming;
    }

    return incoming.mergePage(current: this, refresh: refresh, reset: reset)
        as T;
  }
}

/// Merge support for offset-paginated list responses.
extension PaginatedResponseMergeX on PaginatedResponse<List<Object?>, Object?> {
  /// Returns this page or a de-duplicated append to [current].
  PaginatedResponse<List<Object?>, Object?> mergePage({
    required LoadableResponse<Object?>? current,
    required bool refresh,
    required bool reset,
  }) {
    if (current.shouldReplace(refresh: refresh, reset: reset)) return this;

    final currentItems =
        (current as PaginatedResponse<List<Object?>, Object?>).data ??
            const <Object?>[];
    final incomingItems = data ?? const <Object?>[];
    final mergedItems = <Object?>[...currentItems];

    for (final item in incomingItems) {
      if (!mergedItems.contains(item)) mergedItems.add(item);
    }

    return copyWithPagination(data: mergedItems, pagination: pagination)
        as PaginatedResponse<List<Object?>, Object?>;
  }
}
