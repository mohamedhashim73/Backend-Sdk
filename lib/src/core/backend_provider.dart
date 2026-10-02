/// The backend vendors this SDK can be configured with.
///
/// Only [BackendProvider.supabase] is implemented today. The remaining values
/// are declared so that configuration written against a future provider fails
/// with a clear, typed
/// `BackendErrorType.unsupportedProvider`
/// failure instead of a compile error.
enum BackendProvider {
  /// The Supabase provider, the reference implementation shipped with this
  /// package.
  supabase,

  /// A plain REST provider. Reserved for a future release.
  rest,

  /// Firebase (Firestore/Auth/Storage). Reserved for a future release.
  firebase,
}
