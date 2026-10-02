/// A provider-agnostic user account.
///
/// This is the only user type the application ever handles. Vendor user objects
/// (for example Supabase's `User`) are converted by the provider mapper and are
/// never exposed.
class BackendUser {
  /// The stable unique identifier of the account.
  final String id;

  /// The verified or pending email address, when the provider exposes one.
  final String? email;

  /// Provider-defined, user-writable profile attributes.
  ///
  /// Never contains credentials. Treat unknown keys as untrusted and validate
  /// before use.
  final Map<String, dynamic> metadata;

  /// When the account was created.
  final DateTime? createdAt;

  /// The most recent successful sign-in time.
  final DateTime? lastSignInAt;

  /// Creates a backend user.
  const BackendUser({
    required this.id,
    this.email,
    this.metadata = const {},
    this.createdAt,
    this.lastSignInAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendUser &&
          other.id == id &&
          other.email == email &&
          other.createdAt == createdAt &&
          other.lastSignInAt == lastSignInAt;

  @override
  int get hashCode => Object.hash(id, email, createdAt, lastSignInAt);

  @override
  String toString() => 'BackendUser(id: $id, email: $email)';
}
