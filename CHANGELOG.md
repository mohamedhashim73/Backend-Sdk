# Changelog

All notable changes to this package are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `PageResult<T>.mapItems<R>(R Function(T item) transform)`, which returns a copy
  whose items are the results of applying `transform`. `page`, `pageSize`,
  `hasMore` and `totalCount` are carried over **verbatim** rather than recomputed,
  so a mapper that filters items cannot change pagination behaviour. The returned
  `items` list is unmodifiable and the receiver is never mutated. An empty page
  maps to an empty page with its metadata intact.
- `CursorPageResult<T>.mapItems<R>(R Function(T item) transform)`, with the same
  guarantees. `nextCursor`, `hasMore` and `totalCount` are preserved, so a
  keyset walk keeps advancing after the mapping.

Both methods are additive: no existing symbol changed, and no existing test was
modified.

### Changed

- Expanded the documentation of `BackendResult.map`. The signature and behaviour
  are unchanged; what is new is an explicit statement of three points that were
  previously implied: the `BackendFailure` instance is carried over identically,
  a successful `null` invokes the transform and remains a success, and an
  exception thrown by `transform` propagates rather than being converted into a
  `BackendFailure`. The last point is deliberate, so a bug in an application
  mapper is not reported as a backend outage.

## [0.1.0] — 2026-10-02

