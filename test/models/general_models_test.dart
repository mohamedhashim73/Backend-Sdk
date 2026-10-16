import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SDK-owned general models', () {
    test('creates pagination metadata from a page result', () {
      final metadata = PaginationModel.fromPageResult(
        PageResult<int>.fromItems(
          items: const [1, 2],
          page: 2,
          pageSize: 2,
          totalCount: 5,
        ),
      );

      expect(metadata.total, 5);
      expect(metadata.count, 2);
      expect(metadata.currentPage, 2);
      expect(metadata.totalPages, 3);
      expect(metadata.hasNext, isTrue);
    });

    test('keeps app state contracts independent of a backend provider', () {
      const params = PaginationParams(page: 1, perPage: 20, search: 'watib');
      const data = ListData<int>([1, 2]);

      expect(params.copyWith(page: 2).page, 2);
      expect(data.data, [1, 2]);
    });

    test('builds and merges provider-neutral paginated responses', () {
      const first = _PageResponse(
        items: <int>[1, 2],
        pagination: PaginationModel(
          total: 3,
          count: 2,
          perPage: 2,
          currentPage: 1,
          totalPages: 2,
        ),
      );
      const next = _PageResponse(
        items: <int>[2, 3],
        pagination: PaginationModel(
          total: 3,
          count: 1,
          perPage: 2,
          currentPage: 2,
          totalPages: 2,
        ),
      );

      expect(first.shouldLoad(), isTrue);
      expect(first.nextPage, 2);
      expect(
        first.paginationParams(refresh: false, defaultPageSize: 2).page,
        2,
      );

      final merged = first.mergeIncoming(next, refresh: false, reset: false);
      expect(merged.data, <int>[1, 2, 3]);
      expect(merged.pagination?.hasNext, isFalse);
    });

    test('compares managed entities by their declared props', () {
      const first = _Entity(id: 'one');
      const duplicate = _Entity(id: 'one');
      const another = _Entity(id: 'two');

      expect(first, duplicate);
      expect(first, isNot(another));
    });
  });
}

class _Entity extends ManagedModel {
  const _Entity({required super.id});
}

class _PageResponse implements PaginatedResponse<List<int>, _PageResponse> {
  @override
  final List<int>? data;

  @override
  final PaginationModel? pagination;

  const _PageResponse({required List<int> items, required this.pagination})
      : data = items;

  @override
  _PageResponse copyWithPagination({
    required List<dynamic> data,
    required PaginationModel? pagination,
  }) {
    return _PageResponse(
      items: data.cast<int>(),
      pagination: pagination,
    );
  }
}
