import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';

/// Builds a products repository wired to [backend] with a fast retry policy.
ProductsRepository buildProductsRepository({
  required FakeDataBackend backend,
  BackendLogger logger = const NoopBackendLogger(),
  int maxRetries = 0,
  Duration requestTimeout = const Duration(seconds: 5),
  Future<void> Function(Duration)? delay,
  RealtimeRepository? realtime,
  DateTime Function()? clock,
}) {
  return ProductsRepository(
    backend: backend,
    executor: RequestExecutor(
      retryPolicy: RetryPolicy(maxRetries: maxRetries),
      requestTimeout: requestTimeout,
      logger: logger,
      delay: delay ?? ((_) async {}),
    ),
    realtime: realtime,
    clock: clock,
  );
}

/// A complete, valid product row.
BackendRecord productRow({
  required String id,
  String name = 'Product',
  double price = 10,
  int stock = 5,
  String? categoryId,
  bool isActive = true,
  String createdAt = '2026-01-01T00:00:00Z',
  String? updatedAt,
  String? deletedAt,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'price': price,
    'stock': stock,
    'category_id': categoryId,
    'is_active': isActive,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}

/// Seeds [count] products named `Product 1` .. `Product <count>`.
///
/// `p1` is the **newest** record, because the products module's default ordering
/// is `created_at DESC`. That keeps the expected order in tests obvious:
/// page 1 starts at `p1` and descends from there.
void seedProducts(FakeDataBackend backend, int count) {
  final newest = DateTime.utc(2026, 6, count);
  for (var i = 1; i <= count; i++) {
    backend.seed(
      BackendResource.products,
      productRow(
        id: 'p$i',
        name: 'Product ${i.toString().padLeft(3, '0')}',
        price: i.toDouble(),
        stock: i,
        createdAt: newest.subtract(Duration(days: i - 1)).toIso8601String(),
      ),
    );
  }
}
