/// Ошибки RPC `archive_admin_pos_sale`.
enum AdminPosSaleFailure {
  concurrencyConflict,
  validation,
  forbidden,
  unknown,
}

class AdminPosSaleException implements Exception {
  const AdminPosSaleException(this.failure, {this.message});

  final AdminPosSaleFailure failure;
  final String? message;

  static const concurrencyUserMessage =
      'One of the items in your cart is no longer active or has already been sold.';

  String get userMessage => switch (failure) {
        AdminPosSaleFailure.concurrencyConflict => concurrencyUserMessage,
        AdminPosSaleFailure.validation =>
          message ?? 'Проверьте данные корзины и повторите.',
        AdminPosSaleFailure.forbidden =>
          message ?? 'Недостаточно прав для оформления продажи.',
        AdminPosSaleFailure.unknown =>
          message ?? 'Не удалось заархивировать продажу. Попробуйте снова.',
      };

  static AdminPosSaleFailure classify(Object error, {String? rpcMessage}) {
    final haystack = [
      error.toString(),
      if (rpcMessage != null) rpcMessage,
    ].join(' ').toLowerCase();

    if (_matchesConcurrency(haystack)) {
      return AdminPosSaleFailure.concurrencyConflict;
    }
    if (haystack.contains('forbidden') ||
        haystack.contains('42501') ||
        haystack.contains('not authorized')) {
      return AdminPosSaleFailure.forbidden;
    }
    if (haystack.contains('invalid') ||
        haystack.contains('discount') ||
        haystack.contains('empty')) {
      return AdminPosSaleFailure.validation;
    }
    return AdminPosSaleFailure.unknown;
  }

  static bool _matchesConcurrency(String haystack) {
    if (haystack.contains('already') &&
        (haystack.contains('sold') || haystack.contains('sale'))) {
      return true;
    }
    if (haystack.contains('not active') ||
        haystack.contains('no longer active') ||
        haystack.contains('unavailable') ||
        haystack.contains('stock') && haystack.contains('0')) {
      return true;
    }
    if (haystack.contains('concurrency') || haystack.contains('conflict')) {
      return true;
    }
    return false;
  }
}
