import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import 'api_error_language.dart';

/// Applies the configured language to the safe, user-facing part of a failure.
///
/// Technical details such as [BackendFailure.message], provider codes and the
/// original cause are intentionally preserved for diagnostics. Only
/// [BackendFailure.safeMessage] is localized.
abstract final class ApiErrorLocalizer {
  const ApiErrorLocalizer._();

  /// Returns [failure] with a localized user-facing message.
  static BackendFailure localize(
    BackendFailure failure,
    ApiErrorLanguage language,
  ) {
    final message = language == ApiErrorLanguage.ar
        ? _arabicMessage(failure.type)
        : failure.userMessage ??
            BackendFailure.defaultUserMessage(failure.type);
    return failure.copyWith(userMessage: message);
  }

  static String _arabicMessage(BackendErrorType type) {
    return switch (type) {
      BackendErrorType.configuration =>
        'إعداد التطبيق غير صحيح. يرجى التواصل مع الدعم.',
      BackendErrorType.network =>
        'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مرة أخرى.',
      BackendErrorType.timeout => 'استغرق الطلب وقتًا طويلًا. حاول مرة أخرى.',
      BackendErrorType.cancelled => 'تم إلغاء الطلب.',
      BackendErrorType.unauthorized =>
        'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.',
      BackendErrorType.forbidden => 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
      BackendErrorType.validation => 'بعض القيم المدخلة غير صالحة.',
      BackendErrorType.notFound => 'تعذر العثور على العنصر المطلوب.',
      BackendErrorType.conflict =>
        'يتعارض هذا الإجراء مع الحالة الحالية. حدّث البيانات وحاول مرة أخرى.',
      BackendErrorType.rateLimited =>
        'عدد الطلبات كبير جدًا. انتظر قليلًا وحاول مرة أخرى.',
      BackendErrorType.database ||
      BackendErrorType.storage ||
      BackendErrorType.realtime ||
      BackendErrorType.server =>
        'حدث خطأ من جانب الخادم. حاول مرة أخرى.',
      BackendErrorType.unsupportedProvider =>
        'هذه الميزة غير متاحة في الإصدار الحالي.',
      BackendErrorType.unknown => 'حدث خطأ ما. حاول مرة أخرى.',
    };
  }
}
