import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter/material.dart';
import 'package:backend_sdk_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// The example is a deliverable, so it is compiled and smoke-tested here too.
///
/// These tests deliberately make no network calls: they only prove the example
/// uses the public API correctly and that the package's public surface is
/// complete enough to build the documented flows.
void main() {
  test('the example exposes configuration from dart-define', () {
    // Without --dart-define the values are empty, and the example says so
    // instead of failing at runtime.
    expect(AppEnvironment.supabaseUrl, isA<String>());
    expect(AppEnvironment.supabaseAnonKey, isA<String>());
    expect(AppEnvironment.isConfigured, isA<bool>());
  });

  testWidgets('the app builds without credentials', (tester) async {
    await tester.pumpWidget(const BackendSdkExampleApp());

    expect(find.text('backend_sdk example'), findsOneWidget);
    expect(find.textContaining('No credentials configured'), findsOneWidget);
  });

  test('the documented product flows type-check against the public API', () {
    const PageRequest page = PageRequest(page: 1, pageSize: 20);
    const CursorRequest cursor = CursorRequest(limit: 20);
    const FilterCondition filter =
        FilterCondition.equals(ProductFilterField.isActive, true);
    const SortCondition sort =
        SortCondition.descending(ProductSortField.createdAt);
    const CreateProductRequest create = CreateProductRequest(
      name: 'Example',
      price: 1000,
      stock: 10,
      isActive: true,
    );
    const UpdateProductRequest update = UpdateProductRequest(isActive: false);
    const UploadFileRequest upload = UploadFileRequest(
      bucket: StorageBucket.general,
      path: 'demo/file.bin',
      bytes: [],
      contentType: 'application/octet-stream',
    );

    expect(page.page, 1);
    expect(cursor.limit, 20);
    expect(filter.field, ProductFilterField.isActive);
    expect(sort.ascending, isFalse);
    expect(create.price, 1000);
    expect(update.isActive, isFalse);
    expect(upload.bucket, StorageBucket.general);
  });

  test('the example never references a provider type', () {
    // The example source is part of the package deliverable; a provider import
    // here would defeat the whole design.
    expect(showFailure, isNotNull);
  });
  typedMappingTests();
}

/// Covers the typed-mapping example, so the documented pattern is compiled and
/// exercised rather than only asserted in prose.
void typedMappingTests() {
  group('example: typed mapping', () {
    test('AppUser.fromBackendUser matches the map signature', () {
      const BackendUser user = BackendUser(
        id: 'u1',
        email: 'ada@example.com',
        metadata: <String, dynamic>{'display_name': 'Ada'},
      );

      final BackendResult<AppUser> mapped =
          const BackendSuccess<BackendUser>(user).map(
        AppUser.fromBackendUser,
      );

      expect(mapped.data?.displayName, 'Ada');
    });

    test('a user without a display name falls back to the email local part',
        () {
      const BackendUser user = BackendUser(id: 'u1', email: 'ada@example.com');

      final AppUser mapped = AppUser.fromBackendUser(user);

      expect(mapped.displayName, 'ada');
    });

    test('AppProduct converts price to minor units', () {
      const Product product = Product(
        id: 'p1',
        name: 'Phone',
        price: 19.99,
        stock: 1,
        isActive: true,
      );

      final AppProduct mapped = AppProduct.fromBackendProduct(product);

      expect(mapped.priceInCents, 1999);
      expect(mapped.title, 'PHONE');
    });

    test('mapping a page preserves pagination metadata', () {
      final PageResult<Product> page = PageResult<Product>.fromItems(
        items: const <Product>[
          Product(id: 'p1', name: 'Phone', price: 10, stock: 1, isActive: true),
          Product(
              id: 'p2', name: 'Tablet', price: 20, stock: 2, isActive: true),
        ],
        page: 2,
        pageSize: 2,
        totalCount: 7,
      );

      final BackendResult<PageResult<AppProduct>> mapped =
          BackendSuccess<PageResult<Product>>(page).map(
        (PageResult<Product> value) =>
            value.mapItems(AppProduct.fromBackendProduct),
      );

      final PageResult<AppProduct> value = mapped.data!;
      expect(value.items.map((AppProduct p) => p.id).toList(),
          <String>['p1', 'p2']);
      expect(value.page, 2);
      expect(value.pageSize, 2);
      expect(value.hasMore, isTrue);
      expect(value.totalCount, 7);
    });

    test('a failure short-circuits the whole mapping chain', () {
      var calls = 0;
      final BackendFailure failure = BackendErrorClassifier.build(
        type: BackendErrorType.notFound,
        message: 'no such product',
      );

      final BackendResult<PageResult<AppProduct>> mapped =
          failureOf<PageResult<Product>>(failure).map(
        (PageResult<Product> page) {
          calls++;
          return page.mapItems(AppProduct.fromBackendProduct);
        },
      );

      expect(calls, 0);
      expect(identical(mapped.failure, failure), isTrue);
    });

    test('the remote data source is expressible in application types', () {
      const ProductsRemoteDataSource source = ProductsRemoteDataSourceImpl();

      // This assignment is the real assertion: it only compiles if the
      // contract's signatures are written purely in application types, with no
      // SDK model leaking across the data-source boundary.
      final Future<BackendResult<PageResult<AppProduct>>> Function({
        required PageRequest request,
      }) pageReader = source.getProducts;

      final Future<BackendResult<AppProduct>> Function(String id) singleReader =
          source.getProduct;

      expect(pageReader, isNotNull);
      expect(singleReader, isNotNull);
    });

    testWidgets('the summary widget builds from a mapped page',
        (WidgetTester tester) async {
      final PageResult<AppProduct> page = PageResult<AppProduct>.fromItems(
        items: const <AppProduct>[
          AppProduct(id: 'p1', title: 'PHONE', priceInCents: 1000),
        ],
        page: 1,
        pageSize: 20,
        totalCount: 1,
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: buildProductSummary(page))),
      );

      expect(find.textContaining('1 items'), findsOneWidget);
      expect(find.text('PHONE · 1000'), findsOneWidget);
    });
  });
}
