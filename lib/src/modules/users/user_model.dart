/// A user profile in the application's own users table.
///
/// This is the application-side profile, distinct from the authentication
/// account exposed by `BackendUser`. Keeping the two
/// separate means the auth provider's account lifecycle can change without
/// changing the shape of your own `users` table.
class User {
  /// The account id, which is also the primary key of this record.
  final String id;

  /// The display name.
  final String? displayName;

  /// The email address, when the profile stores one.
  final String? email;

  /// A free-form avatar object key in the `avatars` bucket.
  final String? avatarPath;

  /// The user's role, used by the database policies to gate admin access.
  final String? role;

  /// Whether the profile is active.
  final bool isActive;

  /// When the profile was created.
  final DateTime? createdAt;

  /// When the profile was last modified.
  final DateTime? updatedAt;

  /// Creates a user profile.
  const User({
    required this.id,
    this.displayName,
    this.email,
    this.avatarPath,
    this.role,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Whether this profile is an administrator, according to its stored role.
  ///
  /// This is a **UI convenience only**. It is not a security boundary:
  /// authorization is enforced by row level security in the database, and a
  /// client that lies about its role still gets nothing extra.
  bool get isAdmin => role == 'admin';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          other.id == id &&
          other.displayName == displayName &&
          other.email == email &&
          other.avatarPath == avatarPath &&
          other.role == role &&
          other.isActive == isActive &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        email,
        avatarPath,
        role,
        isActive,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'User(id: $id, displayName: $displayName, role: $role)';
}
