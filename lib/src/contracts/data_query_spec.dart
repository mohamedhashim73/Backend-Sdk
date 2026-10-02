import '../filters/filter_condition.dart';
import '../filters/sort_condition.dart';

/// A validated, provider-agnostic description of a read query.
///
/// A [DataQuerySpec] is what a module repository hands to a provider. It carries
/// only typed intents - filters, sorts, a search term and an inclusive range -
/// and never a table name or a raw query string.
class DataQuerySpec {
  /// The inclusive index of the first record to return.
  final int from;

  /// The **inclusive** index of the last record to return.
  ///
  /// Supabase/PostgREST `range(from, to)` includes both ends, so
  /// `from: 0, to: 19` returns 20 records.
  final int to;

  /// The free-text search term, or `null`.
  final String? search;

  /// The validated filters to apply.
  final List<FilterCondition> filters;

  /// The validated sort instructions, including the stable tie-breaker.
  final List<SortCondition> sorting;

  /// Whether the exact total number of matching records is required.
  final bool includeTotalCount;

  /// Creates a query specification.
  const DataQuerySpec({
    required this.from,
    required this.to,
    this.search,
    this.filters = const [],
    this.sorting = const [],
    this.includeTotalCount = false,
  });

  /// The maximum number of records this query may return.
  int get limit => to - from + 1;

  @override
  String toString() {
    return 'DataQuerySpec(range: $from..$to inclusive, search: $search, '
        'filters: ${filters.length}, sorting: ${sorting.length}, '
        'includeTotalCount: $includeTotalCount)';
  }
}
