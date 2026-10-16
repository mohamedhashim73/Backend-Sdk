/// Provider-neutral routing for application resources and operations.
///
/// Applications declare their logical resource and operation keys once during
/// SDK setup. A provider then resolves those keys to its own target: a
/// Supabase table/RPC today, a Firebase collection/function or REST path later.
class BackendRouting {
  /// Logical resource key to provider target mappings.
  final Map<String, String> resourceTargets;

  /// Logical operation key to provider target mappings.
  final Map<String, String> operationTargets;

  /// Creates immutable routing maps.
  const BackendRouting({
    this.resourceTargets = const <String, String>{},
    this.operationTargets = const <String, String>{},
  });

  /// Returns the provider target for a logical resource key.
  String? resourceTarget(String key) => resourceTargets[key];

  /// Returns the provider target for a logical operation key.
  String? operationTarget(String key) => operationTargets[key];

  /// Returns a validation message when a routing entry is malformed.
  String? validate() {
    for (final entry in resourceTargets.entries) {
      if (!_isKey(entry.key) || entry.value.trim().isEmpty) {
        return 'Resource routing keys must be safe identifiers and targets '
            'must not be empty.';
      }
    }
    for (final entry in operationTargets.entries) {
      if (!_isOperationKey(entry.key) || entry.value.trim().isEmpty) {
        return 'Operation routing keys must contain safe dot-separated '
            'segments and targets must not be empty.';
      }
    }
    return null;
  }

  static bool _isKey(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

  static bool _isOperationKey(String value) => RegExp(
        r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
      ).hasMatch(value);
}
