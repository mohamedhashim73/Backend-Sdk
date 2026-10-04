import 'dart:async';
import 'dart:typed_data';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// Build-time configuration.
///
/// Neither value is a secret and neither is hardcoded: both come from
/// `--dart-define`. The anon / publishable key is readable by anyone who
/// installs the app, which is exactly why every table must be protected by row
/// level security (see `supabase/migrations`).
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
/// ```
abstract final class AppEnvironment {
  /// The Supabase project URL.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's **anon** (publishable) key. Never the service-role key.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Whether both values were supplied at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

/// Initializes the SDK once, before the first frame.
///
/// The whole point of the example: the application imports only
/// `package:backend_sdk/backend_sdk.dart` and never touches Supabase.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppEnvironment.isConfigured) {
    debugPrint(
      'backend_sdk: SUPABASE_URL and SUPABASE_ANON_KEY were not supplied. '
      'Run with --dart-define=SUPABASE_URL=... '
      '--dart-define=SUPABASE_ANON_KEY=...',
    );
    return;
  }

  await BackendSdk.initialize(
    provider: BackendProvider.supabase,
    configuration: BackendConfiguration.supabase(
      url: AppEnvironment.supabaseUrl,
      apiKey: AppEnvironment.supabaseAnonKey,
      enableLogging: kDebugMode,
      maxRetries: 2,
      requestTimeout: const Duration(seconds: 30),
    ),
  );
}

/// Initializes the SDK, then starts the app.
///
/// [bootstrap] is the first thing that runs. It never reads
/// `BackendSdk.instance`: `BackendSdk.initialize` registers the built-in
/// providers itself, so this is the only entry point an application needs.
Future<void> main() async {
  await bootstrap();
  runApp(const BackendSdkExampleApp());
}

/// The example application.
class BackendSdkExampleApp extends StatelessWidget {
  /// Creates the example application.
  const BackendSdkExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'backend_sdk example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: AppEnvironment.isConfigured
          ? const SignInPage()
          : const _NotConfiguredPage(),
    );
  }
}

/// Shown when the required `--dart-define` values are missing.
class _NotConfiguredPage extends StatelessWidget {
  const _NotConfiguredPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('backend_sdk example')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No credentials configured.\n\n'
          'Run the example with:\n\n'
          'flutter run \\\n'
          '  --dart-define=SUPABASE_URL=https://<project>.supabase.co \\\n'
          '  --dart-define=SUPABASE_ANON_KEY=sb_publishable_...\n\n'
          'Then apply the schema in supabase/migrations/ with '
          '`supabase db push`.',
        ),
      ),
    );
  }
}

/// Shows the user-safe message for a failure.
///
/// `BackendFailure.safeMessage` is the only string this app renders. The
/// technical detail stays in `failure.message` and `failure.code`, which are
/// meant for logs.
void showFailure(BuildContext context, BackendFailure failure) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure.safeMessage),
        // A retryable failure is worth offering a retry button; an
        // authorization failure is not.
        action: failure.isRetryable
            ? SnackBarAction(
                label: 'Retry',
                onPressed: () {},
              )
            : null,
      ),
    );
}

