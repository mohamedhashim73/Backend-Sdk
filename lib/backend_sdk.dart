/// A provider-agnostic backend SDK for Flutter and Dart applications.
///
/// This is the **only** library an application imports:
///
/// ```dart
/// import 'package:backend_sdk/backend_sdk.dart';
/// ```
///
/// The public surface below contains no Supabase type of any kind: no
/// `SupabaseClient`, no Supabase `User` or `Session`, no `PostgrestResponse`,
/// no `PostgrestException`, no `StorageFileApi`, no `RealtimeChannel`, no table
/// name and no raw provider payload. All provider code lives in
/// `lib/src/providers/` and never crosses this boundary.
///
/// ## Getting started
///
/// ```dart
/// await BackendSdk.initialize(
///   provider: BackendProvider.supabase,
///   configuration: BackendConfiguration.supabase(
///     url: AppEnvironment.supabaseUrl,
///     apiKey: AppEnvironment.supabaseAnonKey,
///   ),
/// );
///
/// final result = await BackendSdk.instance.auth.login(
///   email: email,
///   password: password,
/// );
/// result.when(
///   success: (session) => navigateHome(session.user),
///   failure: (failure) => showMessage(failure.safeMessage),
/// );
/// ```
///
/// ## Design rules
///
/// * Every operation returns a `BackendResult`; no call throws a provider
///   exception.
/// * Every failure is a `BackendFailure` with a vendor-neutral
///   `BackendErrorType` and a user-safe message.
/// * Pagination, filtering, sorting, retry, timeout and error mapping are
///   handled by the SDK, not by the application.
/// * A new backend vendor is added by implementing the contracts under
///   `lib/src/contracts/`; application code does not change.
library;

export 'src/auth/auth_repository.dart';
export 'src/auth/auth_session.dart';
export 'src/auth/auth_state.dart';
export 'src/auth/auth_user.dart';
export 'src/core/backend_configuration.dart';
export 'src/core/backend_logger.dart';
export 'src/core/backend_provider.dart';
export 'src/core/backend_repository.dart' show BackendRepository;
export 'src/core/backend_resource.dart';
export 'src/core/backend_sdk.dart';
export 'src/core/dependency_container.dart'
    show
        BackendServiceFactory,
        BackendServiceFactoryEntry,
        BackendServices,
        UnsupportedProviderFailure;
export 'src/core/resource_codec.dart'
    show BackendResourceDescriptor, CodecFailures, ResourceCodec;
export 'src/core/data_backend_api.dart';
export 'src/errors/backend_error_mapper.dart'
    show BackendErrorClassifier, BackendErrorMapper;
export 'src/errors/backend_error_type.dart';
export 'src/errors/backend_failure.dart';
export 'src/filters/filter_condition.dart'
    show
        ContainsFilter,
        EqualsFilter,
        FilterCondition,
        FilterFieldValidator,
        GreaterThanFilter,
        GreaterThanOrEqualFilter,
        InListFilter,
        IsNotNullFilter,
        IsNullFilter,
        LessThanFilter,
        LessThanOrEqualFilter,
        NotEqualsFilter,
        StartsWithFilter,
        TextSearchFilter;
export 'src/filters/filter_operator.dart';
export 'src/filters/sort_condition.dart';
export 'src/modules/products/product_columns.dart';
export 'src/modules/products/product_mapper.dart'
    show ProductCodec, ProductColumnsDefinition;
export 'src/modules/products/product_model.dart';
export 'src/modules/products/product_requests.dart';
export 'src/modules/products/products_repository.dart';
export 'src/modules/users/user_model.dart';
export 'src/modules/users/user_requests.dart';
export 'src/modules/users/users_repository.dart';
export 'src/pagination/cursor_page_result.dart';
export 'src/pagination/cursor_request.dart';
export 'src/pagination/page_request.dart';
export 'src/pagination/page_result.dart';
export 'src/pagination/pagination_limits.dart';
export 'src/realtime/realtime_event.dart';
export 'src/realtime/realtime_repository.dart'
    show RealtimeDecoder, RealtimeRepository;
export 'src/realtime/realtime_resource.dart'
    show RealtimeResource, RealtimeSubscription;
export 'src/result/backend_result.dart';
export 'src/retry/cancellation_token.dart';
export 'src/retry/request_executor.dart';
export 'src/retry/retry_policy.dart';
export 'src/storage/storage_bucket.dart';
export 'src/storage/storage_path_validator.dart';
export 'src/storage/storage_repository.dart';
export 'src/storage/storage_requests.dart';
export 'src/storage/upload_file_request.dart';
export 'src/storage/uploaded_file.dart';
