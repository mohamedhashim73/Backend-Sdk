import 'backend_provider.dart';

/// Immutable, validated configuration for a single `BackendSdk` instance.
///
/// The configuration is deliberately provider-agnostic: it carries an endpoint
/// and a public key rather than a vendor client. The Supabase factory
/// ([BackendConfiguration.supabase]) is a named constructor for readability; it
/// produces exactly the same object as the default constructor, so switching to
/// another provider later only changes [BackendConfiguration.provider] and the
/// endpoint details.
///
/// ```dart
/// const config = BackendConfiguration.supabase(
///   url: String.fromEnvironment('SUPABASE_URL'),
///   apiKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
/// );
/// ```
class BackendConfiguration {
  /// The backend vendor that will service every operation.
  final BackendProvider provider;

  /// The backend endpoint URL, for example the Supabase project URL.
  ///
  /// Must be an absolute `http`/`https` URI without query or fragment parts.
  final String? url;

  /// The public, publishable API key for [url].
  ///
  /// This is the provider's *anon* (publishable) key. It is not a secret, but it
  /// grants nothing on its own: every table must be protected by row level
  /// security. Never put a service-role or secret key here - a Flutter binary
  /// is fully readable by the end user.
  final String? apiKey;

  /// The maximum time a single backend call may take before it fails with
  /// `BackendErrorType.timeout`.
  final Duration requestTimeout;

  /// Whether the SDK emits log entries.
  ///
  /// Off by default. Even when enabled, values are redacted before they reach
  /// the sink.
  final bool enableLogging;

  /// How many additional attempts are made after a retryable failure.
  ///
  /// `0` disables retries. This is a *retry* count, so the total number of
  /// attempts is `maxRetries + 1`.
  final int maxRetries;

  /// The delay before the first retry.
  final Duration retryDelay;

  /// The exponential backoff multiplier applied to [retryDelay] on each
  /// subsequent retry.
  ///
  /// `2.0` means 200ms, 400ms, 800ms, and so on.
  final double retryBackoffMultiplier;

  /// The upper bound applied to any single backoff delay.
  final Duration maxRetryDelay;

  /// Creates a configuration.
  ///
  /// Prefer the [BackendConfiguration.supabase] named constructor for
  /// readability when targeting Supabase.
  const BackendConfiguration({
    required this.provider,
    this.url,
    this.apiKey,
    this.requestTimeout = const Duration(seconds: 30),
    this.enableLogging = false,
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 200),
    this.retryBackoffMultiplier = 2.0,
    this.maxRetryDelay = const Duration(seconds: 10),
  });

  /// Creates a configuration for the Supabase provider.
  ///
  /// [url] is the project URL from the Supabase dashboard and [apiKey] is the
  /// project **anon** key (now called the *publishable* key). Both must be
  /// supplied at runtime from a build-time environment; never hardcode them.
  factory BackendConfiguration.supabase({
    required String url,
    required String apiKey,
    Duration requestTimeout = const Duration(seconds: 30),
    bool enableLogging = false,
    int maxRetries = 2,
    Duration retryDelay = const Duration(milliseconds: 200),
    double retryBackoffMultiplier = 2.0,
    Duration maxRetryDelay = const Duration(seconds: 10),
  }) {
    return BackendConfiguration(
      provider: BackendProvider.supabase,
      url: url,
      apiKey: apiKey,
      requestTimeout: requestTimeout,
      enableLogging: enableLogging,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      retryBackoffMultiplier: retryBackoffMultiplier,
      maxRetryDelay: maxRetryDelay,
    );
  }

  /// Returns a copy of this configuration with the given fields replaced.
  BackendConfiguration copyWith({
    BackendProvider? provider,
    String? url,
    String? apiKey,
    Duration? requestTimeout,
    bool? enableLogging,
    int? maxRetries,
    Duration? retryDelay,
    double? retryBackoffMultiplier,
    Duration? maxRetryDelay,
  }) {
    return BackendConfiguration(
      provider: provider ?? this.provider,
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      enableLogging: enableLogging ?? this.enableLogging,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      retryBackoffMultiplier:
          retryBackoffMultiplier ?? this.retryBackoffMultiplier,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
    );
  }

  @override
  String toString() {
    // Deliberately omits url and apiKey.
    return 'BackendConfiguration(provider: ${provider.name}, '
        'requestTimeout: ${requestTimeout.inSeconds}s, '
        'enableLogging: $enableLogging, maxRetries: $maxRetries)';
  }
}
