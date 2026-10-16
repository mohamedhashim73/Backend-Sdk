import 'pagination_model.dart';

/// A response that exposes data for presentation or state management.
abstract interface class LoadableResponse<T> {
  T? get data;
}

/// A loadable response with offset-pagination metadata.
abstract interface class PaginatedResponse<T, Self>
    implements LoadableResponse<T> {
  PaginationModel? get pagination;

  Self copyWithPagination({
    required List<dynamic> data,
    required PaginationModel? pagination,
  });
}

/// A generic loaded list value.
class ListData<T> implements LoadableResponse<List<T>> {
  @override
  final List<T>? data;

  const ListData(this.data);
}

/// A generic loaded single value.
class SingleData<T> implements LoadableResponse<T> {
  @override
  final T? data;

  const SingleData(this.data);
}
