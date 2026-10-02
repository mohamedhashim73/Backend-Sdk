import 'filter_condition.dart';

/// A typed sort instruction.
///
/// Ordering is always made deterministic by the SDK: when the supplied sorts do
/// not include the resource primary key, an ascending primary-key sort is
/// appended as a tie-breaker. Without that, two records with equal sort values
/// can swap places between pages and be returned twice.
class SortCondition {
  /// The database column to sort by.
  final String field;

  /// Whether to sort ascending (`true`) or descending (`false`).
  final bool ascending;

  /// Creates a sort instruction.
  const SortCondition(this.field, {this.ascending = true});

  /// Creates an ascending sort instruction.
  const SortCondition.ascending(String field) : this(field, ascending: true);

  /// Creates a descending sort instruction.
  const SortCondition.descending(String field) : this(field, ascending: false);

  /// Validates this sort instruction.
  ///
  /// Returns `null` when the sort is safe to use, otherwise a developer-facing
  /// description of the problem.
  String? validate() => FilterFieldValidator.validateFieldName(field);

  /// A stable identity used to de-duplicate concurrent page loads.
  String get cacheKey => '${ascending ? 'asc' : 'desc'}:$field';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SortCondition &&
          other.field == field &&
          other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);

  @override
  String toString() => 'SortCondition(${ascending ? 'asc' : 'desc'}: $field)';
}
