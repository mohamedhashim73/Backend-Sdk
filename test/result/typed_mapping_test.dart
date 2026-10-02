import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// An application-side model, the kind a consumer converts an SDK model into.
///
/// It deliberately has no relationship to any provider type, which is what
/// makes it a realistic target for [BackendResult.map].
class AppUser {
  const AppUser({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'AppUser($id, $label)';
}

/// An application-side product model.
class ProductModel {
  const ProductModel({required this.id, required this.displayName});

  final String id;
  final String displayName;

  @override
  String toString() => 'ProductModel($id, $displayName)';
}

/// The tear-off form a remote data source would use.
AppUser appUserFrom(BackendUser user) =>
    AppUser(id: user.id, label: user.email ?? 'no-email');

ProductModel productModelFrom(Product product) =>
    ProductModel(id: product.id, displayName: product.name.toUpperCase());

BackendFailure validationFailure(String message) =>
    BackendErrorClassifier.build(
      type: BackendErrorType.validation,
      message: message,
    );

void main() {
  const backendUser = BackendUser(id: 'u1', email: 'ada@example.com');

  group('BackendResult.map - success', () {
    test('transforms the value and returns a success', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      final BackendResult<AppUser> mapped = result.map(appUserFrom);

      expect(mapped.isSuccess, isTrue);
      expect(mapped.failure, isNull);
      expect(mapped.data, const AppUser(id: 'u1', label: 'ada@example.com'));
    });

    test('R is inferred without an explicit type argument', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      // No <AppUser> written out: the inference comes from appUserFrom.
      final mapped = result.map(appUserFrom);

      expect(
        mapped,
        isA<BackendResult<AppUser>>(),
        reason: 'R must be inferred as AppUser',
      );
    });

    test('can widen the value type', () {
      const BackendResult<int> result = BackendSuccess<int>(7);

      final BackendResult<num> widened = result.map((int value) => value);

      expect(widened.data, 7);
    });

    test('can narrow to a subtype', () {
      const BackendResult<num> result = BackendSuccess<num>(7);

      final BackendResult<int> narrowed =
          result.map((num value) => value.toInt());

      expect(narrowed.data, 7);
    });

    test('can change the type entirely', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      // 'u1' has two characters.
      final BackendResult<int> mapped =
          result.map((BackendUser user) => user.id.length);

      expect(mapped.data, 2);
    });

    test('the receiver is not mutated', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      result.map(appUserFrom);

      expect(result.data, backendUser);
      expect(result.isSuccess, isTrue);
    });

