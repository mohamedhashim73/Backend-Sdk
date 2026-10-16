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
