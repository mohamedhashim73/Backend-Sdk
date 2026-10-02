import '../../contracts/data_backend.dart';
import '../../core/backend_logger.dart';
import '../../core/backend_repository.dart';
import '../../core/backend_resource.dart';
import '../../pagination/cursor_page_result.dart';
import '../../pagination/cursor_request.dart';
import '../../pagination/page_request.dart';
import '../../pagination/page_result.dart';
import '../../realtime/realtime_repository.dart';
import '../../realtime/realtime_resource.dart';
import '../../result/backend_result.dart';
import '../../retry/cancellation_token.dart';
import '../../retry/request_executor.dart';
import 'product_mapper.dart';
import 'product_model.dart';
import 'product_requests.dart';

/// The complete, typed products API.
///
/// This is the reference module for the package: model, requests, validation,
/// mapping, pagination, search, filters, sorting, soft delete and typed
/// failures. An application uses exactly this shape for every module it adds.
///
/// ```dart
/// final result = await BackendSdk.instance.products.getPage(
///   request: PageRequest(
///     page: 1,
///     pageSize: 20,
///     search: 'phone',
///     filters: [
///       FilterCondition.equals(ProductFilterField.isActive, true),
///     ],
///     sorting: [SortCondition.descending(ProductSortField.createdAt)],
///   ),
/// );
///
/// result.when(
///   success: (page) => render(page.items, hasMore: page.hasMore),
///   failure: (failure) => showMessage(failure.safeMessage),
/// );
/// ```
///
/// The application never passes a table name, a column string, or a raw record
/// to any of these methods.
class ProductsRepository {
  final BackendRepository<Product, CreateProductRequest, UpdateProductRequest>
      _repository;

  final RealtimeRepository? _realtime;

  /// Creates a products repository over a data [backend].
  ///
  /// When a [realtime] repository is supplied this module also registers its
  /// realtime decoder, so watching [BackendResource.products] yields typed
  /// [Product]s without the application supplying a mapper.
  ProductsRepository({
    required DataBackend backend,
    required RequestExecutor executor,
    BackendLogger logger = const NoopBackendLogger(),
    RealtimeRepository? realtime,
    DateTime Function()? clock,
  })  : _repository = BackendRepository<Product, CreateProductRequest,
            UpdateProductRequest>(
          backend: backend,
          codec: const ProductCodec(),
          executor: executor,
          logger: logger,
          clock: clock,
        ),
        _realtime = realtime {
    _realtime?.registerDecoder(
      BackendResource.products,
      (record) => const ProductCodec().decode(record).data,
    );
  }

  /// The underlying generic repository.
  ///
  /// Exposed for advanced composition; ordinary callers use the typed methods.
  BackendRepository<Product, CreateProductRequest, UpdateProductRequest>
      get engine => _repository;

  /// Reads a product by its id.
  ///
  /// Returns a `notFound` failure when the product does not exist, has been
  /// soft-deleted, or is hidden by row level security.
  Future<BackendResult<Product>> getById(
    String id, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.getById(id, cancellationToken: cancellationToken);
  }

  /// Reads one offset-paginated page of products.
  ///
  /// A `search` term is matched case-insensitively against the product name and
  /// category. The ordering is made deterministic automatically, so paging is
  /// stable even when many products share a sort value.
  Future<BackendResult<PageResult<Product>>> getPage({
    required PageRequest request,
    CancellationToken? cancellationToken,
  }) {
    return _repository.getPage(
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  /// Reads one cursor-paginated page of products.
  ///
  /// Prefer this over [getPage] for an infinite-scroll catalogue.
  Future<BackendResult<CursorPageResult<Product>>> getCursorPage({
    required CursorRequest request,
    CancellationToken? cancellationToken,
  }) {
    return _repository.getCursorPage(
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  /// Counts the products matching [request]'s filters and search.
  Future<BackendResult<int>> count({
    PageRequest request = const PageRequest(page: 1, pageSize: 1),
    CancellationToken? cancellationToken,
  }) {
    return _repository.count(
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  /// Creates a product.
  Future<BackendResult<Product>> create(
    CreateProductRequest request, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.create(request, cancellationToken: cancellationToken);
  }

  /// Updates the product identified by [id].
  Future<BackendResult<Product>> update(
    String id,
    UpdateProductRequest request, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.update(
      id,
      request,
      cancellationToken: cancellationToken,
    );
  }

  /// Permanently removes the product identified by [id].
  ///
  /// Prefer [softDelete] unless the record really must disappear: the shipped
  /// RLS policies and the audit trail both assume deleted products are retained.
  Future<BackendResult<void>> delete(
    String id, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.delete(id, cancellationToken: cancellationToken);
  }

  /// Marks the product identified by [id] as deleted.
  ///
  /// The row is retained with a `deleted_at` timestamp, which is immediately
  /// invisible to every SDK read and is handled consistently by the database
  /// policies in `supabase/migrations`.
  Future<BackendResult<Product>> softDelete(
    String id, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.softDelete(id, cancellationToken: cancellationToken);
  }

  /// Watches products for insert, update and delete events.
  ///
  /// ```dart
  /// final watcher = BackendSdk.instance.realtime.watch<Product>(
  ///   resource: BackendResource.products,
  /// );
  /// final subscription = await watcher.ready;
  /// ```
  RealtimeSubscription<Product> watchRealtime({
    Map<String, Object?> filters = const {},
  }) {
    final realtime = _realtime;
    if (realtime == null) {
      throw StateError(
        'ProductsRepository was created without a RealtimeRepository, so '
        'watchRealtime() is unavailable. Pass `realtime:` when constructing it.',
      );
    }
    return realtime.watch<Product>(
      resource: BackendResource.products,
      filters: filters,
    );
  }
}
