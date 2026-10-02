import 'filter_operator.dart';

/// A typed, validated filter applied to a backend query.
///
/// Filters are the only supported way to narrow a query from the application
/// layer. There is deliberately no escape hatch for raw SQL, raw PostgREST
/// filter strings, or arbitrary query fragments: field names are validated
/// against a strict identifier pattern and values are passed as typed
/// parameters, so a value can never change the shape of the generated query.
///
/// ```dart
/// FilterCondition.equals('categoryId', 'electronics');
/// FilterCondition.contains('name', 'phone');
/// FilterCondition.isNull('deletedAt');
/// ```
sealed class FilterCondition {
  const FilterCondition();

  /// Matches rows whose field equals [value].
  const factory FilterCondition.equals(
    String field,
    Object? value,
  ) = EqualsFilter;

  /// Matches rows whose field differs from [value].
  const factory FilterCondition.notEquals(
    String field,
    Object? value,
  ) = NotEqualsFilter;

  /// Matches rows whose field contains [value], ignoring case.
  const factory FilterCondition.contains(
    String field,
    String value,
  ) = ContainsFilter;

  /// Matches rows whose field starts with [value], ignoring case.
  const factory FilterCondition.startsWith(
    String field,
    String value,
  ) = StartsWithFilter;

  /// Matches rows whose field is greater than [value].
  const factory FilterCondition.greaterThan(
    String field,
    Object value,
  ) = GreaterThanFilter;

  /// Matches rows whose field is greater than or equal to [value].
  const factory FilterCondition.greaterThanOrEqual(
    String field,
    Object value,
  ) = GreaterThanOrEqualFilter;

  /// Matches rows whose field is less than [value].
  const factory FilterCondition.lessThan(
    String field,
    Object value,
  ) = LessThanFilter;

  /// Matches rows whose field is less than or equal to [value].
  const factory FilterCondition.lessThanOrEqual(
    String field,
    Object value,
  ) = LessThanOrEqualFilter;

  /// Matches rows whose field equals any element of [values].
  const factory FilterCondition.inList(
    String field,
    List<Object?> values,
  ) = InListFilter;

  /// Matches rows whose field matches the [FilterOperator.textSearch] query
  /// [term].
  const factory FilterCondition.textSearch(
    String field,
    String term,
  ) = TextSearchFilter;

  /// Matches rows whose field is `null`.
  const factory FilterCondition.isNull(String field) = IsNullFilter;

  /// Matches rows whose field is not `null`.
  const factory FilterCondition.isNotNull(String field) = IsNotNullFilter;

  /// The database column this filter applies to.
  String get field;

  /// The comparison this filter performs.
  FilterOperator get operator;

  /// The value the field is compared against, or `null` for unary filters.
  Object? get value;

  /// A stable identity used to de-duplicate concurrent page loads.
  String get cacheKey => '${operator.name}:$field:${value ?? '<null>'}';

  /// Validates this filter.
  ///
  /// Returns `null` when the filter is safe to use, otherwise a developer-facing
  /// description of the problem.
  String? validate() {
    final fieldError = FilterFieldValidator.validateFieldName(field);
    if (fieldError != null) return fieldError;
    return FilterFieldValidator.validateValue(operator, value);
  }
}

/// A strict, injection-resistant identifier check for column names.
///
/// Only ASCII letters, digits and underscores are permitted, the first
/// character may not be a digit, and the name may not exceed 63 characters.
/// This rules out the characters PostgREST uses as filter syntax
/// (`.`, `(`, `)`, `,`, `*`, quotes, whitespace), so a field name can never
/// terminate a condition and start a new one.
abstract final class FilterFieldValidator {
  /// Maximum length of an accepted column name.
  static const int maxFieldLength = 63;

  /// The accepted identifier pattern.
  static final RegExp pattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Returns `null` when [field] is a safe column name, otherwise a
  /// developer-facing description of the problem.
  static String? validateFieldName(String field) {
    if (field.isEmpty) {
      return 'A filter field name must not be empty.';
    }
    if (field.length > maxFieldLength) {
      return 'The filter field name "$field" exceeds $maxFieldLength '
          'characters.';
    }
    if (!pattern.hasMatch(field)) {
      return 'The filter field name "$field" is invalid. Only letters, digits '
          'and underscores are allowed, and it must not start with a digit.';
    }
    return null;
  }