First release. The package is API-unstable until `1.0.0`; see the
[versioning section](README.md#versioning-and-backward-compatibility) for the
stability promise and for what counts as a breaking change.

### Added

**Core**

- `BackendSdk.initialize` with an exactly-once lifecycle: validated
  configuration, a synchronous in-flight guard, and a clear
  `BackendErrorType.configuration` failure when a repository is accessed before
  initialization or after `dispose`.
- `BackendConfiguration` with `BackendConfiguration.supabase(...)`, per-attempt
  timeout, bounded retry count, exponential backoff and jitter. `toString()`
  omits the URL and the API key.
- Defence-in-depth rejection of a Supabase **service-role** key at
  initialization, with a message explaining why it must never ship in a client.
- `BackendProvider` with `supabase`, `rest` and `firebase`. Only `supabase` is
  implemented; the others fail with `BackendErrorType.unsupportedProvider`
  unless a factory is registered.
- `BackendServiceFactory` as the single extension point for a new provider.
- `BackendLogger`, `NoopBackendLogger` and `CallbackBackendLogger`, with
  credential-shaped context keys redacted and long values truncated before they
  reach a sink.
- `RealtimeSubscription.ready` for driving a connecting indicator.

**Result and errors**

- Sealed `BackendResult<T>` with `BackendSuccess<T>` and
  `BackendFailureResult<T>`, plus `when`, `map` and `getOrElse`.
- `BackendFailure` carrying `type`, `message`, `userMessage`, `code`,
  `statusCode`, `cause`, `stackTrace` and `isRetryable`. The `cause` is retained
  for diagnostics and never rendered to end users.
- `BackendErrorType` with 15 values and a `retryable` classification that
  excludes every business and authorization failure.
- `BackendErrorClassifier` as the shared classification table: HTTP status,
  PostgreSQL SQLSTATE (including `42501` → `forbidden`) and provider code names,
  with an explicit rule that only a real 3-digit HTTP status is treated as one.
- `SupabaseErrorMapper`, the only class in the package that knows what a
  `PostgrestException`, `AuthException` or `StorageException` is. Maps
  `PGRST116` → `notFound`, unique violations → `conflict`, invalid credentials to
  a single non-enumerating user message, and excludes auth from retry entirely so
  a 5xx during sign-in cannot trip account lockout.

**Pagination**

- `PageRequest` / `PageResult` with 1-based pages, inclusive ranges
  (`page: 2, pageSize: 20` → 20..39), page-size bounds of 1…200, a page-depth
  limit of 10 000 that points at cursor pagination, and opt-in exact counts.
- `CursorRequest` / `CursorPageResult` with an opaque, `toString`-hidden cursor
  and a bounded limit of 500.
- Duplicate in-flight page requests are refused with a `conflict` failure rather
  than issuing a second network call.

**Filters and sorting**

- Sealed `FilterCondition` with 11 typed operators and strict validation of both
  field names and value shapes. Field names must match
  `^[A-Za-z_][A-Za-z0-9_]*$`, which rules out every character PostgREST uses as
  filter syntax.
- `SortCondition` with a stable primary-key tie-breaker appended whenever the
  caller's ordering does not already end with the resource key, so paging cannot
  return a row twice.

**Auth**

- `AuthRepository` with `signUp`, `login`, `logout`, `currentUser`,
  `currentSession`, `refreshSession`, `resetPassword`, `updatePassword`,
  `updateUserMetadata`, `resendVerificationEmail` and `authStateChanges`.
- Local validation of email shape, password length, redirect URL scheme and
  metadata payload, so malformed input never reaches the network.
- `BackendUser` and `BackendSession`, neither of which renders a credential in
  `toString()`. `app_metadata` is intentionally not exposed.
- The auth-state stream is broadcast and never emits errors; a transport failure
  is reported as `AuthStatus.unknown`.

**Storage**

- `StorageBucket`, `StorageRepository`, `UploadFileRequest`, `UploadedFile`,
  `SignedFileUrl`, and move/copy/list requests.
- Local rejection of absolute paths, `..` traversal, backslashes, empty segments,
  control characters, query markers, malformed MIME types and empty or oversized
  payloads.
- Signed-URL lifetimes bounded to 10 s … 7 days, defaulting to 5 minutes.
  `SignedFileUrl.toString()` omits the URL.
- Deleting a missing object is a `notFound` failure, so a typo in a path cannot
  look like a successful cleanup.

**Realtime**

- `RealtimeRepository` with reference-counted channel sharing, typed
  `RealtimeEvent<T>` decoding through the module's codec, idempotent disposal and
  complete cleanup on `BackendSdk.dispose()`.
- Transport errors, channel errors, subscribe timeouts and mapping failures are
  recorded in `lastFailure`; the stream stays open and a malformed payload is
  skipped rather than tearing down a live subscription.

**Modules**

- A complete `Products` reference module: `Product`, `ProductCodec`,
  `CreateProductRequest`, `UpdateProductRequest`, `ProductsRepository`, column
  and filter/sort field constants, validation, mapping, pagination, search,
  filtering, sorting and soft delete.
- A `Users` module: `User`, `UserCodec`, request types, `UsersRepository`.
- `BackendRepository<TModel, TCreate, TUpdate>`, the shared engine that gives
  every module identical pagination, ordering, validation and error behaviour.

**Supabase provider**

- `SupabaseProvider` wiring `SupabaseAuthBackend`, `SupabaseDataBackend`,
  `SupabaseStorageBackend` and `SupabaseRealtimeBackend` into the repositories.
- `SupabaseResourceRegistry` as the single place a `BackendResource` becomes a
  table name, and the single place a bucket becomes a bucket id.
- Search terms reduced to an allow-listed character set before use in a PostgREST
  `or` clause; LIKE wildcards escaped so a user's `%` matches literally.
- Keyset cursors encoded from the sort values, with the extra-row fetch that
  determines `hasMore` without a second count query.
- Retry deliberately **not** delegated to the PostgREST client, so the SDK-wide
  retry budget is not multiplied by a second retry layer.
- `SupabaseClientFactory` as the injection seam, so the provider is testable
  without a Flutter binding, `SharedPreferences` or a network.

**Schema**

- `supabase/migrations/`: reference tables and indexes, `is_admin()`,
  owner-based / admin / public / soft-delete RLS policies, auth lifecycle
  triggers, per-column privileges that stop self-promotion, four private storage
  buckets with owner-based policies, and the realtime publication.

**Tests**

- 328 unit tests across 10 suites, all against in-memory fakes. No network calls.
- `test/public_api_test.dart` reads the barrel and every library it exports and
  fails on a Supabase type, a raw provider record, a provider import outside
  `lib/src/providers/`, a physical table or bucket name in public code, or an
  undocumented public member.

### Known limitations

- `PostgresChangeEvent.all` handling and non-equality realtime filters are
  deliberately limited: a watch filter that cannot be expressed as equality is
  rejected rather than silently ignored.
- Cursor pagination uses PostgREST's offset/limit under the hood with a keyset
  predicate; a true keyset index would be faster on very large tables.
- `moveFile` and `copyFile` do not report the destination size or MIME type
  without an extra round trip; download or list the bucket if you need them.
- The Users module has no soft delete, because the reference `users` schema has
  no `deleted_at` column.
