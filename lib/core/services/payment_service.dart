import '../../features/payment/domain/models/payment_models.dart';

/// Параметры открытия Toss Payments Widget во встроенном WebView.
class TossPaymentLaunchConfig {
  const TossPaymentLaunchConfig({
    required this.widgetUrl,
    required this.orderId,
    required this.amount,
    required this.method,
  });

  /// Полный URL (или deep-link) для загрузки в WebView.
  final String widgetUrl;

  final String orderId;
  final int amount;
  final PaymentMethodType method;
}

/// Публичный client key и redirect URL задаются при инициализации (не хранить secret key).
class PaymentServiceConfig {
  const PaymentServiceConfig({
    this.tossClientKey = '',
    this.createOrderDraftUrl,
    this.paymentWidgetEntryUrl =
        'https://payment-widget.tosspayments.com/v2/entry',
    this.successRedirectUrl = 'sunlight://payment/success',
    this.failRedirectUrl = 'sunlight://payment/fail',
  });

  /// Toss Payments client key (test/live) — только публичный ключ.
  final String tossClientKey;

  /// Будущий REST endpoint: POST черновика заказа → `{ "orderId": "..." }`.
  final String? createOrderDraftUrl;

  final String paymentWidgetEntryUrl;
  final String successRedirectUrl;
  final String failRedirectUrl;
}

/// Оплата и подготовка Toss Widget; UI вызывает через [paymentService].
class PaymentService {
  PaymentService._({PaymentServiceConfig config = const PaymentServiceConfig()})
      : _config = config;

  static PaymentService? _instance;

  /// Единая точка доступа для экранов оплаты.
  static PaymentService get instance =>
      _instance ??= PaymentService._();

  /// Переинициализация (тесты, смена окружения, client key из remote config).
  static void configure(PaymentServiceConfig config) {
    _instance = PaymentService._(config: config);
  }

  final PaymentServiceConfig _config;

  TossPaymentLaunchConfig? _lastTossLaunchConfig;

  /// Последняя успешно подготовленная конфигурация WebView (после [initializeTossPayment]).
  TossPaymentLaunchConfig? get lastTossLaunchConfig => _lastTossLaunchConfig;

  String get successRedirectUrl => _config.successRedirectUrl;

  String get failRedirectUrl => _config.failRedirectUrl;

  /// Создаёт черновик заказа на бэкенде и возвращает [orderId] для Toss.
  ///
  /// Сейчас заглушка; при появлении API — POST на [_config.createOrderDraftUrl].
  Future<String> createOrderDraft({
    required int amount,
    required Map<String, dynamic> shippingAddress,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }

    final endpoint = _config.createOrderDraftUrl;
    if (endpoint != null && endpoint.isNotEmpty) {
      // TODO(prod): HTTP POST { amount, shippingAddress } → parse orderId.
      // Secret key и подпись платежа — только на сервере.
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'ORD-$timestamp';
  }

  /// Готовит URL Toss Payments Widget для WebView.
  ///
  /// Возвращает `false`, если способ оплаты не поддерживается виджетом Toss
  /// (например, банковский перевод) или не задан client key.
  Future<bool> initializeTossPayment({
    required String orderId,
    required int amount,
    required PaymentMethodType method,
  }) async {
    _lastTossLaunchConfig = null;

    if (orderId.isEmpty || amount <= 0) {
      return false;
    }

    if (method == PaymentMethodType.bankTransfer) {
      return false;
    }

    if (_config.tossClientKey.isEmpty) {
      return false;
    }

    final tossMethod = _tossEasyPayMethod(method);
    if (tossMethod == null) {
      return false;
    }

    final uri = Uri.parse(_config.paymentWidgetEntryUrl).replace(
      queryParameters: <String, String>{
        'clientKey': _config.tossClientKey,
        'orderId': orderId,
        'amount': amount.toString(),
        'successUrl': _config.successRedirectUrl,
        'failUrl': _config.failRedirectUrl,
        'method': tossMethod,
      },
    );

    _lastTossLaunchConfig = TossPaymentLaunchConfig(
      widgetUrl: uri.toString(),
      orderId: orderId,
      amount: amount,
      method: method,
    );

    return true;
  }

  String? _tossEasyPayMethod(PaymentMethodType method) {
    switch (method) {
      case PaymentMethodType.tossPay:
        return 'TOSSPAY';
      case PaymentMethodType.kakaoPay:
        return 'KAKAOPAY';
      case PaymentMethodType.appCard:
        return 'CARD';
      case PaymentMethodType.bankTransfer:
        return null;
    }
  }
}

/// Глобальный accessor для [PaymentScreen] и других UI-слоёв.
PaymentService get paymentService => PaymentService.instance;
