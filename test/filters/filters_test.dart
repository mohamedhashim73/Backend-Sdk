import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/test_helpers.dart';

void main() {
  group('FilterCondition - construction', () {
    test('each factory produces its documented operator', () {
      expect(
        const FilterCondition.equals('name', 'x').operator,
        FilterOperator.equals,
      );
      expect(
        const FilterCondition.notEquals('name', 'x').operator,
        FilterOperator.notEquals,
      );
      expect(
        const FilterCondition.contains('name', 'x').operator,
        FilterOperator.contains,
      );
      expect(
        const FilterCondition.greaterThan('price', 1).operator,
        FilterOperator.greaterThan,
      );
      expect(
        const FilterCondition.lessThan('price', 1).operator,
        FilterOperator.lessThan,
      );
      expect(
          const FilterCondition.isNull('name').operator, FilterOperator.isNull);
      expect(
        const FilterCondition.isNotNull('name').operator,
        FilterOperator.isNotNull,
      );
    });

    test('unary filters carry no value', () {
      expect(const FilterCondition.isNull('name').value, isNull);
      expect(const FilterCondition.isNotNull('name').value, isNull);
    });
  });

  group('FilterCondition - field name validation', () {
    test('accepts plain identifiers', () {
      expect(const FilterCondition.equals('category_id', 1).validate(), isNull);
      expect(const FilterCondition.equals('_private2', 1).validate(), isNull);
      expect(
        const FilterCondition.equals('camelCase_name', 1).validate(),
        isNull,
      );
    });

    test('rejects an empty field name', () {
      expect(const FilterCondition.equals('', 1).validate(),
          contains('must not be empty'));
    });

    test('rejects a leading digit', () {
      expect(const FilterCondition.equals('1st', 1).validate(), isNotNull);
    });

    test('rejects characters that are PostgREST filter syntax', () {
      // These are the shapes that would let a value or field escape its
      // condition and start a new one.
      for (final field in <String>[
        'name,other.eq',
        'name).or',
        'name.or',
        'name*',
        'name ',
        'name;drop',
        'name"',
        r'name\',
        'name=',
        'na me',
        'na.me',
      ]) {
        expect(
          FilterCondition.equals(field, 1).validate(),
          isNotNull,
          reason: 'the field "$field" must be rejected',
        );
      }
    });

    test('rejects an over-long field name', () {
      final long = 'a' * (FilterFieldValidator.maxFieldLength + 1);
      expect(FilterCondition.equals(long, 1).validate(), contains('exceed'));
    });
  });

  group('FilterCondition - value validation', () {
    test('contains and startsWith require a non-empty string', () {
      expect(const FilterCondition.contains('name', '').validate(), isNotNull);
      expect(
        FilterFieldValidator.validateValue(FilterOperator.contains, 5),
        isNotNull,
      );
      expect(
          const FilterCondition.startsWith('name', '').validate(), isNotNull);
      expect(const FilterCondition.contains('name', 'ok').validate(), isNull);
    });

    test('inList requires a non-empty list of supported scalars', () {
      expect(const FilterCondition.inList('id', []).validate(), isNotNull);
      expect(const FilterCondition.inList('id', [1, 2]).validate(), isNull);
    });

    test('ordering operators accept any scalar and reject null', () {
      // The SDK cannot know whether a column is numeric or textual, so any
      // scalar is accepted here. A genuine type mismatch is reported by the
      // backend as a typed database failure.
      expect(const FilterCondition.greaterThan('price', 10).validate(), isNull);
      expect(
        const FilterCondition.greaterThan('created_at', '2026-01-01')
            .validate(),
        isNull,
      );
      expect(
        FilterFieldValidator.validateValue(FilterOperator.lessThan, null),
        contains('non-null'),
      );
    });

    test('a DateTime is accepted and normalised to ISO-8601 UTC', () {
      final instant = DateTime.utc(2026, 3, 1, 12);
      final filter = FilterCondition.greaterThan('created_at', instant);

      expect(filter.validate(), isNull);
      expect(
        FilterFieldValidator.normalizeValue(filter.value),
        '2026-03-01T12:00:00.000Z',
      );
    });

    test('null is an acceptable value for equals and notEquals', () {
      expect(const FilterCondition.equals('name', null).validate(), isNull);
      expect(const FilterCondition.notEquals('name', null).validate(), isNull);
    });

    test('ordering operators cannot even be given a null value', () {
      // `FilterCondition.greaterThan` takes a non-nullable `Object`, so passing
      // null is a compile error rather than a runtime surprise. The same rule is
      // re-checked by the provider, because a filter can also be built by hand.
      expect(
        FilterFieldValidator.validateValue(FilterOperator.greaterThan, null),
        isNotNull,
      );
    });
  });

  group('SortCondition', () {
    test('ascending and descending factories set the direction', () {
      expect(const SortCondition.ascending('name').ascending, isTrue);
      expect(const SortCondition.descending('name').ascending, isFalse);
      expect(const SortCondition('name').ascending, isTrue);
    });

    test('validates the field name', () {
      expect(const SortCondition.ascending('created_at').validate(), isNull);
      expect(const SortCondition.ascending('created at').validate(), isNotNull);
      expect(const SortCondition.ascending('name;drop').validate(), isNotNull);
    });

    test('has value equality', () {
      expect(
        const SortCondition.ascending('name'),
        const SortCondition.ascending('name'),
      );
      expect(
        const SortCondition.ascending('name').hashCode,
        const SortCondition.ascending('name').hashCode,
      );
      expect(
        const SortCondition.ascending('name'),
        isNot(const SortCondition.descending('name')),
      );
    });
  });

  group('Stable ordering', () {
    test('the primary key is appended when it is missing', () {
      final sorting = ProductColumnsDefinition.descriptor.stableSorting(
        const [SortCondition.descending(ProductSortField.createdAt)],
      );

      expect(sorting.map((s) => s.field).toList(), ['created_at', 'id']);
      expect(sorting.last.ascending, isTrue);
    });

    test('the primary key is not appended twice', () {
      final sorting = ProductColumnsDefinition.descriptor.stableSorting(
        const [
          SortCondition.descending(ProductSortField.createdAt),
          SortCondition.ascending('id')
        ],
      );

      expect(sorting.where((s) => s.field == 'id'), hasLength(1));
    });

    test('an empty request falls back to the module default', () {
      final sorting =
          ProductColumnsDefinition.descriptor.stableSorting(const []);

      expect(sorting.map((s) => s.field).toList(), ['created_at', 'id']);
    });

    test('a descriptor with no default still gets a primary-key sort', () {
      const descriptor = BackendResourceDescriptor(
        resource: BackendResource.users,
        primaryKeyField: 'id',
      );

      expect(
        descriptor.stableSorting(const []).map((s) => s.field).toList(),
        ['id'],
      );
    });
  });

  group('Filters and sorting end to end', () {
    late FakeDataBackend backend;
    late ProductsRepository repository;

    setUp(() {
      backend = FakeDataBackend()..softDeleteColumn = 'deleted_at';
      repository = buildProductsRepository(backend: backend);
      backend.seedAll(BackendResource.products, [
        productRow(
            id: 'a',
            name: 'Alpha Phone',
            price: 100,
            stock: 5,
            categoryId: 'electronics'),
        productRow(
            id: 'b',
            name: 'Beta Phone',
            price: 200,
            stock: 0,
            categoryId: 'electronics'),
        productRow(
            id: 'c',
            name: 'Gamma Tablet',
            price: 300,
            stock: 2,
            categoryId: 'tablets'),
        productRow(
            id: 'd',
            name: 'Delta Laptop',
            price: 400,
            stock: 1,
            categoryId: 'electronics'),
      ]);
    });

    test('equals narrows the result set', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          filters: [
            FilterCondition.equals(
                ProductFilterField.categoryId, 'electronics'),
          ],
        ),
      );

      expect(page.data!.items.map((p) => p.id).toSet(), {'a', 'b', 'd'});
    });

    test('a boolean equality filter works', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          filters: [FilterCondition.equals(ProductFilterField.isActive, true)],
        ),
      );

      expect(page.data!.items, hasLength(4));
    });

    test('contains performs a case-insensitive match', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          filters: [FilterCondition.contains(ProductFilterField.name, 'phone')],
        ),
      );

      expect(
          page.data!.items.map((p) => p.id), containsAll(<String>['a', 'b']));
      expect(page.data!.items, hasLength(2));
    });

    test('greaterThan and lessThan compose', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          filters: [
            FilterCondition.greaterThan(ProductFilterField.price, 100),
            FilterCondition.lessThanOrEqual(ProductFilterField.price, 300),
          ],
        ),
      );

      expect(page.data!.items.map((p) => p.id).toSet(), {'b', 'c'});
    });

    test('isNotNull keeps only rows with a category', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          filters: [FilterCondition.isNotNull(ProductFilterField.categoryId)],
        ),
      );

      expect(page.data!.items, hasLength(4));
    });

    test('inList restricts to a set of values', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          filters: [
            FilterCondition.inList('id', ['a', 'c'])
          ],
        ),
      );

      expect(page.data!.items.map((p) => p.id).toSet(), {'a', 'c'});
    });

    test('search narrows by free text', () async {
      final page = await repository.getPage(
        request: const PageRequest(page: 1, pageSize: 20, search: 'tablet'),
      );

      expect(page.data!.items.map((p) => p.id), ['c']);
    });

    test('descending price sorting is applied in order', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          sorting: [SortCondition.descending(ProductSortField.price)],
        ),
      );

      expect(
        page.data!.items.map((p) => p.price).toList(),
        [400, 300, 200, 100],
      );
    });

    test('ascending name sorting is applied in order', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          sorting: [SortCondition.ascending(ProductSortField.name)],
        ),
      );

      expect(
        page.data!.items.map((p) => p.name).toList(),
        ['Alpha Phone', 'Beta Phone', 'Delta Laptop', 'Gamma Tablet'],
      );
    });

    test('the spec always carries a deterministic tie-breaker', () async {
      await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          sorting: [SortCondition.descending(ProductSortField.price)],
        ),
      );

      final sorting = backend.pageSpecs.single.sorting;
      expect(sorting.last.field, 'id');
    });

    test('paging stays stable when many rows share a sort value', () async {
      backend.clear(BackendResource.products);
      for (var i = 0; i < 12; i++) {
        backend.seed(
          BackendResource.products,
          productRow(id: 'id-$i', name: 'Same Name', price: 10, stock: 1),
        );
      }

      final first = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 6,
          sorting: [SortCondition.descending(ProductSortField.price)],
        ),
      );
      final second = await repository.getPage(
        request: const PageRequest(
          page: 2,
          pageSize: 6,
          sorting: [SortCondition.descending(ProductSortField.price)],
        ),
      );

      final ids = [
        ...first.data!.items.map((p) => p.id),
        ...second.data!.items.map((p) => p.id),
      ];
      expect(ids.toSet(), hasLength(12));
    });

    test('an invalid filter field is rejected before any request', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          filters: [FilterCondition.equals('id)or(1', 1)],
        ),
      );

      expect(page.failure?.type, BackendErrorType.validation);
      expect(backend.pageSpecs, isEmpty);
    });

    test('an invalid sort field is rejected before any request', () async {
      final page = await repository.getPage(
        request: const PageRequest(
          page: 1,
          sorting: [SortCondition.ascending('name desc nulls first')],
        ),
      );

      expect(page.failure?.type, BackendErrorType.validation);
      expect(backend.pageSpecs, isEmpty);
    });
  });
}
