/// The field names accepted by a [CreateProductRequest].
enum CreateProductField {
  /// The display name. Required, 1 to 200 characters.
  name,

  /// The unit price. Required, must be finite and non-negative.
  price,

  /// The stock quantity. Optional, defaults to 0.
  stock,

  /// The owning category. Optional.
  categoryId,

  /// Whether the product is immediately active. Optional, defaults to `false`.
  isActive,
}

/// The field names accepted by an [UpdateProductRequest].
enum UpdateProductField {
  /// The display name.
  name,

  /// The unit price.
  price,

  /// The stock quantity.
  stock,

  /// The owning category. Passing `null` clears the category.
  categoryId,

  /// The active flag.
  isActive,
}

/// A request to create a product.
///
/// Every field is validated locally before any network call, so an invalid
/// product is rejected on the device with a precise message.
///
/// ```dart
/// final result = await BackendSdk.instance.products.create(
///   CreateProductRequest(name: 'Phone', price: 1000),
/// );
/// ```
class CreateProductRequest {
  /// The display name. Required.
  final String name;

  /// The unit price. Required.
  final double price;

  /// The initial stock quantity. Defaults to 0.
  final int stock;

  /// The owning category. Optional.
  final String? categoryId;

  /// Whether the product starts out active. Defaults to `false`.
  final bool isActive;

  /// Creates a product request.
  const CreateProductRequest({
    required this.name,
    required this.price,
    this.stock = 0,
    this.categoryId,
    this.isActive = false,
  });

  @override
  String toString() => 'CreateProductRequest(name: $name, price: $price, '
      'stock: $stock, categoryId: $categoryId, isActive: $isActive)';
}

/// A request to update a product.
///
/// All fields are optional; only the ones that are set are written. An empty
/// request is rejected as a validation failure rather than sent as a no-op.
///
/// ```dart
/// final result = await BackendSdk.instance.products.update(
///   id: productId,
///   request: const UpdateProductRequest(name: 'Updated Phone'),
/// );
/// ```
class UpdateProductRequest {
  /// The new display name, or `null` to leave it unchanged.
  final String? name;

  /// The new unit price, or `null` to leave it unchanged.
  final double? price;

  /// The new stock quantity, or `null` to leave it unchanged.
  final int? stock;

  /// The new category, or `null` to leave it unchanged.
  ///
  /// Use [clearCategoryId] to explicitly detach the product from its category,
  /// because `null` on its own means "unchanged".
  final String? categoryId;

  /// The new active flag, or `null` to leave it unchanged.
  final bool? isActive;

  /// Whether to detach the product from its category.
  final bool clearCategoryId;

  /// Creates a product update request.
  const UpdateProductRequest({
    this.name,
    this.price,
    this.stock,
    this.categoryId,
    this.isActive,
    this.clearCategoryId = false,
  });

  /// Whether this request would change at least one field.
  bool get hasChanges =>
      name != null ||
      price != null ||
      stock != null ||
      categoryId != null ||
      isActive != null ||
      clearCategoryId;

  @override
  String toString() => 'UpdateProductRequest(name: $name, price: $price, '
      'stock: $stock, categoryId: $categoryId, isActive: $isActive, '
      'clearCategoryId: $clearCategoryId)';
}
