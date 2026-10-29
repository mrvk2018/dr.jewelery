import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Исход WebView Toss Payments для [PaymentScreen].
enum TossPaymentWebViewResult {
  success,
  failed,
  cancelled,
}

/// Redirect Toss (successUrl) → query `paymentKey`, `orderId`, `amount`.
class TossPaymentWebViewPopResult {
  const TossPaymentWebViewPopResult({
    required this.result,
    this.paymentKey,
    this.orderId,
    this.amount,
  });

  final TossPaymentWebViewResult result;
  final String? paymentKey;
  final String? orderId;
  final int? amount;

  bool get hasConfirmPayload =>
      paymentKey != null &&
      paymentKey!.trim().isNotEmpty &&
      orderId != null &&
      orderId!.trim().isNotEmpty &&
      amount != null &&
      amount! > 0;
}

/// Встроенный WebView для виджета Toss Payments v2 (SDK через [loadHtmlString]).
class TossWebViewPage extends StatefulWidget {
  const TossWebViewPage({
    super.key,
    required this.clientKey,
    required this.orderId,
    required this.amount,
    required this.successUrl,
    required this.failUrl,
    required this.orderName,
    this.customerName = '',
    this.customerEmail = '',
  });

  final String clientKey;
  final String orderId;
  final int amount;
  final String successUrl;
  final String failUrl;
  final String orderName;
  final String customerName;
  final String customerEmail;

  @override
  State<TossWebViewPage> createState() => _TossWebViewPageState();
}

class _TossWebViewPageState extends State<TossWebViewPage> {
  late final WebViewController _controller;
  var _isLoading = true;
  var _isCompleting = false;
  var _tossWidgetsReady = false;

  static const _htmlBaseUrl = 'https://localhost/';

  @override
  void initState() {
    super.initState();
    final html = _buildTossWidgetHtml(
      clientKey: widget.clientKey,
      customerKey: widget.orderId,
      orderId: widget.orderId,
      amount: widget.amount,
      successUrl: widget.successUrl,
      failUrl: widget.failUrl,
      orderName: widget.orderName,
      customerName: widget.customerName,
      customerEmail: widget.customerEmail,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint('🛑 TOSS JS CONSOLE: ${message.message}');
      })
      ..addJavaScriptChannel(
        'TossBridge',
        onMessageReceived: (message) {
          if (message.message == 'ready' && mounted) {
            setState(() => _tossWidgetsReady = true);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: _onNavigationRequest,
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            if (_handleRedirectUrl(url)) return;
            if (!_isHttpOrHttpsUrl(url)) {
              unawaited(_launchExternalUrl(url));
            }
          },
          onWebResourceError: (error) {
            debugPrint(
              '[TossWebView] onWebResourceError '
              'code=${error.errorCode} '
              'type=${error.errorType} '
              'description=${error.description} '
              'url=${error.url}',
            );
            if (_isCriticalWebResourceError(error)) {
              _handleCriticalWebViewFailure(
                'webResourceError: ${error.description}',
              );
            }
          },
          onHttpError: (error) {
            debugPrint(
              '[TossWebView] onHttpError '
              'statusCode=${error.response?.statusCode} '
              'url=${error.request?.uri}',
            );
            if (_isCriticalHttpError(error)) {
              _handleCriticalWebViewFailure(
                'httpError: status=${error.response?.statusCode}',
              );
            }
          },
        ),
      )
      ..loadHtmlString(html, baseUrl: _htmlBaseUrl);

