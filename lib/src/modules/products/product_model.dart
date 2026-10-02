/// A product in the catalogue.
///
/// This is the only product shape the application handles. The backend record
/// it is built from never escapes the provider and mapper layers, and the
/// application never writes a table name, a column name or a filter string.
///
/// ```dart
/// final result = await BackendSdk.instance.products.getPage(
///   request: const PageRequest(page: 1, pageSize: 20),
/// );
/// ```
class Product {
  /// The stable unique identifier of the product.
  final String id;

  /// The display name.
  final String name;

  /// The unit price.
  final double price;

  /// The number of units in stock. Never negative.
  final int stock;

  /// The category this product belongs to, when it has one.
  final String? categoryId;

  /// Whether the product is visible and purchasable.
  final bool isActive;

  /// When the product was created.
  final DateTime? createdAt;

  /// When the product was last modified.
  final DateTime? updatedAt;

  /// When the product was soft-deleted, or `null` when it is live.
  ///
  /// A soft-deleted product is excluded from every read the SDK performs. The
  /// field is exposed so an administrative view can show archived records.
  final DateTime? deletedAt;

  /// Creates a product.
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.isActive,
    this.categoryId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  /// Whether the product has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// The price formatted as a non-localised numeric string.
  ///
  /// The application decides how to render currency; the SDK does not assume a
  /// locale or a currency symbol.
  String get priceLabel => price.toStringAsFixed(2);

  /// Returns a copy of this product with the given fields replaced.
  Product copyWith({
    String? id,
    String? name,
    double? price,
    int? stock,
    String? categoryId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      categoryId: categoryId ?? this.categoryId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Product &&
        other.id == id &&
        other.name == name &&
        other.price == price &&
        other.stock == stock &&
        other.categoryId == categoryId &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        price,
        stock,
        categoryId,
        isActive,
        createdAt,
        updatedAt,
        deletedAt,
      );

  @override
  String toString() => 'Product(id: $id, name: $name, price: $price, '
      'stock: $stock, isActive: $isActive, isDeleted: $isDeleted)';
}
