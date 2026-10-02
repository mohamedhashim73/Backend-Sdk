/// The column names of the users record.
abstract final class UserColumns {
  /// The primary key column, which is the account id.
  static const String id = 'id';

  /// The display name column.
  static const String displayName = 'display_name';

  /// The email column.
  static const String email = 'email';

  /// The avatar object key column.
  static const String avatarPath = 'avatar_path';

  /// The role column.
  static const String role = 'role';

  /// The active flag column.
  static const String isActive = 'is_active';

  /// The creation timestamp column.
  static const String createdAt = 'created_at';

  /// The last-modification timestamp column.
  static const String updatedAt = 'updated_at';

  /// The columns a free-text search term is matched against.
  static const List<String> searchable = <String>[displayName, email];
}

/// Named constants for the user filter fields.
abstract final class UserFilterField {
  /// The `email` column.
  static const String email = 'email';

  /// The `display_name` column.
  static const String displayName = 'display_name';

  /// The `role` column.
  static const String role = 'role';

  /// The `is_active` column.
  static const String isActive = 'is_active';
}

/// Named constants for the user sort fields.
abstract final class UserSortField {
  /// The `display_name` column.
  static const String displayName = 'display_name';

  /// The `email` column.
  static const String email = 'email';

  /// The `created_at` column.
  static const String createdAt = 'created_at';
}

/// A request to create a user profile.
///
/// In the normal flow the profile row is created by a database trigger on
/// sign-up, so this request exists for administrative and migration paths only.
class CreateUserRequest {
  /// The account id this profile belongs to. Required.
  final String id;

  /// The display name. Optional.
  final String? displayName;

  /// The email address. Optional.
  final String? email;

  /// The role assigned to the user. Optional, defaults to `user`.
  final String? role;

  /// Creates a create-user request.
  const CreateUserRequest({
    required this.id,
    this.displayName,
    this.email,
    this.role,
  });

  @override
  String toString() =>
      'CreateUserRequest(id: $id, displayName: $displayName, role: $role)';
}

/// A request to update a user profile.
class UpdateUserRequest {
  /// The new display name, or `null` to leave it unchanged.
  final String? displayName;

  /// The new email, or `null` to leave it unchanged.
  final String? email;

  /// The new avatar object key, or `null` to leave it unchanged.
  final String? avatarPath;

  /// The new role, or `null` to leave it unchanged.
  final String? role;

  /// The new active flag, or `null` to leave it unchanged.
  final bool? isActive;

  /// Creates a user update request.
  const UpdateUserRequest({
    this.displayName,
    this.email,
    this.avatarPath,
    this.role,
    this.isActive,
  });

  /// Whether this request would change at least one field.
  bool get hasChanges =>
      displayName != null ||
      email != null ||
      avatarPath != null ||
      role != null ||
      isActive != null;

  @override
  String toString() => 'UpdateUserRequest(displayName: $displayName, '
      'role: $role, isActive: $isActive)';
}
