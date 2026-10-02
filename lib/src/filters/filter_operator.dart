/// The comparison operators supported by `FilterCondition`.
///
/// The enum is provider-agnostic. Each provider maps these onto its own query
/// syntax; the application never writes that syntax.
enum FilterOperator {
  /// Field equals the value (`=`).
  equals,

  /// Field does not equal the value (`!=`).
  notEquals,

  /// Field is greater than the value.
  greaterThan,

  /// Field is greater than or equal to the value.
  greaterThanOrEqual,

  /// Field is less than the value.
  lessThan,

  /// Field is less than or equal to the value.
  lessThanOrEqual,

  /// Case-insensitive substring match (`contains`).
  contains,

  /// Case-insensitive prefix match.
  startsWith,

  /// Field is `null` (`is.null`).
  isNull,

  /// Field is not `null` (`not.is.null`).
  isNotNull,

  /// Field equals any of the listed values (`in`).
  inList,

  /// Field appears in the given search term.
  textSearch,
}
