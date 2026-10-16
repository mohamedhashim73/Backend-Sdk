/// Common immutable identity and audit fields for application entities.
///
/// Feature models remain owned by applications. This base type only keeps the
/// fields that are shared independently of a backend provider.
abstract class ManagedModel {
  final String id;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;

  const ManagedModel({
    required this.id,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  List<Object?> get props => [id];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType || other is! ManagedModel) {
      return false;
    }

    final left = props;
    final right = other.props;
    if (left.length != right.length) return false;

    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hashAll(props);
}
