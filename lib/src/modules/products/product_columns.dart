/// The column names of the products record.
///
/// Declared in the module, not in the application, so a schema rename is a
/// one-file change reviewed in this package rather than a search across every
/// feature. The application references these through [ProductFilterField] and
/// the typed filter factories, never as raw strings.
abstract final class ProductColumns {
  /// The primary key column.
  static const String id = 'id';

  /// The display name column.
  static const String name = 'name';

  /// The unit price column.
  static const String price = 'price';

  /// The stock quantity column.
  static const String stock = 'stock';

  /// The owning category column.
  static const String categoryId = 'category_id';

  /// The active flag column.
  static const String isActive = 'is_active';

  /// The creation timestamp column.
  static const String createdAt = 'created_at';

  /// The last-modification timestamp column.
  static const String updatedAt = 'updated_at';

  /// The soft-delete timestamp column.
  static const String deletedAt = 'deleted_at';

  /// The columns a free-text search term is matched against.
  static const List<String> searchable = <String>[name, categoryId];
}

/// Named constants for the product filter fields, so a typo is a compile error
/// instead of a silently empty result set.
///
/// ```dart
/// FilterCondition.equals(ProductFilterField.categoryId, 'electronics');
/// ```
abstract final class ProductFilterField {
  /// The `name` column.
  static const String name = 'name';

  /// The `category_id` column.
  static const String categoryId = 'category_id';

  /// The `is_active` column.
  static const String isActive = 'is_active';

  /// The `stock` column.
  static const String stock = 'stock';

  /// The `price` column.
  static const String price = 'price';

  /// The `created_at` column.
  static const String createdAt = 'created_at';
}

/// Named constants for the product sort fields.
abstract final class ProductSortField {
  /// The `name` column.
  static const String name = 'name';

  /// The `price` column.
  static const String price = 'price';

  /// The `stock` column.
  static const String stock = 'stock';

  /// The `created_at` column.
  static const String createdAt = 'created_at';
}
