import '../../contracts/data_backend.dart';
import '../../core/backend_logger.dart';
import '../../core/backend_repository.dart';
import '../../core/backend_resource.dart';
import '../../core/resource_codec.dart';
import '../../errors/backend_failure.dart';
import '../../filters/sort_condition.dart';
import '../../pagination/cursor_page_result.dart';
import '../../pagination/cursor_request.dart';
import '../../pagination/page_request.dart';
import '../../pagination/page_result.dart';
import '../../realtime/realtime_repository.dart';
import '../../realtime/realtime_resource.dart';
import '../../result/backend_result.dart';
import '../../retry/cancellation_token.dart';
import '../../retry/request_executor.dart';
import 'user_model.dart';
import 'user_requests.dart';

/// The column layout of the users record.
abstract final class UserColumnsDefinition {
  /// The descriptor used by the users repository.
  static const BackendResourceDescriptor descriptor = BackendResourceDescriptor(
    resource: BackendResource.users,
    primaryKeyField: UserColumns.id,
    searchableFields: UserColumns.searchable,
    defaultSorting: <SortCondition>[
      SortCondition.ascending(UserColumns.displayName),
    ],
    createdAtField: UserColumns.createdAt,
    updatedAtField: UserColumns.updatedAt,
  );
}

/// Translates between [User] and a backend record, and validates requests.
class UserCodec
    implements ResourceCodec<User, CreateUserRequest, UpdateUserRequest> {
  /// The maximum accepted display-name length.
  static const int maxDisplayNameLength = 120;

  /// Creates a user codec.
  const UserCodec();

  @override
  BackendResourceDescriptor get descriptor => UserColumnsDefinition.descriptor;

  @override
  BackendResult<User> decode(BackendRecord record) {
    final id = record[UserColumns.id];
    if (id is! String || id.isEmpty) {
      return failureOf(
        CodecFailures.decode(
          'user',
          'the "${UserColumns.id}" column is missing or is not a non-empty '
              'string.',
        ),
      );
    }

    final isActive = record[UserColumns.isActive];
    if (isActive != null && isActive is! bool) {
      return failureOf(
        CodecFailures.decode(
          'user',
          'the "${UserColumns.isActive}" column is not a boolean.',
        ),
      );
    }

    return BackendSuccess<User>(
      User(
        id: id,
        displayName: _asString(record[UserColumns.displayName]),
        email: _asString(record[UserColumns.email]),
        avatarPath: _asString(record[UserColumns.avatarPath]),
        role: _asString(record[UserColumns.role]),
        isActive: isActive as bool? ?? true,
        createdAt: _asDateTime(record[UserColumns.createdAt]),
        updatedAt: _asDateTime(record[UserColumns.updatedAt]),
      ),
    );
  }

  @override
  BackendResult<Map<String, Object?>> encodeCreate(CreateUserRequest request) {
    return BackendSuccess<Map<String, Object?>>(<String, Object?>{
      UserColumns.id: request.id,
      UserColumns.displayName: request.displayName,
      UserColumns.email: request.email,
      UserColumns.role: request.role,
    });
  }

  @override
  BackendResult<Map<String, Object?>> encodeUpdate(UpdateUserRequest request) {
    final values = <String, Object?>{};
    if (request.displayName != null) {
      values[UserColumns.displayName] = request.displayName;
    }
    if (request.email != null) values[UserColumns.email] = request.email;
    if (request.avatarPath != null) {
      values[UserColumns.avatarPath] = request.avatarPath;
    }
    if (request.role != null) values[UserColumns.role] = request.role;
    if (request.isActive != null) {
      values[UserColumns.isActive] = request.isActive;
    }
    return BackendSuccess<Map<String, Object?>>(values);
  }

  @override
  BackendFailure? validateCreate(CreateUserRequest request) {
    if (request.id.trim().isEmpty) {
      return CodecFailures.field('A user id is required.');
    }
    if (request.displayName != null &&
        request.displayName!.trim().length > maxDisplayNameLength) {
      return CodecFailures.field(
        'The display name must not exceed $maxDisplayNameLength characters.',
      );
    }
    return null;
  }

  @override
  BackendFailure? validateUpdate(UpdateUserRequest request) {
    if (!request.hasChanges) {
      return CodecFailures.field(
        'The update request does not change any field.',
      );
    }
    if (request.displayName != null &&
        request.displayName!.trim().length > maxDisplayNameLength) {
      return CodecFailures.field(
        'The display name must not exceed $maxDisplayNameLength characters.',
      );
    }
    return null;
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static DateTime? _asDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

/// The complete, typed users API.
///
/// Rows are normally created by a database trigger on sign-up, so the write
/// methods exist mainly for administrative paths. Every read is still subject to
/// row level security: a non-admin user sees only their own row.
class UsersRepository {
  final BackendRepository<User, CreateUserRequest, UpdateUserRequest>
      _repository;

  final RealtimeRepository? _realtime;

  /// Creates a users repository over a data [backend].
  UsersRepository({
    required DataBackend backend,
    required RequestExecutor executor,
    BackendLogger logger = const NoopBackendLogger(),
    RealtimeRepository? realtime,
  })  : _repository =
            BackendRepository<User, CreateUserRequest, UpdateUserRequest>(
          backend: backend,
          codec: const UserCodec(),
          executor: executor,
          logger: logger,
        ),
        _realtime = realtime {
    _realtime?.registerDecoder(
      BackendResource.users,
      (record) => const UserCodec().decode(record).data,
    );
  }

  /// The underlying generic repository.
  BackendRepository<User, CreateUserRequest, UpdateUserRequest> get engine =>
      _repository;

  /// Reads a user profile by account id.
  Future<BackendResult<User>> getById(
    String id, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.getById(id, cancellationToken: cancellationToken);
  }

  /// Reads one offset-paginated page of user profiles.
  ///
  /// Without an admin role the database policies restrict this to the caller's
  /// own row, so a "list all users" screen legitimately returns only one record
  /// for a non-admin.
  Future<BackendResult<PageResult<User>>> getPage({
    required PageRequest request,
    CancellationToken? cancellationToken,
  }) {
    return _repository.getPage(
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  /// Reads one cursor-paginated page of user profiles.
  Future<BackendResult<CursorPageResult<User>>> getCursorPage({
    required CursorRequest request,
    CancellationToken? cancellationToken,
  }) {
    return _repository.getCursorPage(
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  /// Counts the user profiles matching [request]'s filters and search.
  Future<BackendResult<int>> count({
    PageRequest request = const PageRequest(page: 1, pageSize: 1),
    CancellationToken? cancellationToken,
  }) {
    return _repository.count(
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  /// Creates a user profile row.
  Future<BackendResult<User>> create(
    CreateUserRequest request, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.create(request, cancellationToken: cancellationToken);
  }

  /// Updates the profile identified by [id].
  Future<BackendResult<User>> update(
    String id,
    UpdateUserRequest request, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.update(
      id,
      request,
      cancellationToken: cancellationToken,
    );
  }

  /// Removes the profile identified by [id] permanently.
  Future<BackendResult<void>> delete(
    String id, {
    CancellationToken? cancellationToken,
  }) {
    return _repository.delete(id, cancellationToken: cancellationToken);
  }

  /// Watches user profiles for insert, update and delete events.
  RealtimeSubscription<User> watchRealtime({
    Map<String, Object?> filters = const {},
  }) {
    final realtime = _realtime;
    if (realtime == null) {
      throw StateError(
        'UsersRepository was created without a RealtimeRepository, so '
        'watchRealtime() is unavailable. Pass `realtime:` when constructing it.',
      );
    }
    return realtime.watch<User>(
      resource: BackendResource.users,
      filters: filters,
    );
  }
}
