import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

/// Creates and owns the Supabase client for a provider instance.
///
/// This indirection exists for two reasons:
///
/// * the SDK can be unit-tested without a Flutter binding, a `SharedPreferences`
///   instance or a network, because tests inject their own factory;
/// * the Flutter-specific `Supabase.initialize` call, which is the only part of
///   this package that needs platform storage, is confined to one function.
typedef SupabaseClientFactory = Future<SupabaseClient> Function(
  SupabaseClientOptions options,
);

/// Everything the Supabase provider needs in order to build a client.
class SupabaseClientOptions {
  /// The Supabase project URL.
  final String url;

  /// The project's **anon** (publishable) key.
  ///
  /// Never the service-role or secret key: a compiled Flutter binary is
  /// readable by its users, so a secret key shipped in a client is compromised
  /// the moment the app is published.
  final String apiKey;

  /// Whether Supabase's own debug logging is enabled.
  final bool debug;

  /// Creates client options.
  const SupabaseClientOptions({
    required this.url,
    required this.apiKey,
    this.debug = false,
  });

  /// A log-safe description. Never includes the key.
  @override
  String toString() =>
      'SupabaseClientOptions(url: $url, apiKey: [redacted], debug: $debug)';
}

/// The default factory, backed by `supabase_flutter`.
///
/// This is the single place in the package that touches Flutter platform
/// storage for session persistence.
Future<SupabaseClient> createSupabaseClientWithFlutter(
  SupabaseClientOptions options,
) {
  return Supabase.initialize(
    url: options.url,
    publishableKey: options.apiKey,
    debug: options.debug,
  ).then((instance) => instance.client);
}
