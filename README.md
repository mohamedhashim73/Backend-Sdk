# backend_sdk

A **provider-agnostic backend SDK** for Flutter and Dart applications.

Application code talks to `backend_sdk`. `backend_sdk` talks to a backend
provider. Supabase is the first provider, implemented entirely inside the
package — your application never sees a Supabase type, a table name, a filter
string, or a Supabase exception.

```dart
import 'package:backend_sdk/backend_sdk.dart';

final result = await BackendSdk.instance.auth.login(
  email: email,
  password: password,
);

result.when(
  success: (session) => navigateHome(session.user),
  failure: (failure) => showMessage(failure.safeMessage),
);
```

---

## Table of contents

- [Why](#why)
- [Architecture](#architecture)
- [Installation](#installation)
- [Initialization](#initialization)
- [Environment configuration](#environment-configuration)
- [Authentication](#authentication)
- [Pagination](#pagination)
- [Filters and sorting](#filters-and-sorting)
- [CRUD](#crud)
- [Storage](#storage)
- [Realtime](#realtime)
- [Typed mapping between layers](#typed-mapping-between-layers)
- [Error handling](#error-handling)
- [Retry and timeout behaviour](#retry-and-timeout-behaviour)
- [Testing](#testing)
- [Security and RLS](#security-and-rls)
- [Adding an application-defined module](#adding-an-application-defined-module)
- [Adding a new backend provider](#adding-a-new-backend-provider)
- [Versioning and backward compatibility](#versioning-and-backward-compatibility)
- [Complete usage example](#complete-usage-example)

---

## Why

A Flutter app that talks to a backend directly accumulates four problems:

1. **Vendor lock-in in the UI layer.** `Supabase.instance.from('products')` in a
   widget means every widget must change when the backend changes.
2. **Pagination, retry and error mapping reimplemented per screen.**
3. **Backend concepts leak into the presentation layer** — table names, filter
   syntax, `PostgrestException`.
4. **No test seam.** Every test needs a network.

`backend_sdk` is the seam. It provides:

| Concern | Who owns it |
|---|---|
| Typed auth, data, storage, realtime APIs | `backend_sdk` |
| Pagination arithmetic, stable ordering | `backend_sdk` |
| Retry, timeout, cancellation, backoff | `backend_sdk` |
| Provider error → `BackendFailure` mapping | `backend_sdk` |
| Input validation, path safety, size limits | `backend_sdk` |
| The actual HTTP, SQL and wire format | the provider |

---

## Architecture

```
Application
    ↓  package:backend_sdk/backend_sdk.dart   ← the only import
backend_sdk public API
    ↓
Backend contracts / interfaces   (lib/src/contracts/)
    ↓
Selected backend provider
    ├── Supabase provider        (lib/src/providers/supabase/)
    ├── REST provider            (planned)
    ├── Firebase provider        (planned)
    └── Other providers          (planned)
```

The consuming application **must not**:

- import `supabase_flutter` for data operations,
- write Supabase queries,
- know table names or bucket names,
- write Supabase filter syntax,
- parse Supabase responses,
- catch Supabase exceptions,
- handle Supabase realtime channels,
- implement pagination arithmetic,
- implement retry or error mapping.

### Directory layout

```
backend_sdk/
├── lib/
│   ├── backend_sdk.dart                 ← public barrel (the only import)
│   └── src/
│       ├── core/          configuration, provider enum, logger, DI, SDK facade
│       ├── contracts/     the four interfaces a provider must implement
│       ├── result/        BackendResult / BackendSuccess / BackendFailureResult
│       ├── errors/        BackendErrorType, BackendFailure, error classifier
│       ├── pagination/    PageRequest, PageResult, CursorRequest, CursorPageResult
│       ├── filters/       FilterCondition, FilterOperator, SortCondition
│       ├── auth/          BackendUser, BackendSession, AuthStateChange, AuthRepository
│       ├── storage/       StorageBucket, requests, StorageRepository
│       ├── realtime/      RealtimeEvent, RealtimeSubscription, RealtimeRepository
│       ├── retry/         RetryPolicy, RequestExecutor, CancellationToken
│       ├── providers/
│       │   └── supabase/  ← ALL vendor code lives here and only here
│       └── modules/       products/ and users/ reference implementations
├── test/
├── example/
├── supabase/migrations/
└── ...
```

### The four contracts a provider implements

| Contract | Responsibility |
|---|---|
| `AuthBackend` | sign-in, sign-up, session lifecycle, session-change events |
| `DataBackend` | page, cursor page, read by id, insert, update, delete, count |
| `StorageBackend` | upload, download, public/signed URL, delete, move, copy, list |
| `RealtimeBackend` | subscribe, emit typed events, unsubscribe, dispose |

Nothing above these contracts knows which backend is active.

---

## Installation

```yaml
dependencies:
  backend_sdk:
    path: ../packages/backend_sdk   # or your git / hosted source
```

```bash
flutter pub get
```

Requires Dart `>=3.6.0` and Flutter `>=3.27.0`.

---

## Initialization

Initialization happens **exactly once** per process, before the first screen.

```dart
import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BackendSdk.initialize(
    provider: BackendProvider.supabase,
    configuration: BackendConfiguration.supabase(
      url: AppEnvironment.supabaseUrl,
      apiKey: AppEnvironment.supabaseAnonKey,
    ),
  );

  runApp(const MyApp());
}
```

That is the whole bootstrap. Note there is no `BackendSdk.instance` line: the
call to `initialize` registers the built-in Supabase provider on its own.

Guarantees:

**You never need to touch `BackendSdk.instance` before calling `initialize`.**
The built-in providers are registered by `initialize` itself, so the bootstrap
above is complete on its own. `BackendSdk.instance` is only for *reaching the
repositories* after initialization.

| Rule | Behaviour |
|---|---|
| Standalone `initialize` | `initialize` registers the built-in providers before resolving a factory, so it works as the very first call. No `BackendSdk.instance` read required. |
| Initialize once | A second call **throws** a `BackendErrorType.configuration` failure. The active provider is never silently replaced. |
| Validate first | Configuration is validated before any network call. |
| Access before init | Accessing `auth`, `storage`, `realtime`, `products` or `users` throws a `BackendErrorType.configuration` failure, never a null dereference. |
| Retry after failure | A **failed** initialization clears the in-flight marker, so a corrected configuration can be retried. |
| Unsupported provider | `BackendProvider.rest` and `.firebase` throw `BackendErrorType.unsupportedProvider` with an actionable message. Registering the built-ins does not enable them. |
| Built-ins are non-clobbering | Built-in registration only fills in providers that are **missing**. A factory you registered with `BackendServiceFactory.register` is never replaced. |
| Registration is idempotent | Built-in registration may run any number of times; only the first call has an effect. |
| No secrets logged | `BackendConfiguration.toString()` omits both the URL and the key. |
| No `SupabaseClient` exposed | The public API has no provider type in it. This is enforced by `test/public_api_test.dart`. |

To deliberately switch backends at runtime (rare; usually a test concern):

```dart
await BackendSdk.dispose();   // releases the active provider
await BackendSdk.initialize(provider: ..., configuration: ...);
```

`BackendSdk.validateConfiguration(provider, configuration)` is public so an app can
check a configuration at start-up and surface its own diagnostics.

---

## Environment configuration

Never hardcode a URL or a key. Supply both at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

```dart
abstract final class AppEnvironment {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
```

CI-friendly variant:

```bash
flutter build apk \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define-from-file=env.json
```

> **The anon / publishable key is not a secret, but it is also not a
> permission.** It is readable by anyone who installs the app. It grants nothing
> by itself: every table must be protected by row level security. See
> [Security and RLS](#security-and-rls).
>
> `BackendSdk.initialize` **rejects a key whose JWT payload contains
> `service_role`**, which catches the most common mistake — pasting the secret
> key from the dashboard — before it ships.

Configuration options:

```dart
BackendConfiguration.supabase(
  url: '...',
  apiKey: '...',
  requestTimeout: const Duration(seconds: 30),   // per attempt
  enableLogging: false,                          // redacted when enabled
  maxRetries: 2,                                 // extra attempts; capped at 10
  retryDelay: const Duration(milliseconds: 200),
  retryBackoffMultiplier: 2.0,
  maxRetryDelay: const Duration(seconds: 10),
);
```

---

## Authentication

`BackendSdk.instance.auth` is a complete, provider-agnostic `AuthRepository`.

| Method | Returns |
|---|---|
| `signUp` | `BackendResult<BackendSession>` |
| `login` | `BackendResult<BackendSession>` |
| `logout` | `BackendResult<void>` |
| `currentUser` | `BackendResult<BackendUser?>` |
| `currentSession` | `BackendResult<BackendSession?>` |
| `refreshSession` | `BackendResult<BackendSession>` |
| `resetPassword` | `BackendResult<void>` |
| `updatePassword` | `BackendResult<BackendUser>` |
| `updateUserMetadata` | `BackendResult<BackendUser>` |
| `resendVerificationEmail` | `BackendResult<void>` |
| `authStateChanges` | `Stream<AuthStateChange>` |

```dart
final result = await BackendSdk.instance.auth.login(
  email: email,
  password: password,
);

final label = result.when(
  success: (session) => 'Signed in as ${session.user.email}',
  failure: (failure) => failure.safeMessage,   // safe to render
);
```

Handled for you:

- invalid credentials → `BackendErrorType.unauthorized`, with a single
  non-enumerating user message that never reveals whether an email exists;
- email already registered → `conflict`;
- email not verified → `validation`;
- expired session / invalid refresh token → `unauthorized`;
- password policy violations → `validation`, **before** the request is made;
- network failures → `network`, retried with backoff;
- logout always clears the local session, even when the provider call fails.

Passwords are never stored, never logged, and never included in a failure
message. `BackendSession.toString()` omits the access token.

Auth state changes:

```dart
final subscription = BackendSdk.instance.auth.authStateChanges.listen(
  (change) {
    switch (change.status) {
      case AuthStatus.authenticated:      setSignedIn(change.user!); break;
      case AuthStatus.unauthenticated:    setSignedIn(null); break;
      case AuthStatus.recoveryRequired:  goToChooseNewPassword(); break;
      case AuthStatus.unknown:            showReconnecting(); break;
    }
  },
);
```

The stream is a broadcast stream and **never emits errors**: a transport failure
surfaces as `AuthStatus.unknown`, so a listener can never crash the app.

---

## Pagination

Two strategies, one API surface.

### Offset pagination — `PageRequest` / `PageResult`

```dart
final result = await BackendSdk.instance.products.getPage(
  request: const PageRequest(page: 1, pageSize: 20),
);

result.when(
  success: (page) {
    render(page.items);
    loadMoreIfNeeded(page.hasMore);
  },
  failure: (failure) => showMessage(failure.safeMessage),
);
```

What the SDK does for you:

- **1-based pages.** `page: 1` is the first page; `page: 0` is a validation
  failure, not a silent empty list.
- **Inclusive ranges.** PostgREST `range(from, to)` includes both ends.
  `PageRequest` exposes `inclusiveStart` / `inclusiveEnd` so you can see exactly
  what was requested:

  | page | pageSize | from | to (inclusive) |
  |---|---|---|---|
  | 1 | 20 | 0 | 19 |
  | 2 | 20 | 20 | 39 |
  | 3 | 15 | 30 | 44 |

- **Bounded page size.** 1 … 200 (`PaginationLimits.maxPageSize`). A larger
  request is rejected locally instead of being silently clamped.
- **Bounded depth.** Pages beyond 10 000 are rejected and the message points at
  cursor pagination.
- **Deterministic ordering.** If your sorts do not end with the primary key, an
  ascending primary-key sort is appended as a tie-breaker. Without it, rows with
  equal sort values can swap between pages and be returned twice.
- **Counts are opt-in.** `includeTotalCount: false` by default; no count query
  runs unless you ask. Use the explicit `count()` method when you want a total.
- **Empty pages** return `hasMore: false`, not an error.
- **No duplicate loads.** Two concurrent identical page requests are collapsed:
  the second returns a `conflict` failure with a message telling you to await the
  in-flight request. This prevents a double-tap or a rebuilt widget from firing
  two network calls.
- **Soft-deleted rows** are excluded automatically, using the same
  `deleted_at is null` predicate the RLS policies use.

### Cursor pagination — `CursorRequest` / `CursorPageResult`

**Prefer cursors** for an infinite-scroll feed or a large, frequently mutated
dataset. Offset pagination degrades linearly because the database must skip
every preceding row; a keyset seek is constant cost and does not skip or repeat
rows when data is inserted mid-scroll.

```dart
String? cursor;
var hasMore = true;

while (hasMore) {
  final result = await BackendSdk.instance.products.getCursorPage(
    request: CursorRequest(cursor: cursor, limit: 20),
  );

  result.when(
    success: (page) {
      appendAll(page.items);
      cursor = page.nextCursor;   // opaque — never parse it
      hasMore = page.hasMore;
    },
    failure: (failure) => hasMore = false,
  );
}
```

The cursor is opaque and provider-internal. It is also hidden from `toString()`,
because it is effectively a position in your data.

---

## Filters and sorting

Filters are typed. There is deliberately **no escape hatch** for raw SQL or raw
filter strings.

```dart
final result = await BackendSdk.instance.products.getPage(
  request: PageRequest(
    page: 1,
    pageSize: 20,
    search: 'phone',
    filters: [
      FilterCondition.equals(ProductFilterField.categoryId, 'electronics'),
      FilterCondition.equals(ProductFilterField.isActive, true),
      FilterCondition.greaterThan(ProductFilterField.price, 100),
    ],
    sorting: [
      SortCondition.descending(ProductSortField.createdAt),
    ],
  ),
);
```

Available operators:

```dart
FilterCondition.equals(field, value)        FilterCondition.greaterThan(field, value)
FilterCondition.notEquals(field, value)     FilterCondition.greaterThanOrEqual(field, value)
FilterCondition.contains(field, String)      FilterCondition.lessThan(field, value)
FilterCondition.startsWith(field, String)    FilterCondition.lessThanOrEqual(field, value)
FilterCondition.inList(field, values)        FilterCondition.isNull(field)
FilterCondition.textSearch(field, term)      FilterCondition.isNotNull(field)

SortCondition.ascending(field)
SortCondition.descending(field)
```

Why this is safe:

- **Field names are validated** against `^[A-Za-z_][A-Za-z0-9_]*$` (max 63
  chars). That rules out `.`, `(`, `)`, `,`, `*`, quotes and whitespace — the
  characters PostgREST uses as filter syntax. A field name can never terminate one
  condition and start another.
- **Values are typed parameters**, never interpolated into a query string.
- **The free-text `search` term is reduced** to an explicit allow-listed
  character set before it reaches the provider, so it cannot introduce syntax
  either.
- **An invalid field or value fails locally**, before any request is made.

Use the `ProductFilterField` / `ProductSortField` constants so a typo is a
compile error rather than a silently empty result set.

---

## CRUD

```dart
final created = await BackendSdk.instance.products.create(
  const CreateProductRequest(name: 'Phone', price: 1000),
);

final updated = await BackendSdk.instance.products.update(
  productId,
  const UpdateProductRequest(name: 'Updated Phone'),
);

final deleted = await BackendSdk.instance.products.delete(productId);

final archived = await BackendSdk.instance.products.softDelete(productId);
```

Every repository exposes:

| Method | Notes |
|---|---|
| `getById(id)` | `notFound` when missing, soft-deleted, or hidden by RLS |
| `getPage(request)` | Offset pagination |
| `getCursorPage(request)` | Cursor pagination |
| `count(request)` | Explicit count; never implicit |
| `create(request)` | Validated locally first |
| `update(id, request)` | Only the fields you set are written |
| `delete(id)` | Permanent |
| `softDelete(id)` | Sets `deleted_at`; retained and consistently hidden |

Requests are typed (`CreateProductRequest`, `UpdateProductRequest`), so the
application never passes a column map:

```dart
final updated = await BackendSdk.instance.products.update(
  productId,
  UpdateProductRequest(stock: 0),
);
// UPDATE products SET stock = 0 WHERE id = $1
```

Prefer `softDelete` over `delete` unless the record truly must disappear: the
shipped RLS policies and any audit trail assume deleted rows are retained.

---

## Storage

```dart
final uploadResult = await BackendSdk.instance.storage.upload(
  request: UploadFileRequest(
    bucket: StorageBucket.products,
    path: 'products/$productId/image.jpg',
    bytes: imageBytes,
    contentType: 'image/jpeg',
  ),
);
```

Full API:

| Method | Purpose |
|---|---|
| `upload` | Upload bytes |
| `download` | Download bytes |
| `getPublicUrl` | Stable public URL (public buckets only) |
| `createSignedUrl` | Time-limited URL for private files |
| `deleteFile` | Delete an object |
| `moveFile` | Move within or across buckets |
| `copyFile` | Copy within or across buckets |
| `listFiles` | List under a prefix, with limit and offset |

Protection the SDK applies:

- **Path validation.** Absolute paths, `..` traversal, backslashes, empty
  segments, control characters, `?`, `#` and over-long paths are rejected before
  the request. Only letters, digits, `.`, `_`, `-` and spaces are allowed in a
  segment.
- **Content-type validation** against a strict `type/subtype` pattern, which
  blocks header injection.
- **Size limits.** Empty payloads are rejected; the default ceiling is 10 MiB and
  is configurable per repository.
- **Typed failures** for every outcome, including `notFound` when deleting a
  missing object (so a typo cannot look like a successful cleanup).
- **Bounded listings** — limit and offset are validated; a listing can never
  become an unbounded download.
- **Signed URL lifetimes are bounded** — 10 s … 7 days, defaulting to 5 minutes.
  `SignedFileUrl.toString()` omits the URL, because it is a bearer credential.

---

## Realtime

```dart
final watcher = BackendSdk.instance.realtime.watch<Product>(
  resource: BackendResource.products,
);

final subscription = await watcher.ready;

final subscription2 = watcher.events.listen((event) {
  switch (event.type) {
    case RealtimeEventType.inserted:
    case RealtimeEventType.updated:
      apply(event.newData!);
    case RealtimeEventType.deleted:
      remove(event.oldData!.id);
  }
});

// In State.dispose / onClose:
await subscription2.cancel();
await watcher.dispose();
```

Guarantees:

- **Typed events.** `RealtimeEvent<Product>` carries `oldData` / `newData` as
  your own model, decoded by the module's codec. The module registers its decoder
  during construction, so there is no mapper to wire up.
- **No duplicate subscriptions.** Two watchers with the same resource and filters
  share one provider channel; the channel closes when the last one disposes.
- **Safe disposal.** `dispose()` is idempotent, so calling it from a
  `State.dispose` override after an explicit cancel is fine.
- **No crashes.** Transport errors, channel errors, subscribe timeouts and
  mapping failures are recorded in `lastFailure`; the stream stays open. A
  background socket can never take the app down.
- **A malformed payload is skipped, not fatal** — one bad row does not tear down
  a live subscription.
- **Filtering** uses validated column names only, so a watch filter cannot inject
  query syntax.
- **Cleanup is complete** — `BackendSdk.dispose()` closes every channel and the
  underlying client.

> Tables must be in the `supabase_realtime` publication to emit changes. See
> `supabase/migrations/0006_realtime.sql`.

---

## Typed mapping between layers

The SDK returns its own models (`Product`, `BackendUser`). Most applications want
their own models at the edge of a data source, so they never leak SDK types into
the domain or presentation layer.

`map` and `mapItems` exist for exactly that. Both are **pure, total, and
provider-agnostic**: no network, no `dynamic`, no `force` unwrap.

### Mapping a single value

```dart
final BackendResult<BackendUser> result =
    await BackendSdk.instance.auth.currentUser();

// R is inferred; no type argument is needed.
final BackendResult<AppUser> appUserResult = result.map(
  AppUser.fromBackendUser,
);
```

- On success, `transform` runs on the value and you get `BackendSuccess<R>`.
- On failure, `transform` is **not** called and you get the *same*
  `BackendFailure` instance — `identical(before.failure, after.failure)` holds.

### Mapping a page

```dart
final BackendResult<PageResult<Product>> result =
    await BackendSdk.instance.products.getPage(request: request);

final BackendResult<PageResult<ProductModel>> mappedResult = result.map(
  (page) => page.mapItems(ProductModel.fromBackendProduct),
);

mappedResult.when(
  success: (page) {
    final items = page.items;      // List<ProductModel>
    final hasMore = page.hasMore;  // unchanged
    final total = page.totalCount; // unchanged
  },
  failure: (failure) => showMessage(failure.safeMessage),
);
```

`PageResult.mapItems` carries over `page`, `pageSize`, `hasMore` and
`totalCount` **verbatim**. It deliberately does *not* recompute `hasMore` from
the mapped list, so a mapper that filters items cannot silently change
pagination behaviour.

### Mapping a cursor page

```dart
final BackendResult<CursorPageResult<Product>> result =
    await BackendSdk.instance.products.getCursorPage(request: request);

final mappedResult = result.map(
  (page) => page.mapItems(ProductModel.fromBackendProduct),
);

mappedResult.when(
  success: (page) {
    final items = page.items;         // List<ProductModel>
    final cursor = page.nextCursor;   // unchanged — the walk still advances
    final hasMore = page.hasMore;     // unchanged
  },
  failure: (failure) => showMessage(failure.safeMessage),
);
```

### Inside a remote data source

This is the intended shape. The SDK type stops at the data-source boundary:

```dart
class ProductsRemoteDataSourceImpl implements ProductsRemoteDataSource {
  const ProductsRemoteDataSourceImpl();

  @override
  Future<BackendResult<PageResult<ProductModel>>> getProducts({
    required PageRequest request,
  }) async {
    final result = await BackendSdk.instance.products.getPage(
      request: request,
    );

    return result.map(
      (page) => page.mapItems(ProductModel.fromBackendProduct),
    );
  }

  @override
  Future<BackendResult<ProductModel>> getProduct(String id) async {
    return (await BackendSdk.instance.products.getById(id)).map(
      ProductModel.fromBackendProduct,
    );
  }

  @override
  Future<BackendResult<CursorPageResult<ProductModel>>> getProductsAfter({
    String? cursor,
    int limit = 20,
  }) async {
    return (await BackendSdk.instance.products.getCursorPage(
      request: CursorRequest(cursor: cursor, limit: limit),
    ))
        .map((page) => page.mapItems(ProductModel.fromBackendProduct));
  }
}
```

### Contract

| Guarantee | Detail |
|---|---|
| Failure is untouched | Same `BackendFailure` instance; no re-classification, no copy. |
| `transform` is skipped on failure | It is never invoked when the result is a failure. |
| Immutability | `map` allocates a new result; `mapItems` allocates a new unmodifiable list. The receiver is never mutated. |
| No `dynamic` | Both signatures are fully typed; `R` is inferred from `transform`. |
| Empty pages | `mapItems` on an empty page returns an empty page, metadata intact. |
| Nullable `T` | A successful `null` invokes `transform` with `null`; it stays a *success*, not a failure. Declare the parameter nullable. |

### Exceptions from `transform`

`transform` is **not** wrapped in a `try`/`catch`. An exception it throws
propagates unchanged and is **never** converted into a `BackendFailure`.

This is deliberate: a mapping function is application code, and a bug in it is
not a backend outage. Swallowing it into `BackendResult` would make a programming
error look like a transient network failure and would attach a retry policy that
can never help. If you need a total mapping, return a nullable model or catch at
the call site.

```dart
// A mapping bug surfaces loudly, as itself.
result.map<String>((Product p) => throw StateError('bad mapper'));
// -> throws StateError

// To make the mapping total, return a nullable model instead.
result.map<ProductModel?>((Product p) => _tryConvert(p));  // no throw
```

---

## Error handling

Every call returns a `BackendResult`. Nothing throws a provider exception.

```dart
sealed class BackendResult<T> {
  bool get isSuccess;
  bool get isFailure;
  T? get data;
  BackendFailure? get failure;

  R when<R>({
    required R Function(T data) success,
    required R Function(BackendFailure failure) failure,
  });

  BackendResult<R> map<R>(R Function(T data) transform);
  T getOrElse(T Function(BackendFailure failure) orElse);
}
```

`BackendFailure` carries a vendor-neutral `BackendErrorType` plus the technical
detail kept for logs:

| Field | Purpose |
|---|---|
| `type` | `BackendErrorType` — the value to branch on |
| `message` | Developer-facing detail (never a credential) |
| `userMessage` | Safe to render; falls back to a per-type default |
| `code` | Provider code (`'23505'`, `'invalid_credentials'`) for logs |
| `statusCode` | HTTP status, when the failure came from a response |
| `cause` | The original provider exception, for logs only |
| `stackTrace` | Captured at the throw site |
| `isRetryable` | Whether the SDK may retry this |

`BackendErrorType` values:

```
configuration  network       timeout       cancelled
unauthorized   forbidden     validation    notFound
conflict       rateLimited   database      storage
realtime       server        unsupportedProvider  unknown
```

```dart
final result = await BackendSdk.instance.products.getPage(
  request: const PageRequest(page: 1),
);

if (result.isFailure) {
  final failure = result.failure!;
  showMessage(failure.safeMessage);          // user-facing

  switch (failure.type) {
    case BackendErrorType.unauthorized:      goToLogin(); break;
    case BackendErrorType.rateLimited:       scheduleRetry(); break;
    case BackendErrorType.notFound:          showEmptyState(); break;
    case BackendErrorType.network:           showOfflineBanner(); break;
    default:                                 showGenericError();
  }
}
```

Guarantees:

- Provider exceptions are **never** exposed; they are converted by a single
  provider error mapper and retained only as `cause`.
- A `PostgrestException` with code `PGRST116` becomes `notFound`, not a generic
  database error.
- SQLSTATE `42501` (an RLS denial) becomes `forbidden`.
- An RLS denial and a missing row are **indistinguishable** to the client,
  because distinguishing them would leak whether a record exists.
- Auth failures never leak the vendor message into `safeMessage`.
- Passwords, tokens and keys never appear in a message, a `toString()`, or a log.

---

## Retry and timeout behaviour

```dart
BackendConfiguration.supabase(
  url: ...,
  apiKey: ...,
  requestTimeout: const Duration(seconds: 30),  // per attempt
  maxRetries: 2,                                // extra attempts
  retryDelay: const Duration(milliseconds: 200),
  retryBackoffMultiplier: 2.0,
  maxRetryDelay: const Duration(seconds: 10),
);
```

Delay before attempt *n* is
`retryDelay × multiplier^(n-1)`, clamped to `maxRetryDelay`, with ±20 % jitter so
a fleet of clients does not synchronise its retries.

**Retried** (transport-level, transient): `network`, `timeout`, `rateLimited`,
`server`.

**Never retried**: `unauthorized`, `forbidden`, `validation`, `notFound`,
`conflict`, `configuration`, `unsupportedProvider`, and everything else. A retry
cannot change the answer, and for a sign-in it can trip account lockout.

Retries are **bounded**: `maxRetries` is capped at 10 by configuration
validation, so a stuck call cannot loop indefinitely.

Cancellation is cooperative and optional:

```dart
final token = CancellationToken()..cancel();

final result = await BackendSdk.instance.products.getPage(
  request: const PageRequest(page: 1),
  cancellationToken: token,
);
// BackendErrorType.cancelled, and no request is sent
```

A call already on the wire is allowed to finish; cancelling stops the next
attempt. Attach the token to a `dispose` if you want in-flight work abandoned.

Logging is off by default. When enabled, every context value is redacted before
it reaches the sink — keys that look like credentials are replaced with
`[redacted]` and long values are truncated, because a provider error payload can
echo the request body.

```dart
await BackendSdk.initialize(
  provider: BackendProvider.supabase,
  configuration: config,
  logger: CallbackBackendLogger(sink: myCrashReporter.log),
);
```

---

## Testing

```bash
dart analyze          # strict static analysis, must be clean
dart format .         # formatting
flutter test          # the 328 unit tests
```

> **Use `flutter test`, not `dart test`.** This package depends on `flutter` and
> its tests import `package:flutter_test`, which requires `dart:ui`. Running
> `dart test` fails at load time with
> `Dart library 'dart:ui' is not available on this platform` — that is expected
> for any Flutter package, not a defect in this one.

The suite has **328 tests** and makes **no network calls**: every provider is
replaced by an in-memory fake that implements the same contracts.

| Suite | Covers |
|---|---|
| `test/result/` | Result type, failure classification, provider error mapping |
| `test/core/` | Configuration validation, initialization lifecycle, double init, access before init, unsupported providers |
| `test/pagination/` | Inclusive ranges, page-size limits, empty pages, `hasMore`, total count, cursor walking, duplicate-load prevention |
| `test/filters/` | Field-name safety, value validation, every operator, stable ordering |
| `test/retry/` | Retry decisions, backoff schedule, timeout, cancellation, log redaction |
| `test/auth/` | Credential mapping, local validation, provider failures, auth-state stream |
| `test/storage/` | Path safety, content type, size limits, signed URLs, listing bounds |
| `test/realtime/` | Duplicate prevention, typed events, cleanup, idempotent dispose, failure isolation |
| `test/modules/` | Product and user mapping, validation, repository behaviour, soft delete |
| `test/providers/` | Supabase → `BackendFailure` conversion |
| `test/public_api_test.dart` | **The public API contains no Supabase type, no table name, and no provider import outside `lib/src/providers/`** |

`test/public_api_test.dart` reads the barrel and every library it exports and
fails on:

- a `SupabaseClient`, `PostgrestResponse`, `PostgrestException`,
  `StorageFileApi`, `RealtimeChannel`, `AuthException`, … in public code,
- a `BackendRecord` (raw provider payload) in the public surface,
- a `package:supabase` (or `gotrue`, `postgrest`, `storage_client`,
  `realtime_client`) import outside `lib/src/providers/supabase/`,
- a physical table or bucket name in a public library,
- an undocumented public member.

### Testing your own application

The SDK is a singleton, so tests usually reset it around each case:

```dart
setUp(() async {
  BackendSdk.initialize(
    provider: BackendProvider.supabase,
    configuration: BackendConfiguration.supabase(
      url: 'https://test.supabase.co',
      apiKey: 'test-key',
      enableLogging: true,
    ),
  );
});

tearDown(() => BackendSdk.dispose());
```

For true isolation, register your own provider factory of fakes — this needs no
network and no Supabase project:

```dart
BackendServiceFactory.register(
  BackendProvider.supabase,
  (configuration, logger) => MyFakeServices(configuration),
);
```

### Integration testing against a real Supabase project

The unit suite never touches the network. To verify the provider wiring for real:

```bash
# 1. Apply the schema
supabase link --project-ref <ref>
supabase db push

# 2. Run the integration suite with real credentials
flutter test test_integration \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

Guidelines for that suite:

- Use a **dedicated test project**, never production data.
- Create a throwaway account per test via `auth.signUp`; do not share sessions.
- Assert on **typed results**, not on raw responses.
- Cover the failure paths too: sign in with the wrong password, read a record
  owned by another user, request a signed URL for a private object, and assert
  you get `unauthorized` / `forbidden` / `notFound`.
- Add a test that a non-admin cannot read another user's profile row. If it
  passes only because the client filtered the result, RLS is missing.
- Assert `watcher.lastFailure` for realtime behaviour that depends on the
  `supabase_realtime` publication.

---

## Security and RLS

`supabase/migrations/` contains a complete, reviewed reference schema:

| File | Contents |
|---|---|
| `0001_products_and_users.sql` | Tables, indexes, `is_admin()` helper, updated-at triggers |
| `0002_rls_policies.sql` | RLS for every table: owner-based, admin, public, soft-delete |
| `0003_auth_triggers.sql` | Profile creation/removal from the auth lifecycle |
| `0004_column_privileges.sql` | Per-column grants so a client cannot self-promote |
| `0005_storage_buckets.sql` | The four buckets plus owner-based storage policies |
| `0006_realtime.sql` | Publication setup |

### The rules

1. **The anon key is not a secret, but it is not a permission.** It ships inside
   the app binary and is readable by anyone who installs it. It grants nothing
   without RLS.
2. **Never ship the service-role key in a Flutter app.** It bypasses RLS
   entirely. `BackendSdk.initialize` rejects a service-role JWT as a
   defence-in-depth check.
3. **Client-side authorization is not security.** `User.isAdmin` is a rendering
   hint. The `is_admin()` SQL helper reading `app_metadata` is the actual gate.
   `user_metadata` is user-writable; `app_metadata` is not.
4. **Every table needs RLS enabled and at least one policy.** RLS on with no
   policy denies everything, which is the safe default.
5. **Ownership is enforced in the database**, with `auth.uid()`:
   `using (id = auth.uid())`.
6. **Admin access is enforced in the database**, with `using (public.is_admin())`.
7. **Soft-deleted rows are excluded consistently.** The SDK adds
   `deleted_at is null` to every read; the policies do the same. Clients may soft
   delete but not hard delete.
8. **Private files live in private buckets with signed URLs.** Every bucket in
   the reference schema is `public = false`.
9. **RLS decides rows; privileges decide columns.** `0004_column_privileges.sql`
   revokes blanket `UPDATE` and re-grants per column, which is what actually
   stops a user writing `role = 'admin'` into their own row.

### Verified end state

```sql
-- A user cannot read another user's profile.
select count(*) from public.users where id <> auth.uid();  -- 0

-- A user cannot promote themselves.
update public.users set role = 'admin' where id = auth.uid();
-- ERROR: permission denied for table users

-- A non-admin cannot see soft-deleted products.
select count(*) from public.products where deleted_at is not null;  -- 0

-- A user cannot hard delete.
delete from public.products where id = '...';
-- ERROR: permission denied for table products
```

---

## Adding an application-defined module

Application modules live in the consuming Flutter application. They do not
require a new `BackendResource` enum value, a change to this package, a second
`SupabaseClient`, or a raw Supabase query.

### RPC for aggregated reads

Use normal repositories and CRUD methods when the screen is reading or
mutating one resource and benefits from the standard filtering, pagination,
validation, and typed resource codec flow. Use `BackendSdk.instance.data.callRpc`
when a backend function intentionally returns a computed or aggregated view
that would otherwise require multiple coordinated requests, such as a home
feed combining featured and recommended content.

RPC remains provider-agnostic: pass a safe function identifier, JSON-compatible
parameters, and an application decoder. The SDK never exposes a provider client,
raw SQL, or a provider response:

```dart
final result = await BackendSdk.instance.data.callRpc<HomeFeed>(
  functionName: 'get_home_feed',
  parameters: {'locale': 'ar'},
  decoder: HomeFeed.fromJson,
);
```

Function names are validated as identifiers and every provider or decoding
failure is returned as a `BackendFailure`. Keep authorization and row-level
security in the backend function; do not use RPC as a way to bypass the normal
security model.

1. Initialize `backend_sdk` once and obtain `BackendSdk.instance.data`.
2. Declare a static, validated descriptor with an application-owned key and
   table name:

```dart
abstract final class HistoricalNarrativeResource {
  static const descriptor = BackendResourceDescriptor(
    key: 'historical_narratives',
    tableName: 'historical_narratives',
    searchableFields: {'title', 'description'},
    defaultSorting: [SortCondition.descending('published_at')],
  );
}
```

3. Create the application model and codec. The codec is the only application
   code that knows the row shape:

```dart
class HistoricalNarrativeCodec implements ResourceCodec<HistoricalNarrative,
    Map<String, Object?>, Map<String, Object?>> {
  const HistoricalNarrativeCodec();

  @override
  BackendResourceDescriptor get descriptor =>
      HistoricalNarrativeResource.descriptor;

  @override
  BackendResult<HistoricalNarrative> decode(BackendRecord record) =>
      BackendSuccess(HistoricalNarrative.fromBackend(record));

  @override
  BackendResult<Map<String, Object?>> encodeCreate(Map<String, Object?> value) =>
      BackendSuccess(value);

  @override
  BackendResult<Map<String, Object?>> encodeUpdate(Map<String, Object?> value) =>
      BackendSuccess(value);

  @override
  BackendFailure? validateCreate(Map<String, Object?> value) => null;

  @override
  BackendFailure? validateUpdate(Map<String, Object?> value) => null;
}
```

4. Create a repository in the application:

```dart
class HistoricalNarrativesRepository extends BackendRepository<
    HistoricalNarrative, Map<String, Object?>, Map<String, Object?>> {
  HistoricalNarrativesRepository({
    required DataBackend backend,
    required RequestExecutor executor,
  }) : super(
          backend: backend,
          executor: executor,
          codec: const HistoricalNarrativeCodec(),
        );
}

final result = await repository.getPage(
  request: const PageRequest(
    page: 1,
    pageSize: 20,
    search: 'museum',
    sorting: [SortCondition.descending('published_at')],
  ),
);
final narratives = result.map(
  (page) => page.mapItems(HistoricalNarrative.fromBackend),
);
```

5. A `RemoteDataSource` or Cubit can depend on this repository and handle the
   returned `BackendResult`; no provider types cross the boundary.

Descriptor keys, table names and field names must be static safe identifiers;
they are never received from end users and never contain SQL or query
fragments. Keep RLS enabled and enforced by Supabase. Future modules such as
orders, vehicles, podcasts or invoices follow the same application-only flow.

---

## Adding a new backend provider

Adding a vendor is a **contained** change: four interfaces plus a registration.
**No application code changes.**

### Step 1 — implement the contracts

```dart
// lib/src/providers/rest/rest_data_backend.dart
class RestDataBackend implements DataBackend {
  @override
  Future<BackendResult<PageResult<BackendRecord>>> readPage({
    required BackendResource resource,
    required DataQuerySpec spec,
  }) async {
    // spec.from / spec.to are inclusive. Translate them into
    // ?offset=<from>&limit=<to - from + 1> for a REST API, a `skip`/`limit`
    // pair for Firestore, or a `first`/`after` cursor pair for GraphQL.
  }

  // ...insertRecord, updateRecord, deleteRecord, readById, countRecords,
  //    readCursorPage
}
```

Implement `AuthBackend`, `StorageBackend` and `RealtimeBackend` the same way.

You get **for free**, because they live above the contracts:

- pagination arithmetic, stable ordering and duplicate-load prevention,
- retry, exponential backoff, timeout and cancellation,
- input, path, content-type and size validation,
- error classification into `BackendFailure` with a user-safe message,
- log redaction.

### Step 2 — map resource → physical location

```dart
abstract final class RestResourceRegistry {
  static String pathOf(BackendResource resource) => switch (resource) {
        BackendResource.products => 'v1/products',
        BackendResource.users => 'v1/users',
      };
}
```

The application still only says `BackendResource.products`.

### Step 3 — register a factory

```dart
BackendServiceFactory.register(
  BackendProvider.rest,
  (configuration, logger) async {
    final client = RestClient(baseUrl: configuration.url!);
    final executor = RequestExecutor(
      retryPolicy: RetryPolicy(maxRetries: configuration.maxRetries),
      requestTimeout: configuration.requestTimeout,
      logger: logger,
    );

    return ProviderBackendServices(
      auth: AuthRepository(backend: RestAuthBackend(client), executor: executor),
      storage: StorageRepository(
        backend: RestStorageBackend(client),
        executor: executor,
      ),
      realtime: RealtimeRepository(backend: RestRealtimeBackend(client)),
      products: ProductsRepository(backend: data, executor: executor),
      users: UsersRepository(backend: data, executor: executor),
    );
  },
);
```

`BackendProvider.rest` and `BackendProvider.firebase` are already declared. They
fail with `BackendErrorType.unsupportedProvider` until you register them, so
configuring them today gives a clear error instead of a compile error.

### Step 4 — nothing else changes

This application keeps working verbatim, against REST instead of Supabase:

```dart
final result = await BackendSdk.instance.products.getPage(
  request: PageRequest(
    page: 1,
    pageSize: 20,
    search: 'phone',
    filters: [FilterCondition.equals(ProductFilterField.categoryId, 'electronics')],
    sorting: [SortCondition.descending(ProductSortField.createdAt)],
  ),
);
```

The only application edit is the `BackendProvider` value at initialization.

---

## Versioning and backward compatibility

- Semantic versioning. `1.0.0` is the API-stability promise.
- **Additive by default.** New optional parameters, new enum values on
  `BackendErrorType`, new resources and new methods are minor releases.
- **No silent behaviour changes.** Changing `hasMore` semantics, the default
  sort order or the retry policy is a major release.
- **Breaking change** = removing or renaming a public symbol, changing a method
  signature or return type, narrowing an accepted value, or changing documented
  behaviour. All of these are gated behind a major version.
- Deprecated symbols are annotated with `@Deprecated('use X instead')` and kept
  for at least one minor cycle.
- `BackendResult` is `sealed`: `when` gives exhaustive handling, and adding a
  third variant is a breaking change — which is intentional, because it should
  require thought.
- **Provider internals are not public API.** Anything under `lib/src/` other
  than the explicitly exported symbols may change in any release. This is the
  escape hatch that lets error codes and query strategy evolve without breaking
  you.

Depend on the barrel only. Importing `package:backend_sdk/src/...` opts you out
of the compatibility promise.

---

## Complete usage example

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
abstract final class AppEnvironment {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BackendSdk.initialize(
    provider: BackendProvider.supabase,
    configuration: BackendConfiguration.supabase(
      url: AppEnvironment.supabaseUrl,
      apiKey: AppEnvironment.supabaseAnonKey,
      enableLogging: kDebugMode,
      maxRetries: 2,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const SignInPage());
  }
}

// ---------------------------------------------------------------------------
// A result-aware helper for error display
// ---------------------------------------------------------------------------
void showFailure(BuildContext context, BackendFailure failure) {
  // `safeMessage` is the only string that is guaranteed to be user-safe.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failure.safeMessage)));
}

// ---------------------------------------------------------------------------
// Sign in
// ---------------------------------------------------------------------------
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);

    final result = await BackendSdk.instance.auth.login(
      email: _email.text,
      password: _password.text,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    result.when(
      success: (_) => Navigator.of(context).pushReplacementNamed('/home'),
      failure: (failure) => showFailure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: Text(_busy ? 'Signing in…' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product list: pagination, search, filters, sorting, realtime
// ---------------------------------------------------------------------------
class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  static const _pageSize = 20;

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<Product> _items = [];
  bool _hasMore = true;
  bool _loading = false;
  int _page = 1;

  RealtimeSubscription<Product>? _watcher;
  StreamSubscription<RealtimeEvent<Product>>? _events;
  CancellationToken? _cancel;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load(reset: true));
    _watchProducts();
  }

  @override
  void dispose() {
    // Order matters: cancel the listener, dispose the subscription, then
    // abandon any in-flight request. Every step is idempotent.
    unawaited(_events?.cancel());
    unawaited(_watcher?.dispose());
    _cancel?.cancel();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _watchProducts() {
    // Registered automatically by ProductsRepository, so this yields
    // RealtimeEvent<Product> with no mapper to wire up.
    final watcher = BackendSdk.instance.realtime.watch<Product>(
      resource: BackendResource.products,
    );
    _watcher = watcher;

    unawaited(watcher.ready.then((_) {
      if (!mounted) return;
      _events = watcher.events.listen(_onEvent);
    }));
  }

  void _onEvent(RealtimeEvent<Product> event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case RealtimeEventType.inserted:
          if (event.newData != null) _items.insert(0, event.newData!);
        case RealtimeEventType.updated:
          final updated = event.newData;
          if (updated == null) break;
          final index =
              _items.indexWhere((product) => product.id == updated.id);
          if (index >= 0) _items[index] = updated;
        case RealtimeEventType.deleted:
          final removed = event.oldData;
          if (removed == null) break;
          _items.removeWhere((product) => product.id == removed.id);
      }
    });
  }

  Future<void> _onScroll() async {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      await _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;

    setState(() => _loading = true);
    _cancel?.cancel();
    _cancel = CancellationToken();

    if (reset) {
      _page = 1;
      _hasMore = true;
    }

    final result = await BackendSdk.instance.products.getPage(
      request: PageRequest(
        page: _page,
        pageSize: _pageSize,
        search: _controller.text.trim().isEmpty ? null : _controller.text.trim(),
        filters: const [
          FilterCondition.equals(ProductFilterField.isActive, true),
        ],
        sorting: const [
          SortCondition.descending(ProductSortField.createdAt),
        ],
        includeTotalCount: reset,
      ),
      cancellationToken: _cancel,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    result.when(
      success: (page) {
        setState(() {
          if (reset) _items.clear();
          _items.addAll(page.items);
          _hasMore = page.hasMore;
          if (page.hasMore) _page++;
        });
      },
      failure: (failure) {
        if (failure.type == BackendErrorType.cancelled) return;
        showFailure(context, failure);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: 'Search',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _load(reset: true),
                  ),
                ),
                onSubmitted: (_) => _load(reset: true),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final product = _items[index];
                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text(
                        '${product.priceLabel} · stock ${product.stock}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _rename(product),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await BackendSdk.instance.products.create(
            CreateProductRequest(
              name: _controller.text.trim().isEmpty
                  ? 'New product'
                  : _controller.text.trim(),
              price: 1000,
            ),
          );

          if (!mounted) return;
          // A live insert will arrive over realtime too; the explicit insert
          // above is only needed when realtime is unavailable.
          result.when(
            success: (_) {},
            failure: (failure) => showFailure(context, failure),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _rename(Product product) async {
    final result = await BackendSdk.instance.products.update(
      product.id,
      UpdateProductRequest(name: '${product.name} (updated)'),
    );

    if (!mounted) return;
    result.when(
      success: (_) {},
      failure: (failure) => showFailure(context, failure),
    );
  }
}

// ---------------------------------------------------------------------------
// File upload
// ---------------------------------------------------------------------------
Future<void> uploadProductImage({
  required String productId,
  required Uint8List bytes,
  required BuildContext context,
}) async {
  final result = await BackendSdk.instance.storage.upload(
    request: UploadFileRequest(
      bucket: StorageBucket.products,
      path: 'products/$productId/image.jpg',
      bytes: bytes,
      contentType: 'image/jpeg',
    ),
  );

  if (!context.mounted) return;
  result.when(
    success: (file) => debugPrint('Stored ${file.path} (${file.sizeInBytes} B)'),
    failure: (failure) => showFailure(context, failure),
  );
}

// ---------------------------------------------------------------------------
// A private document link
// ---------------------------------------------------------------------------
Future<String?> createDocumentLink({
  required StorageBucket bucket,
  required String path,
}) async {
  final result = await BackendSdk.instance.storage.createSignedUrl(
    bucket: bucket,
    path: path,
    expiresIn: 300,
  );

  // The URL is a bearer credential: never log it, never persist it.
  return result.when(
    success: (signed) => signed.url,
    failure: (failure) => null,
  );
}
```

A runnable version of this file lives in `example/lib/main.dart`.

---

## License

MIT — see the `LICENSE` file.
