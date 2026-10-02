import '../../contracts/data_backend.dart';
import '../../core/backend_resource.dart';
import '../../core/resource_codec.dart';
import '../../errors/backend_failure.dart';
import '../../filters/sort_condition.dart';
import '../../result/backend_result.dart';
import 'product_columns.dart';
import 'product_model.dart';
import 'product_requests.dart';

/// The column layout of the products record.
///
/// This is the single place in the package that maps between `Product` and a
/// backend row. It is pure: no I/O, no provider types, fully unit-testable.
abstract final class ProductColumnsDefinition {
  /// The descriptor used by the products repository.
  static const BackendResourceDescriptor descriptor = BackendResourceDescriptor(
    resource: BackendResource.products,
    primaryKeyField: ProductColumns.id,
    searchableFields: ProductColumns.searchable,
    defaultSorting: <SortCondition>[
      SortCondition.descending(ProductColumns.createdAt),
    ],
    softDeleteField: ProductColumns.deletedAt,
    createdAtField: ProductColumns.createdAt,
    updatedAtField: ProductColumns.updatedAt,
  );
}

/// Translates between [Product] and a backend record, and validates requests.
class ProductCodec
    implements
        ResourceCodec<Product, CreateProductRequest, UpdateProductRequest> {
  /// The maximum accepted product name length.
  static const int maxNameLength = 200;

  /// The maximum accepted unit price.
  static const double maxPrice = 1000000000;

  /// The maximum accepted stock quantity.
  static const int maxStock = 1000000000;

  /// Creates a product codec.
  const ProductCodec();

  @override
  BackendResourceDescriptor get descriptor =>
      ProductColumnsDefinition.descriptor;

  /// Converts a backend record into a [Product].
  ///
  /// Returns a `validation` failure when a required column is missing or has the
  /// wrong type, instead of throwing. A single malformed row is then skipped by
  /// the repository rather than failing the whole page.
  @override
  BackendResult<Product> decode(BackendRecord record) {
    final id = record[ProductColumns.id];
    if (id is! String || id.isEmpty) {
      return failureOf(
        CodecFailures.decode(
            'product',
            'the "${ProductColumns.id}" column is '
                'missing or is not a non-empty string.'),
      );
    }

    final name = record[ProductColumns.name];
    if (name is! String || name.isEmpty) {
      return failureOf(
        CodecFailures.decode(
          'product',
          'the "${ProductColumns.name}" column is missing or is not a '
              'non-empty string.',
        ),
      );
    }

    final price = _toDouble(record[ProductColumns.price]);
    if (price == null || price < 0) {
      return failureOf(
        CodecFailures.decode(
          'product',
          'the "${ProductColumns.price}" column is missing or is not a '
              'non-negative number.',
        ),
      );
    }

    final stock = _toInt(record[ProductColumns.stock]);
    if (stock == null || stock < 0) {
      return failureOf(
        CodecFailures.decode(
          'product',
          'the "${ProductColumns.stock}" column is missing or is not a '
              'non-negative integer.',
        ),
      );
    }

    final categoryId = record[ProductColumns.categoryId];
    if (categoryId != null && categoryId is! String) {
      return failureOf(
        CodecFailures.decode(
          'product',
          'the "${ProductColumns.categoryId}" column is not a string.',
        ),
      );
    }

    final isActive = record[ProductColumns.isActive];
    if (isActive != null && isActive is! bool) {
      return failureOf(
        CodecFailures.decode(
          'product',
          'the "${ProductColumns.isActive}" column is not a boolean.',
        ),
      );
    }

    return BackendSuccess<Product>(
      Product(
        id: id,
        name: name,
        price: price,
        stock: stock,
        categoryId: categoryId as String?,
        isActive: isActive as bool? ?? true,
        createdAt: _toDateTime(record[ProductColumns.createdAt]),
        updatedAt: _toDateTime(record[ProductColumns.updatedAt]),
        deletedAt: _toDateTime(record[ProductColumns.deletedAt]),
      ),
    );
  }

  @override
  BackendResult<Map<String, Object?>> encodeCreate(
      CreateProductRequest request) {
    return BackendSuccess<Map<String, Object?>>(<String, Object?>{
      ProductColumns.name: request.name.trim(),
      ProductColumns.price: request.price,
      ProductColumns.stock: request.stock,
      ProductColumns.categoryId: request.categoryId,
      ProductColumns.isActive: request.isActive,
    });
  }

  @override
  BackendResult<Map<String, Object?>> encodeUpdate(
      UpdateProductRequest request) {
    final values = <String, Object?>{};
    if (request.name != null) {
      values[ProductColumns.name] = request.name!.trim();
    }
    if (request.price != null) values[ProductColumns.price] = request.price;
    if (request.stock != null) values[ProductColumns.stock] = request.stock;
    if (request.isActive != null) {
      values[ProductColumns.isActive] = request.isActive;
    }
    if (request.clearCategoryId) {
      values[ProductColumns.categoryId] = null;
    } else if (request.categoryId != null) {
      values[ProductColumns.categoryId] = request.categoryId;
    }
    return BackendSuccess<Map<String, Object?>>(values);
  }

  @override
  BackendFailure? validateCreate(CreateProductRequest request) {
    return _validateName(request.name) ??
        _validatePrice(request.price) ??
        _validateStock(request.stock);
  }

  @override
  BackendFailure? validateUpdate(UpdateProductRequest request) {
    if (!request.hasChanges) {
      return CodecFailures.field('The update request does not change any '
          'field. Provide at least one field to update.');
    }
    BackendFailure? failure;
    if (request.name != null) failure = _validateName(request.name!);
    failure ??= request.price != null ? _validatePrice(request.price!) : null;
    failure ??= request.stock != null ? _validateStock(request.stock!) : null;
    if (failure != null) return failure;
    if (request.categoryId != null && request.clearCategoryId) {
      return CodecFailures.field(
        'A category and a category clear cannot be requested at the same time.',
      );
    }
    return null;
  }

  BackendFailure? _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return CodecFailures.field('A product name is required.');
    }
    if (trimmed.length > maxNameLength) {
      return CodecFailures.field(
        'The product name must not exceed $maxNameLength characters.',
      );
    }
    return null;
  }

  BackendFailure? _validatePrice(double price) {
    if (price.isNaN || price.isInfinite) {
      return CodecFailures.field('The product price must be a finite number.');
    }
    if (price < 0) {
      return CodecFailures.field('The product price must not be negative.');
    }
    if (price > maxPrice) {
      return CodecFailures.field(
        'The product price must not exceed $maxPrice.',
      );
    }
    return null;
  }

  BackendFailure? _validateStock(int stock) {
    if (stock < 0) {
      return CodecFailures.field('The product stock must not be negative.');
    }
    if (stock > maxStock) {
      return CodecFailures.field(
        'The product stock must not exceed $maxStock.',
      );
    }
    return null;
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _toDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }
    return null;
  }
}
