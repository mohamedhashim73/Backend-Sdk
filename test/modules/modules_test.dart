import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/test_helpers.dart';

void main() {
  group('ProductCodec - decoding', () {
    const codec = ProductCodec();

    test('a complete row decodes into a Product', () {
      final result = codec.decode(<String, dynamic>{
        'id': 'p1',
        'name': 'Phone',
        'price': 999.99,
        'stock': 12,
        'category_id': 'electronics',
        'is_active': true,
        'created_at': '2026-01-02T03:04:05Z',
        'updated_at': '2026-02-02T03:04:05Z',
      });

      final product = result.data!;
      expect(product.id, 'p1');
      expect(product.name, 'Phone');
      expect(product.price, 999.99);
      expect(product.stock, 12);
      expect(product.categoryId, 'electronics');
      expect(product.isActive, isTrue);
      expect(product.isDeleted, isFalse);
      expect(product.createdAt, isNotNull);
      expect(product.priceLabel, '999.99');
    });

    test('a null category decodes as null, not as an empty string', () {
      final product = codec.decode(productRow(id: 'p1')).data!;

      expect(product.categoryId, isNull);
    });

    test('a numeric price sent as a string is accepted', () {
      final product = codec.decode(
          <String, dynamic>{...productRow(id: 'p1'), 'price': '42.5'}).data!;

      expect(product.price, 42.5);
    });

    test('a soft-deleted row keeps its deletedAt stamp', () {
      final product = codec
          .decode(productRow(id: 'p1', deletedAt: '2026-06-01T00:00:00Z'))
          .data!;

      expect(product.isDeleted, isTrue);
      expect(product.deletedAt, isNotNull);
    });

    test('a missing id is a validation failure, not a crash', () {
      final result = codec.decode(<String, dynamic>{'name': 'x'});

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.failure?.message, contains('id'));
    });

    test('an empty id is rejected', () {
      final result = codec.decode(productRow(id: ''));

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a missing name is rejected', () {
      final result = codec.decode(<String, dynamic>{
        'id': 'p1',
        'price': 1,
        'stock': 1,
      });

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a negative price is rejected', () {
      final result =
          codec.decode(<String, dynamic>{...productRow(id: 'p1'), 'price': -1});

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a negative stock is rejected', () {
      final result =
          codec.decode(<String, dynamic>{...productRow(id: 'p1'), 'stock': -5});

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a wrongly typed category is rejected', () {
      final result = codec
          .decode(<String, dynamic>{...productRow(id: 'p1'), 'category_id': 7});

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a wrongly typed active flag is rejected', () {
      final result = codec.decode(
          <String, dynamic>{...productRow(id: 'p1'), 'is_active': 'yes'});

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an unparseable timestamp becomes null rather than throwing', () {
      final product = codec.decode(<String, dynamic>{
        ...productRow(id: 'p1'),
        'created_at': 'not a date',
      }).data!;

      expect(product.createdAt, isNull);
    });

    test('a missing active flag defaults to true', () {
      final product = codec.decode(<String, dynamic>{
        'id': 'p1',
        'name': 'x',
        'price': 1,
        'stock': 1,
      }).data!;

      expect(product.isActive, isTrue);
    });
  });

  group('ProductCodec - encoding', () {
    const codec = ProductCodec();

    test('a create request maps onto the column names', () {
      final values = codec
          .encodeCreate(const CreateProductRequest(
            name: '  Phone  ',
            price: 1000,
            stock: 4,
            categoryId: 'electronics',
            isActive: true,
          ))
          .data!;

      expect(values['name'], 'Phone');
      expect(values['price'], 1000.0);
      expect(values['stock'], 4);
      expect(values['category_id'], 'electronics');
      expect(values['is_active'], isTrue);
    });

    test('an update maps only the fields that were set', () {
      final values =
          codec.encodeUpdate(const UpdateProductRequest(name: 'Updated')).data!;

      expect(values, hasLength(1));
      expect(values['name'], 'Updated');
    });

    test('clearing the category writes an explicit null', () {
      final values = codec
          .encodeUpdate(const UpdateProductRequest(clearCategoryId: true))
          .data!;

      expect(values.containsKey('category_id'), isTrue);
      expect(values['category_id'], isNull);
    });

    test('an update that sets nothing encodes to an empty map', () {
      final values = codec.encodeUpdate(const UpdateProductRequest()).data!;

      expect(values, isEmpty);
      expect(const UpdateProductRequest().hasChanges, isFalse);
    });
  });

  group('ProductCodec - validation', () {
    const codec = ProductCodec();

    test('an empty name is rejected', () {
      final failure = codec.validateCreate(
        const CreateProductRequest(name: '   ', price: 1),
      );

      expect(failure?.type, BackendErrorType.validation);
    });

    test('an over-long name is rejected', () {
      final failure = codec.validateCreate(
        CreateProductRequest(
            name: 'x' * (ProductCodec.maxNameLength + 1), price: 1),
      );

      expect(failure?.message, contains('must not exceed'));
    });

    test('a negative price is rejected', () {
      expect(
        codec.validateCreate(const CreateProductRequest(name: 'x', price: -1)),
        isNotNull,
      );
    });

    test('a non-finite price is rejected', () {
      expect(
        codec.validateCreate(
          const CreateProductRequest(name: 'x', price: double.nan),
        ),
        isNotNull,
      );
      expect(
        codec.validateCreate(
          const CreateProductRequest(name: 'x', price: double.infinity),
        ),
        isNotNull,
      );
    });

    test('a price above the ceiling is rejected', () {
      expect(
        codec.validateCreate(
          const CreateProductRequest(
              name: 'x', price: ProductCodec.maxPrice + 1),
        ),
        isNotNull,
      );
    });

    test('negative stock is rejected', () {
      expect(
        codec.validateCreate(
          const CreateProductRequest(name: 'x', price: 1, stock: -1),
        ),
        isNotNull,
      );
    });

    test('a valid create request passes', () {
      expect(
        codec.validateCreate(
            const CreateProductRequest(name: 'Phone', price: 1)),
        isNull,
      );
    });

    test('an empty update is rejected', () {
      expect(codec.validateUpdate(const UpdateProductRequest()), isNotNull);
    });

    test('an invalid updated price is rejected', () {
      expect(
        codec.validateUpdate(const UpdateProductRequest(price: -5)),
        isNotNull,
      );
    });

    test('setting and clearing the category at once is rejected', () {
      expect(
        codec.validateUpdate(
          const UpdateProductRequest(
            categoryId: 'electronics',
            clearCategoryId: true,
          ),
        ),
        isNotNull,
      );
    });
  });

  group('Product model', () {
    test('has value equality', () {
      const a = Product(
        id: 'p1',
        name: 'x',
        price: 1,
        stock: 1,
        isActive: true,
      );
      const b = Product(
        id: 'p1',
        name: 'x',
        price: 1,
        stock: 1,
        isActive: true,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith replaces only the given fields', () {
      const product = Product(
        id: 'p1',
        name: 'x',
        price: 1,
        stock: 1,
        isActive: true,
      );

      final updated = product.copyWith(name: 'y');

      expect(updated.name, 'y');
      expect(updated.id, 'p1');
      expect(updated.price, 1);
    });

    test('toString carries the identifying fields only', () {
      const product = Product(
        id: 'p1',
        name: 'x',
        price: 1,
        stock: 1,
        isActive: true,
      );

      expect(product.toString(), contains('p1'));
      expect(product.toString(), contains('isDeleted: false'));
    });
  });

  group('ProductsRepository - CRUD', () {
    late FakeDataBackend backend;
    late ProductsRepository repository;

    setUp(() {
      backend = FakeDataBackend()..softDeleteColumn = 'deleted_at';
      repository = buildProductsRepository(backend: backend);
      backend.seedAll(BackendResource.products, [
        productRow(id: 'p1', name: 'Phone', price: 100, stock: 3),
        productRow(id: 'p2', name: 'Tablet', price: 200, stock: 1),
      ]);
    });

    test('getById returns a decoded product', () async {
      final result = await repository.getById('p1');

      expect(result.data!.name, 'Phone');
      expect(result.data!.price, 100);
    });

    test('getById on a missing id is a notFound failure', () async {
      final result = await repository.getById('nope');

      expect(result.failure?.type, BackendErrorType.notFound);
    });

    test('getById with a blank id is a validation failure', () async {
      final result = await repository.getById('   ');

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('getById on a soft-deleted product is a notFound failure', () async {
      await repository.softDelete('p1');

      final result = await repository.getById('p1');

      expect(result.failure?.type, BackendErrorType.notFound);
    });

    test('create validates before hitting the backend', () async {
      final result = await repository.create(
        const CreateProductRequest(name: '', price: 1),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.insertCalls, 0);
    });

    test('create stores the record and returns it', () async {
      final result = await repository.create(
        const CreateProductRequest(name: 'Phone', price: 1000, stock: 5),
      );

      expect(result.isSuccess, isTrue);
      expect(result.data!.name, 'Phone');
      expect(result.data!.price, 1000);
      expect(backend.insertCalls, 1);
    });

    test('update writes only the changed columns', () async {
      final result = await repository.update(
        'p1',
        const UpdateProductRequest(name: 'Updated Phone'),
      );

      expect(result.data!.name, 'Updated Phone');
      expect(result.data!.price, 100, reason: 'unchanged fields are preserved');
      expect(backend.store[BackendResource.products]!.first['price'], 100);
    });

    test('update on a missing id is a notFound failure', () async {
      final result = await repository.update(
        'nope',
        const UpdateProductRequest(name: 'x'),
      );

      expect(result.failure?.type, BackendErrorType.notFound);
    });

    test('update with an invalid request is rejected', () async {
      final result =
          await repository.update('p1', const UpdateProductRequest());

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('delete removes the record permanently', () async {
      final result = await repository.delete('p1');

      expect(result.isSuccess, isTrue);
      expect(backend.store[BackendResource.products], hasLength(1));
    });

    test('delete on a missing id is a notFound failure', () async {
      final result = await repository.delete('nope');

      expect(result.failure?.type, BackendErrorType.notFound);
    });

    test('softDelete retains the row with a deleted_at stamp', () async {
      final result = await repository.softDelete('p1');

      expect(result.data!.isDeleted, isTrue);
      expect(backend.store[BackendResource.products], hasLength(2));
      expect(
        backend.store[BackendResource.products]!
            .firstWhere((row) => row['id'] == 'p1')['deleted_at'],
        isNotNull,
      );
    });

    test('softDelete uses the injected clock', () async {
      final fixed = DateTime.utc(2030, 5, 6, 7, 8, 9);
      final repository = buildProductsRepository(
        backend: backend,
        clock: () => fixed,
      );

      await repository.softDelete('p1');

      final row = backend.store[BackendResource.products]!
          .firstWhere((r) => r['id'] == 'p1');
      // The value is passed through as a DateTime; the provider serialises it.
      expect(row['deleted_at'], fixed);
    });

    test('the generic engine is exposed for advanced composition', () {
      expect(repository.engine.resource, BackendResource.products);
    });
  });

  group('UsersRepository', () {
    late FakeDataBackend backend;
    late UsersRepository repository;

    setUp(() {
      backend = FakeDataBackend();
      repository = UsersRepository(
        backend: backend,
        executor: const RequestExecutor(
          retryPolicy: RetryPolicy.noRetries,
          requestTimeout: Duration.zero,
        ),
      );
      backend.seedAll(BackendResource.users, [
        <String, dynamic>{
          'id': 'u1',
          'display_name': 'Ada',
          'email': 'ada@example.com',
          'role': 'admin',
          'is_active': true,
        },
        <String, dynamic>{
          'id': 'u2',
          'display_name': 'Linus',
          'email': 'linus@example.com',
          'role': 'user',
          'is_active': true,
        },
      ]);
    });

    test('decodes a profile and derives the admin flag', () async {
      final result = await repository.getById('u1');

      expect(result.data!.displayName, 'Ada');
      expect(result.data!.isAdmin, isTrue);
    });

    test('a non-admin profile reports isAdmin false', () async {
      final result = await repository.getById('u2');

      expect(result.data!.isAdmin, isFalse);
    });

    test('a row without an id is a validation failure', () {
      final result =
          const UserCodec().decode(const <String, dynamic>{'email': 'x@y.z'});

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.data, isNull);
    });

    test('a wrong active-flag type is a validation failure', () {
      final result = const UserCodec().decode(const <String, dynamic>{
        'id': 'u1',
        'is_active': 'yes',
      });

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an empty update is rejected', () async {
      final result = await repository.update('u1', const UpdateUserRequest());

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an over-long display name is rejected', () async {
      final result = await repository.update(
        'u1',
        UpdateUserRequest(
            displayName: 'x' * (UserCodec.maxDisplayNameLength + 1)),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('paging returns decoded profiles', () async {
      final result = await repository.getPage(
        request: const PageRequest(page: 1, pageSize: 10),
      );

      expect(result.data!.items.map((u) => u.id).toSet(), {'u1', 'u2'});
    });
  });
}