/// A sign-in screen that demonstrates the auth surface.
class SignInPage extends StatefulWidget {
  /// Creates the sign-in screen.
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);

    final BackendResult<BackendSession> result =
        await BackendSdk.instance.auth.login(
      email: _email.text,
      password: _password.text,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    result.when(
      success: (_) => Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ProductListPage()),
      ),
      failure: (failure) => showFailure(context, failure),
    );
  }

  Future<void> _signUp() async {
    setState(() => _busy = true);

    final result = await BackendSdk.instance.auth.signUp(
      email: _email.text,
      password: _password.text,
      metadata: <String, dynamic>{'display_name': _email.text.split('@').first},
      emailRedirectTo: 'https://example.com/confirm',
    );

    if (!mounted) return;
    setState(() => _busy = false);

    result.when(
      success: (session) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Signed up as ${session.user.email}.'),
          ),
        ),
      failure: (failure) => showFailure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _signUp,
            child: const Text('Sign up'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _signIn(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: Text(_busy ? 'Working…' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A paginated, searchable, realtime product list.
class ProductListPage extends StatefulWidget {
  /// Creates the product list.
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  static const int _pageSize = 20;

  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<Product> _items = <Product>[];

  bool _hasMore = true;
  bool _loading = false;
  bool _realtimeConnected = false;
  int _page = 1;

  RealtimeSubscription<Product>? _watcher;
  StreamSubscription<RealtimeEvent<Product>>? _events;
  CancellationToken? _inFlight;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load(reset: true));
    _watchProducts();
  }

  @override
  void dispose() {
    // Disposal order matters and every step is idempotent:
    // cancel the listener, dispose the subscription, abandon in-flight work.
    unawaited(_events?.cancel());
    unawaited(_watcher?.dispose());
    _inFlight?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _watchProducts() {
    // No decoder and no channel name to supply: ProductsRepository registered
    // the decoder when it was constructed, so this yields Product events.
    final RealtimeSubscription<Product> watcher =
        BackendSdk.instance.realtime.watch<Product>(
      resource: BackendResource.products,
    );
    _watcher = watcher;

    unawaited(
      watcher.ready.then((_) {
        if (!mounted) return;
        setState(() => _realtimeConnected = true);
        _events = watcher.events.listen(_onEvent);
      }),
    );
  }

  void _onEvent(RealtimeEvent<Product> event) {
    if (!mounted) return;

    setState(() {
      switch (event.type) {
        case RealtimeEventType.inserted:
        case RealtimeEventType.updated:
          final Product? updated = event.newData;
          if (updated == null) return;
          final int index =
              _items.indexWhere((Product product) => product.id == updated.id);
          if (index >= 0) {
            _items[index] = updated;
          } else if (event.type == RealtimeEventType.inserted) {
            _items.insert(0, updated);
          }
        case RealtimeEventType.deleted:
          final Product? removed = event.oldData;
          if (removed == null) return;
          _items.removeWhere((Product product) => product.id == removed.id);
      }
    });
  }

  Future<void> _onScroll() async {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      await _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) return;

    setState(() => _loading = true);
    _inFlight?.cancel();
    _inFlight = CancellationToken();

    if (reset) {
      _page = 1;
      _hasMore = true;
    }

    final String term = _search.text.trim();
    final BackendResult<PageResult<Product>> result =
        await BackendSdk.instance.products.getPage(
      request: PageRequest(
        page: _page,
        pageSize: _pageSize,
        search: term.isEmpty ? null : term,
        filters: const <FilterCondition>[
          FilterCondition.equals(ProductFilterField.isActive, true),
        ],
        sorting: const <SortCondition>[
          SortCondition.descending(ProductSortField.createdAt),
        ],
        includeTotalCount: reset,
      ),
      cancellationToken: _inFlight,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    result.when(
      success: (PageResult<Product> page) {
        setState(() {
          if (reset) _items.clear();
          _items.addAll(page.items);
          _hasMore = page.hasMore;
          if (page.hasMore) _page++;
        });
      },
      failure: (BackendFailure failure) {
        // A cancelled request is the expected outcome of a new keystroke, not
        // something to report to the user.
        if (failure.type == BackendErrorType.cancelled) return;
        showFailure(context, failure);
      },
    );
  }

  Future<void> _createSampleProduct() async {
    final BackendResult<Product> result =
        await BackendSdk.instance.products.create(
      CreateProductRequest(
        name: 'Example ${_items.length + 1}',
        price: 1000,
        stock: 10,
        isActive: true,
      ),
    );

    if (!mounted) return;
    result.when(
      success: (_) {},
      failure: (BackendFailure failure) => showFailure(context, failure),
    );
  }

  Future<void> _deactivate(Product product) async {
    final BackendResult<Product> result =
        await BackendSdk.instance.products.update(
      product.id,
      const UpdateProductRequest(isActive: false),
    );

    if (!mounted) return;
    result.when(
      success: (_) {},
      failure: (BackendFailure failure) => showFailure(context, failure),
    );
  }

  Future<void> _archive(Product product) async {
    final BackendResult<Product> result =
        await BackendSdk.instance.products.softDelete(product.id);

    if (!mounted) return;
    result.when(
      success: (_) {},
      failure: (BackendFailure failure) => showFailure(context, failure),
    );
  }

  Future<void> _signOut() async {
    final BackendResult<void> result = await BackendSdk.instance.auth.logout();
    if (!mounted) return;

    result.when(
      success: (_) => Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SignInPage()),
      ),
      failure: (BackendFailure failure) => showFailure(context, failure),
    );
  }

  /// Uploads a small generated file to demonstrate the storage surface.
  Future<void> _uploadSampleFile() async {
    final Uint8List bytes = Uint8List.fromList(
      List<int>.generate(1024, (int i) => i % 256),
    );

    final BackendResult<UploadedFile> result =
        await BackendSdk.instance.storage.upload(
      request: UploadFileRequest(
        bucket: StorageBucket.general,
        path: 'demo/${DateTime.now().millisecondsSinceEpoch}.bin',
        bytes: bytes,
        contentType: 'application/octet-stream',
      ),
    );

    if (!mounted) return;
    result.when(
      success: (UploadedFile file) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
              content: Text('Stored ${file.path} (${file.sizeInBytes} B)')),
        ),
      failure: (BackendFailure failure) => showFailure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Upload sample file',
            onPressed: _uploadSampleFile,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Search products',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _load(reset: true),
                    ),
                  ),
                  onSubmitted: (_) => _load(reset: true),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Icon(
                      _realtimeConnected ? Icons.circle : Icons.circle_outlined,
                      size: 10,
                      color: _realtimeConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _realtimeConnected ? 'live' : 'connecting…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      '${_items.length} loaded',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _items.isEmpty && !_loading
          ? const Center(child: Text('No products match.'))
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                controller: _scroll,
                itemCount: _items.length,
                itemBuilder: (BuildContext context, int index) {
                  final Product product = _items[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.priceLabel} · stock ${product.stock}'
                      '${product.categoryId == null ? '' : ' · ${product.categoryId}'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Deactivate',
                          onPressed: () => _deactivate(product),
                          icon: const Icon(Icons.toggle_off_outlined),
                        ),
                        IconButton(
                          tooltip: 'Archive',
                          onPressed: () => _archive(product),
                          icon: const Icon(Icons.archive_outlined),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createSampleProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ============================================================================
// Typed mapping between layers
// ============================================================================
// `backend_sdk` returns its own models. An application usually wants its own at
// the edge of a data source, so no SDK type reaches the domain layer. `map` and
// `mapItems` do that conversion in one typed step, with no `dynamic` and no
// provider involvement.

/// An application-side user model.
class AppUser {
  /// Creates an application user.
  const AppUser({required this.id, required this.displayName});

  /// The account id.
  final String id;

  /// The display name, falling back to the email local part.
  final String displayName;

  /// Converts an SDK user into an application user.
  ///
  /// This is the exact signature [BackendResult.map] expects, which is why the
  /// tear-off can be passed directly with no closure and no type argument.
  static AppUser fromBackendUser(BackendUser user) {
    final String? name = user.metadata['display_name'] as String?;
    return AppUser(
      id: user.id,
      displayName: name ?? user.email?.split('@').first ?? user.id,
    );
  }

  @override
  String toString() => 'AppUser($id, $displayName)';
}

/// An application-side product model.
class AppProduct {
  /// Creates an application product.
  const AppProduct({
    required this.id,
    required this.title,
    required this.priceInCents,
  });

  /// The product id.
  final String id;

  /// The display title.
  final String title;

  /// The price in minor units, so no floating-point rounding reaches the UI.
  final int priceInCents;

  /// Converts an SDK product into an application product.
  static AppProduct fromBackendProduct(Product product) {
    return AppProduct(
      id: product.id,
      title: product.name.toUpperCase(),
      priceInCents: (product.price * 100).round(),
    );
  }

  @override
  String toString() => 'AppProduct($id, $title, $priceInCents)';
}

/// The data-source contract, expressed entirely in application types.
abstract interface class ProductsRemoteDataSource {
  /// Reads one offset-paginated page as application products.
  Future<BackendResult<PageResult<AppProduct>>> getProducts({
    required PageRequest request,
  });

  /// Reads one product by id as an application product.
  Future<BackendResult<AppProduct>> getProduct(String id);
}

/// The SDK-backed implementation.
///
/// Every method converts at the boundary, so nothing above this class ever sees
/// a `Product`, a `BackendUser`, or a `BackendFailure` it did not choose.
class ProductsRemoteDataSourceImpl implements ProductsRemoteDataSource {
  /// Creates the data source.
  const ProductsRemoteDataSourceImpl();

  @override
  Future<BackendResult<PageResult<AppProduct>>> getProducts({
    required PageRequest request,
  }) async {
    final BackendResult<PageResult<Product>> result =
        await BackendSdk.instance.products.getPage(request: request);

    // Both type parameters are inferred; nothing is written out by hand.
    return result.map(
      (PageResult<Product> page) =>
          page.mapItems(AppProduct.fromBackendProduct),
    );
  }

  @override
  Future<BackendResult<AppProduct>> getProduct(String id) async {
    return (await BackendSdk.instance.products.getById(id)).map(
      AppProduct.fromBackendProduct,
    );
  }

  /// Reads one cursor-paginated page as application products.
  ///
  /// `nextCursor`, `hasMore` and `totalCount` are carried over untouched, so a
  /// keyset walk keeps advancing after the mapping.
  Future<BackendResult<CursorPageResult<AppProduct>>> getProductsAfter({
    String? cursor,
    int limit = 20,
  }) async {
    final BackendResult<CursorPageResult<Product>> result =
        await BackendSdk.instance.products.getCursorPage(
      request: CursorRequest(cursor: cursor, limit: limit),
    );

    return result.map(
      (CursorPageResult<Product> page) =>
          page.mapItems(AppProduct.fromBackendProduct),
    );
  }
}

/// Renders a mapped page, demonstrating that the conversion is transparent to
/// the UI.
Widget buildProductSummary(PageResult<AppProduct> page) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('${page.length} items (page ${page.page} of size ${page.pageSize})'),
      if (page.totalCount != null) Text('total: ${page.totalCount}'),
      if (page.hasMore) const Text('more available'),
      ...page.items.map(
        (AppProduct product) =>
            Text('${product.title} · ${product.priceInCents}'),
      ),
    ],
  );
}