    unawaited(_configurePlatformWebView(_controller));
  }

  /// DOM Storage на Android включён в [AndroidWebViewController] по умолчанию;
  /// дополнительно разрешаем mixed content для ресурсов виджета.
  Future<void> _configurePlatformWebView(WebViewController controller) async {
    if (!Platform.isAndroid) return;
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return;

    await platform.setMixedContentMode(MixedContentMode.alwaysAllow);
    debugPrint(
      '[TossWebView] Android WebView: DOM Storage enabled by plugin default',
    );
  }

  static String _escapeJsString(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
  }

  static String _buildTossWidgetHtml({
    required String clientKey,
    required String customerKey,
    required String orderId,
    required int amount,
    required String successUrl,
    required String failUrl,
    required String orderName,
    String customerName = '',
    String customerEmail = '',
  }) {
    final jsClientKey = _escapeJsString(clientKey);
    final jsCustomerKey = _escapeJsString(customerKey);
    final jsOrderId = _escapeJsString(orderId);
    final jsSuccessUrl = _escapeJsString(successUrl);
    final jsFailUrl = _escapeJsString(failUrl);
    final jsOrderName = _escapeJsString(orderName);
    final jsCustomerName = _escapeJsString(customerName);
    final jsCustomerEmail = _escapeJsString(customerEmail);
    final customerFieldsJs = (customerName.isNotEmpty || customerEmail.isNotEmpty)
        ? '''
          customerName: "$jsCustomerName",
          customerEmail: "$jsCustomerEmail",
        '''
        : '';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://js.tosspayments.com/v2/standard" onerror="console.error('Не удалось загрузить Toss SDK')"></script>
  <script>
    var tossWidgets = null;

    async function initToss() {
      try {
        console.log("Toss SDK успешно загружен. Инициализация...");
        if (typeof TossPayments === "undefined") {
          throw new Error("TossPayments is undefined after script onload");
        }
        const tossPayments = TossPayments("$jsClientKey");
        tossWidgets = tossPayments.widgets({ customerKey: "$jsCustomerKey" });

        await tossWidgets.setAmount({
          currency: "KRW",
          value: $amount
        });

        await tossWidgets.renderPaymentMethods({
          selector: "#payment-method",
          variantKey: "DEFAULT"
        });

        await tossWidgets.renderAgreement({
          selector: "#agreement",
          variantKey: "AGREEMENT"
        });

        if (typeof TossBridge !== "undefined") {
          TossBridge.postMessage("ready");
        }
        console.log("Виджеты Toss успешно отрендерены!");
      } catch (error) {
        var msg = (error && error.message) ? error.message : String(error);
        console.error("Критическая ошибка инициализации Toss:", msg);
      }
    }

    async function requestTossPayment() {
      try {
        if (!tossWidgets) {
          console.error("Toss widgets еще не готовы");
          return;
        }
        console.log("Запрос оплаты requestPayment...");
        await tossWidgets.requestPayment({
          orderId: "$jsOrderId",
          orderName: "$jsOrderName",
          successUrl: "$jsSuccessUrl",
          failUrl: "$jsFailUrl",
          appScheme: "drjewelry",
          $customerFieldsJs
        });
      } catch (error) {
        var msg = (error && error.message) ? error.message : String(error);
        console.error("Ошибка requestPayment:", msg);
      }
    }

    // Гарантируем, что <body> и все контейнеры уже созданы в памяти браузера
    window.addEventListener('DOMContentLoaded', () => {
      initToss();
    });
  </script>
</head>
<body>
  <div id="payment-method"></div>
  <div id="agreement"></div>
</body>
</html>
''';
  }

  Future<void> _submitPayment() async {
    if (!_tossWidgetsReady) {
      debugPrint('[TossWebView] Pay tapped before widgets ready');
      return;
    }
    await _controller.runJavaScript('requestTossPayment()');
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final url = request.url;
    if (_handleRedirectUrl(url)) {
      return NavigationDecision.prevent;
    }
    if (!_isHttpOrHttpsUrl(url)) {
      unawaited(_launchExternalUrl(url));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  static bool _isHttpOrHttpsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static String? _convertIntentUrlToAppScheme(String intentUrl) {
    final normalized = intentUrl.trim();
    if (!normalized.toLowerCase().startsWith('intent:')) {
      return null;
    }

    final schemeMatch = RegExp(
      r';scheme=([^;]+);?',
      caseSensitive: false,
    ).firstMatch(normalized);
    final scheme = schemeMatch?.group(1);
    if (scheme == null || scheme.isEmpty) {
      return null;
    }

    final schemeStart = normalized.indexOf('://');
    final intentHash = normalized.indexOf('#Intent');
    if (schemeStart == -1 || intentHash == -1 || intentHash <= schemeStart + 3) {
      return null;
    }

    final path = normalized.substring(schemeStart + 3, intentHash);
    return '$scheme://$path';
  }

  static String? _extractIntentBrowserFallbackUrl(String intentUrl) {
    final match = RegExp(
      r';S\.browser_fallback_url=([^;]+);?',
      caseSensitive: false,
    ).firstMatch(intentUrl);
    if (match == null) {
      return null;
    }
    return Uri.decodeComponent(match.group(1)!);
  }

  Future<void> _launchExternalUrl(String url) async {
    try {
      final candidates = <String>[url];

      if (url.toLowerCase().startsWith('intent:')) {
        final appScheme = _convertIntentUrlToAppScheme(url);
        if (appScheme != null) {
          candidates.insert(0, appScheme);
        }
        final fallback = _extractIntentBrowserFallbackUrl(url);
        if (fallback != null) {
          candidates.add(fallback);
        }
      }

      for (final candidate in candidates) {
        final uri = Uri.tryParse(candidate);
        if (uri == null) {
          continue;
        }
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          debugPrint('[TossWebView] opened external url: $candidate');
          return;
        }
      }

      debugPrint('[TossWebView] launchUrl failed for all candidates: $candidates');
    } catch (error, stackTrace) {
      debugPrint(
        '[TossWebView] external launch error: $error\n$stackTrace',
      );
    }
  }

  bool _isCriticalWebResourceError(WebResourceError error) {
    if (error.isForMainFrame == true) {
      return true;
    }
    switch (error.errorType) {
      case WebResourceErrorType.connect:
      case WebResourceErrorType.hostLookup:
      case WebResourceErrorType.timeout:
      case WebResourceErrorType.failedSslHandshake:
      case WebResourceErrorType.badUrl:
      case WebResourceErrorType.unsupportedScheme:
      case WebResourceErrorType.redirectLoop:
      case WebResourceErrorType.webContentProcessTerminated:
      case WebResourceErrorType.webViewInvalidated:
        return true;
      default:
        return false;
    }
  }

  bool _isCriticalHttpError(HttpResponseError error) {
    final status = error.response?.statusCode;
    if (status == null || status < 400) {
      return false;
    }
    final uri = error.response?.uri ?? error.request?.uri;
    if (uri == null) {
      return true;
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.contains('tosspayments.com')) {
      return true;
    }
    return status >= 500;
  }

  void _handleCriticalWebViewFailure(String reason) {
    debugPrint('[TossWebView] critical failure: $reason');
    if (_isCompleting || !mounted) {
      return;
    }
    setState(() => _isLoading = false);
    _complete(
      const TossPaymentWebViewPopResult(
        result: TossPaymentWebViewResult.failed,
      ),
    );
  }

  bool _handleRedirectUrl(String url) {
    if (_isCompleting) return true;

    if (_matchesRedirect(url, widget.successUrl)) {
      _completeFromRedirect(url, TossPaymentWebViewResult.success);
      return true;
    }
    if (_matchesRedirect(url, widget.failUrl)) {
      _complete(
        const TossPaymentWebViewPopResult(
          result: TossPaymentWebViewResult.failed,
        ),
      );
      return true;
    }
    return false;
  }

  bool _matchesRedirect(String url, String configuredRedirect) {
    if (configuredRedirect.isEmpty) return false;
    return url.startsWith(configuredRedirect);
  }

  void _completeFromRedirect(String url, TossPaymentWebViewResult result) {
    final uri = Uri.tryParse(url);
    final paymentKey = uri?.queryParameters['paymentKey']?.trim();
    final orderId = uri?.queryParameters['orderId']?.trim();
    final amountRaw = uri?.queryParameters['amount'];
    final parsedAmount = amountRaw != null ? int.tryParse(amountRaw) : null;
    _complete(
      TossPaymentWebViewPopResult(
        result: result,
        paymentKey: paymentKey,
        orderId: orderId,
        amount: parsedAmount,
      ),
    );
  }

  void _complete(TossPaymentWebViewPopResult result) {
    if (_isCompleting || !mounted) return;
    _isCompleting = true;
    Navigator.of(context).pop(result);
  }

  void _onUserClose() {
    _complete(
      const TossPaymentWebViewPopResult(
        result: TossPaymentWebViewResult.cancelled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onUserClose();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Toss Payments',
            style: AppTypography.heading(fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onUserClose,
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _tossWidgetsReady ? _submitPayment : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textOnAccent,
                      disabledBackgroundColor:
                          AppColors.accent.withValues(alpha: 0.35),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _tossWidgetsReady ? 'Оплатить' : 'Загрузка Toss…',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnAccent,
                      ).copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