    test('the transform receives exactly the carried value', () {
      final seen = <BackendUser>[];

      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );
      result.map((BackendUser user) {
        seen.add(user);
        return user;
      });

      expect(seen, <BackendUser>[backendUser]);
    });
  });

  group('BackendResult.map - failure', () {
    test('does not invoke the transform', () {
      var calls = 0;
      final result = failureOf<BackendUser>(validationFailure('bad'));

      result.map((BackendUser user) {
        calls++;
        return appUserFrom(user);
      });

      expect(calls, 0);
    });

    test('preserves the identical BackendFailure instance', () {
      final failure = validationFailure('bad');
      final result = failureOf<BackendUser>(failure);

      final BackendResult<AppUser> mapped = result.map(appUserFrom);

      expect(mapped.isFailure, isTrue);
      expect(mapped.data, isNull);
      expect(identical(mapped.failure, failure), isTrue);
      expect(mapped.failure!.type, BackendErrorType.validation);
      expect(mapped.failure!.message, 'bad');
    });

    test('preserves every field of the failure, not just the type', () {
      final original = BackendErrorClassifier.build(
        type: BackendErrorType.rateLimited,
        message: 'slow down',
        userMessage: 'Too many requests.',
        code: 'over_request_rate_limit',
        statusCode: 429,
        isRetryable: true,
      );

      final mapped = failureOf<BackendUser>(original).map(appUserFrom);
      final failure = mapped.failure!;

      expect(failure.type, BackendErrorType.rateLimited);
      expect(failure.message, 'slow down');
      expect(failure.userMessage, 'Too many requests.');
      expect(failure.code, 'over_request_rate_limit');
      expect(failure.statusCode, 429);
      expect(failure.isRetryable, isTrue);
      expect(failure.safeMessage, 'Too many requests.');
    });

    test('R is still inferred on the failure path', () {
      final mapped =
          failureOf<BackendUser>(validationFailure('x')).map(appUserFrom);

      expect(mapped, isA<BackendResult<AppUser>>());
    });

    test('a failed result stays failed through repeated mapping', () {
      final failure = validationFailure('bad');

      // Each hop changes the success type, which is the realistic shape of a
      // chain: BackendUser -> AppUser -> AppUser -> AppUser.
      BackendResult<AppUser> mapped =
          failureOf<BackendUser>(failure).map(appUserFrom);

      for (var i = 0; i < 2; i++) {
        mapped = mapped.map(
          (AppUser user) => AppUser(id: user.id, label: user.label),
        );
      }

      expect(mapped.isFailure, isTrue);
      expect(identical(mapped.failure, failure), isTrue);
    });
  });

  group('BackendResult.map - nullable values', () {
    test('a successful null invokes the transform with null', () {
      var calls = 0;
      const BackendResult<BackendUser?> result =
          BackendSuccess<BackendUser?>(null);

      final mapped = result.map((BackendUser? user) {
        calls++;
        return user == null ? 'anonymous' : user.id;
      });

      expect(calls, 1);
      expect(mapped.data, 'anonymous');
      expect(mapped.isSuccess, isTrue);
    });

    test('a successful null is a success, not a failure', () {
      const BackendResult<BackendUser?> result =
          BackendSuccess<BackendUser?>(null);

      final mapped = result.map((BackendUser? user) => user);

      expect(mapped.isSuccess, isTrue);
      expect(mapped.isFailure, isFalse);
      expect(mapped.failure, isNull);
      expect(mapped.data, isNull);
    });

    test('a null-carrying result can map to a nullable model', () {
      const BackendResult<BackendUser?> result =
          BackendSuccess<BackendUser?>(null);

      final BackendResult<AppUser?> mapped = result.map(appUserFromOrNull);

      expect(mapped.isSuccess, isTrue);
      expect(mapped.data, isNull);
    });

    test('a failure carrying a nullable type still short-circuits', () {
      var calls = 0;

      failureOf<BackendUser?>(validationFailure('bad'))
          .map((BackendUser? user) {
        calls++;
        return appUserFromOrNull(user);
      });

      expect(calls, 0);
    });
  });

  group('BackendResult.map - transform exceptions', () {
    test('an exception from the transform propagates unchanged', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      expect(
        () => result
            .map<String>((BackendUser _) => throw StateError('mapper bug')),
        throwsA(isA<StateError>()),
      );
    });

    test('the exception is not converted into a BackendFailure', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      // The documented contract: mapping bugs surface as exceptions, so they
      // cannot be mistaken for a backend outage.
      Object? caught;
      try {
        result.map<String>((BackendUser _) => throw StateError('mapper bug'));
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<StateError>());
      expect(caught, isNot(isA<BackendFailure>()));
    });

    test('the receiver is untouched when the transform throws', () {
      const BackendResult<BackendUser> result = BackendSuccess<BackendUser>(
        backendUser,
      );

      expect(
        () => result.map<String>((BackendUser _) => throw StateError('boom')),
        throwsStateError,
      );
      expect(result.isSuccess, isTrue);
      expect(result.data, backendUser);
    });
  });

  group('PageResult.mapItems', () {
    final page = PageResult<Product>.fromItems(
      items: const <Product>[
        Product(id: 'p1', name: 'Phone', price: 1, stock: 1, isActive: true),
        Product(id: 'p2', name: 'Tablet', price: 2, stock: 2, isActive: true),
        Product(id: 'p3', name: 'Laptop', price: 3, stock: 3, isActive: true),
      ],
      page: 2,
      pageSize: 3,
      totalCount: 9,
    );

    test('transforms every item', () {
      final mapped = page.mapItems(productModelFrom);

      expect(
        mapped.items.map((ProductModel p) => p.id).toList(),
        <String>['p1', 'p2', 'p3'],
      );
      expect(
        mapped.items.map((ProductModel p) => p.displayName).toList(),
        <String>['PHONE', 'TABLET', 'LAPTOP'],
      );
    });

    test('R is inferred without an explicit type argument', () {
      final mapped = page.mapItems(productModelFrom);

      expect(mapped, isA<PageResult<ProductModel>>());
    });

    test('preserves every piece of pagination metadata', () {
      final mapped = page.mapItems(productModelFrom);

      expect(mapped.page, 2);
      expect(mapped.pageSize, 3);
      expect(mapped.hasMore, isTrue);
      expect(mapped.totalCount, 9);
      expect(mapped.length, 3);
    });

    test('preserves a null totalCount', () {
      final noCount = PageResult<Product>.fromItems(
        items: const <Product>[],
        page: 1,
        pageSize: 20,
      );

      expect(noCount.mapItems(productModelFrom).totalCount, isNull);
    });

    test('preserves hasMore false verbatim, not re-derived', () {
      final lastPage = PageResult<Product>.fromItems(
        items: const <Product>[
          Product(id: 'p9', name: 'Last', price: 1, stock: 1, isActive: true),
        ],
        page: 9,
        pageSize: 20,
        totalCount: 9,
      );

      // A mapper that filters items must not be able to flip hasMore.
      final mapped = lastPage.mapItems(productModelFrom);

      expect(mapped.hasMore, isFalse);
      expect(mapped.page, 9);
      expect(mapped.totalCount, 9);
    });

    test('works with an empty list', () {
      final empty = PageResult<Product>.fromItems(
        items: const <Product>[],
        page: 3,
        pageSize: 10,
        totalCount: 20,
      );

      var calls = 0;
      final mapped = empty.mapItems((Product p) {
        calls++;
        return productModelFrom(p);
      });

      expect(calls, 0);
      expect(mapped.items, isEmpty);
      expect(mapped.isEmpty, isTrue);
      expect(mapped.page, 3);
      expect(mapped.totalCount, 20);
    });

    test('does not mutate the original list', () {
      final original = List<Product>.of(page.items);
      final before = List<Product>.of(original);

      page.mapItems(productModelFrom);

      expect(page.items, before);
      expect(page.items.length, 3);
      expect(original.length, 3);
    });

    test('the mapped list is unmodifiable', () {
      final mapped = page.mapItems(productModelFrom);

      expect(
        () => mapped.items.add(
          const ProductModel(id: 'x', displayName: 'X'),
        ),
        throwsUnsupportedError,
      );
    });

    test('the receiver is not mutated in any other way', () {
      page.mapItems(productModelFrom);

      expect(page.page, 2);
      expect(page.pageSize, 3);
      expect(page.hasMore, isTrue);
      expect(page.totalCount, 9);
      expect(page.items.length, 3);
    });

    test('propagates an exception from the transform', () {
      expect(
        () => page.mapItems<String>((Product _) => throw StateError('bad')),
        throwsStateError,
      );
    });

    test('handles nullable item types', () {
      final nullablePage = PageResult<Product?>.fromItems(
        items: const <Product?>[
          null,
          Product(id: 'p1', name: 'Phone', price: 1, stock: 1, isActive: true),
        ],
        page: 1,
        pageSize: 2,
      );

      final mapped = nullablePage.mapItems((Product? p) => p?.name);

      expect(mapped.items, <String?>[null, 'Phone']);
      // 2 items returned for pageSize 2 with no total count, so the SDK's
      // "a full page implies more" rule applies.
      expect(mapped.hasMore, isTrue);
      expect(mapped.page, 1);
      expect(mapped.pageSize, 2);
    });
  });

  group('CursorPageResult.mapItems', () {
    const page = CursorPageResult<Product>(
      items: <Product>[
        Product(id: 'p1', name: 'Phone', price: 1, stock: 1, isActive: true),
        Product(id: 'p2', name: 'Tablet', price: 2, stock: 2, isActive: true),
      ],
      nextCursor: 'cursor-abc',
      hasMore: true,
      totalCount: 42,
    );

    test('transforms every item', () {
      final mapped = page.mapItems(productModelFrom);

      expect(
        mapped.items.map((ProductModel p) => p.displayName).toList(),
        <String>['PHONE', 'TABLET'],
      );
    });

    test('R is inferred without an explicit type argument', () {
      final mapped = page.mapItems(productModelFrom);

      expect(mapped, isA<CursorPageResult<ProductModel>>());
    });

    test('preserves every piece of cursor metadata', () {
      final mapped = page.mapItems(productModelFrom);

      expect(mapped.nextCursor, 'cursor-abc');
      expect(mapped.hasMore, isTrue);
      expect(mapped.totalCount, 42);
      expect(mapped.length, 2);
    });

    test('preserves a null nextCursor and null totalCount', () {
      const last = CursorPageResult<Product>(
        items: <Product>[],
        hasMore: false,
      );

      final mapped = last.mapItems(productModelFrom);

      expect(mapped.nextCursor, isNull);
      expect(mapped.hasMore, isFalse);
      expect(mapped.totalCount, isNull);
      expect(mapped.isEmpty, isTrue);
    });

    test('does not mutate the original list', () {
      final before = List<Product>.of(page.items);

      page.mapItems(productModelFrom);

      expect(page.items, before);
      expect(page.nextCursor, 'cursor-abc');
    });

    test('the mapped list is unmodifiable', () {
      final mapped = page.mapItems(productModelFrom);

      expect(
        () => mapped.items.add(const ProductModel(id: 'x', displayName: 'X')),
        throwsUnsupportedError,
      );
    });

    test('a cursor-paginated walk survives mapping', () {
      // The exact loop from the README, mapped at every step: the cursor must
      // keep advancing rather than resetting.
      var cursor = page.nextCursor;
      var rounds = 0;

      while (cursor != null && rounds < 3) {
        final mapped = page.mapItems(productModelFrom);
        expect(mapped.items, hasLength(2));
        expect(mapped.hasMore, isTrue);
        rounds++;
        cursor = mapped.nextCursor;
      }

      expect(rounds, 3);
    });

    test('propagates an exception from the transform', () {
      expect(
        () => page.mapItems<String>((Product _) => throw StateError('bad')),
        throwsStateError,
      );
    });
  });

  group('Nested mapping - result.map with mapItems', () {
    test('maps a page inside a result without explicit generics', () {
      final BackendResult<PageResult<Product>> result =
          BackendSuccess<PageResult<Product>>(
        PageResult<Product>.fromItems(
          items: const <Product>[
            Product(
                id: 'p1', name: 'Phone', price: 1, stock: 1, isActive: true),
            Product(
                id: 'p2', name: 'Tablet', price: 2, stock: 2, isActive: true),
          ],
          page: 1,
          pageSize: 2,
          totalCount: 2,
        ),
      );

      final mapped = result.map(
        (PageResult<Product> value) => value.mapItems(productModelFrom),
      );

      expect(
        mapped,
        isA<BackendResult<PageResult<ProductModel>>>(),
        reason: 'both type parameters must be inferred',
      );
      expect(mapped.data!.items.map((ProductModel p) => p.id).toList(),
          <String>['p1', 'p2']);
      expect(mapped.data!.totalCount, 2);
      expect(mapped.data!.hasMore, isFalse);
    });

    test('maps a cursor page inside a result without explicit generics', () {
      const BackendResult<CursorPageResult<Product>> result =
          BackendSuccess<CursorPageResult<Product>>(
        CursorPageResult<Product>(
          items: <Product>[
            Product(
                id: 'p1', name: 'Phone', price: 1, stock: 1, isActive: true),
          ],
          nextCursor: 'next',
          hasMore: true,
        ),
      );

      final mapped = result.map(
        (CursorPageResult<Product> value) => value.mapItems(productModelFrom),
      );

      expect(
        mapped,
        isA<BackendResult<CursorPageResult<ProductModel>>>(),
      );
      expect(mapped.data!.nextCursor, 'next');
      expect(mapped.data!.hasMore, isTrue);
      expect(mapped.data!.items.single.displayName, 'PHONE');
    });

    test('a failure short-circuits the whole nested map', () {
      var transformCalls = 0;
      final result = failureOf<PageResult<Product>>(
        validationFailure('no page for you'),
      );

      final mapped = result.map((PageResult<Product> page) {
        transformCalls++;
        return page.mapItems(productModelFrom);
      });

      expect(transformCalls, 0);
      expect(mapped.failure!.message, 'no page for you');
      expect(mapped.failure!.type, BackendErrorType.validation);
    });
  });

  group('The remote data source pattern from the documentation', () {
    test('compiles and behaves as documented', () {
      final BackendResult<PageResult<Product>> backend =
          BackendSuccess<PageResult<Product>>(
        PageResult<Product>.fromItems(
          items: const <Product>[
            Product(
                id: 'p1', name: 'Phone', price: 1, stock: 1, isActive: true),
          ],
          page: 1,
          pageSize: 20,
          totalCount: 1,
        ),
      );

      final BackendResult<PageResult<ProductModel>> result =
          _getProducts(backend);

      expect(result.isSuccess, isTrue);
      expect(result.data!.items.single.displayName, 'PHONE');
      expect(result.data!.totalCount, 1);
    });

    test('propagates the failure unchanged', () {
      final failure = validationFailure('nope');
      final backend = failureOf<PageResult<Product>>(failure);

      final result = _getProducts(backend);

      expect(identical(result.failure, failure), isTrue);
    });
  });
}

/// The exact shape of the data source shown in the README.
BackendResult<PageResult<ProductModel>> _getProducts(
  BackendResult<PageResult<Product>> backend,
) {
  return backend.map(
    (page) => page.mapItems(productModelFrom),
  );
}

AppUser? appUserFromOrNull(BackendUser? user) =>
    user == null ? null : appUserFrom(user);
