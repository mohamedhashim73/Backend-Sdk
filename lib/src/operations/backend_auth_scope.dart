/// Authentication requirement for an application operation.
enum BackendAuthScope {
  /// The operation must run anonymously.
  anonymous,

  /// The operation may run for either an anonymous or signed-in user.
  optional,

  /// The operation requires a valid authenticated session.
  required,
}