  /// Returns `null` when [value] can be sent to the backend for [operator],
  /// otherwise a developer-facing description of the problem.
  static String? validateValue(FilterOperator operator, Object? value) {
    switch (operator) {
      case FilterOperator.isNull:
      case FilterOperator.isNotNull:
        return null;
      case FilterOperator.contains:
      case FilterOperator.startsWith:
      case FilterOperator.textSearch:
        if (value is! String) {
          return 'The filter operator ${operator.name} requires a String '
              'value, but got ${value.runtimeType}.';
        }
        if (value.isEmpty) {
          return 'The filter operator ${operator.name} requires a non-empty '
              'value.';
        }
        return null;
      case FilterOperator.inList:
        if (value is! List) {
          return 'The filter operator ${operator.name} requires a List value, '
              'but got ${value.runtimeType}.';
        }
        if (value.isEmpty) {
          return 'The filter operator ${operator.name} requires a non-empty '
              'list.';
        }
        return null;
      case FilterOperator.equals:
      case FilterOperator.notEquals:
        // Only equality may compare against `null`; the ordering operators take
        // a non-nullable value, so a null there is a caller bug.
        return _isSupportedScalar(value)
            ? null
            : 'The filter operator ${operator.name} does not support values '
                'of type ${value.runtimeType}.';
      case FilterOperator.greaterThan:
      case FilterOperator.greaterThanOrEqual:
      case FilterOperator.lessThan:
      case FilterOperator.lessThanOrEqual:
        if (value == null) {
          return 'The filter operator ${operator.name} requires a non-null '
              'value.';
        }
        return _isSupportedScalar(value)
            ? null
            : 'The filter operator ${operator.name} does not support values '
                'of type ${value.runtimeType}.';
    }
  }

  static bool _isSupportedScalar(Object? value) =>
      value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime;

  /// Converts a [DateTime] filter value into the representation the backend
  /// expects, leaving other scalars untouched.
  static Object? normalizeValue(Object? value) {
    return value is DateTime ? value.toUtc().toIso8601String() : value;
  }
}

/// Base implementation shared by every concrete filter.
sealed class _FieldFilter extends FilterCondition {
  const _FieldFilter(this.field);

  @override
  final String field;
}

/// Matches rows whose field equals [value].
final class EqualsFilter extends _FieldFilter {
  /// Creates an equality filter.
  const EqualsFilter(super.field, this.value);

  @override
  final Object? value;

  @override
  FilterOperator get operator => FilterOperator.equals;
}

/// Matches rows whose field differs from [value].
final class NotEqualsFilter extends _FieldFilter {
  /// Creates an inequality filter.
  const NotEqualsFilter(super.field, this.value);

  @override
  final Object? value;

  @override
  FilterOperator get operator => FilterOperator.notEquals;
}

/// Matches rows whose field contains [value], ignoring case.
final class ContainsFilter extends _FieldFilter {
  /// Creates a case-insensitive substring filter.
  const ContainsFilter(super.field, this.value);

  @override
  final String value;

  @override
  FilterOperator get operator => FilterOperator.contains;
}

/// Matches rows whose field starts with [value], ignoring case.
final class StartsWithFilter extends _FieldFilter {
  /// Creates a case-insensitive prefix filter.
  const StartsWithFilter(super.field, this.value);

  @override
  final String value;

  @override
  FilterOperator get operator => FilterOperator.startsWith;
}

/// Matches rows whose field is greater than [value].
final class GreaterThanFilter extends _FieldFilter {
  /// Creates a greater-than filter.
  const GreaterThanFilter(super.field, this.value);

  @override
  final Object value;

  @override
  FilterOperator get operator => FilterOperator.greaterThan;
}

/// Matches rows whose field is greater than or equal to [value].
final class GreaterThanOrEqualFilter extends _FieldFilter {
  /// Creates a greater-than-or-equal filter.
  const GreaterThanOrEqualFilter(super.field, this.value);

  @override
  final Object value;

  @override
  FilterOperator get operator => FilterOperator.greaterThanOrEqual;
}

/// Matches rows whose field is less than [value].
final class LessThanFilter extends _FieldFilter {
  /// Creates a less-than filter.
  const LessThanFilter(super.field, this.value);

  @override
  final Object value;

  @override
  FilterOperator get operator => FilterOperator.lessThan;
}

/// Matches rows whose field is less than or equal to [value].
final class LessThanOrEqualFilter extends _FieldFilter {
  /// Creates a less-than-or-equal filter.
  const LessThanOrEqualFilter(super.field, this.value);

  @override
  final Object value;

  @override
  FilterOperator get operator => FilterOperator.lessThanOrEqual;
}

/// Matches rows whose field equals any element of [value].
final class InListFilter extends _FieldFilter {
  /// Creates an `in` filter.
  const InListFilter(super.field, this.value);

  @override
  final List<Object?> value;

  @override
  FilterOperator get operator => FilterOperator.inList;
}

/// Matches rows whose field matches the [value] search term.
final class TextSearchFilter extends _FieldFilter {
  /// Creates a full-text search filter.
  const TextSearchFilter(super.field, this.value);

  @override
  final String value;

  @override
  FilterOperator get operator => FilterOperator.textSearch;
}

/// Matches rows whose field is `null`.
final class IsNullFilter extends _FieldFilter {
  /// Creates an `is null` filter.
  const IsNullFilter(super.field);

  @override
  Object? get value => null;

  @override
  FilterOperator get operator => FilterOperator.isNull;
}

/// Matches rows whose field is not `null`.
final class IsNotNullFilter extends _FieldFilter {
  /// Creates an `is not null` filter.
  const IsNotNullFilter(super.field);

  @override
  Object? get value => null;

  @override
  FilterOperator get operator => FilterOperator.isNotNull;
}
