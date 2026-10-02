/// A backend entity that this SDK knows how to read and write.
///
/// The application layer references resources through this enum and never
/// through table, collection or endpoint names. Mapping a resource onto a
/// vendor-specific table is the responsibility of the provider, which keeps
/// schema details out of the consuming application.
///
/// Adding a module to an application means adding a value here together with a
/// typed repository; it never means teaching the UI about SQL.
enum BackendResource {
  /// Product catalogue records, exposed as
  /// `ProductsRepository`.
  products,

  /// Application users, exposed as
  /// `UsersRepository`.
  users,
}
