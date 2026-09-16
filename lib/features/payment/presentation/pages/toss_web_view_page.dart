import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Исход WebView Toss Payments для [PaymentScreen].
enum TossPaymentWebViewResult {
  success,
  failed,
  cancelled,
}

/// Встроенный WebView для виджета Toss Payments с перехватом redirect URL.
class TossWebViewPage extends StatefulWidget {
  const TossWebViewPage({
    super.key,
    required this.initialUrl,
    required this.successRedirectUrl,
    required this.failRedirectUrl,
  });

  final String initialUrl;
  final String successRedirectUrl;
  final String failRedirectUrl;

  @override
  State<TossWebViewPage> createState() => _TossWebViewPageState();
}

class _TossWebViewPageState extends State<TossWebViewPage> {
  late final WebViewController _controller;
  var _isLoading = true;
  var _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
            _handleRedirectUrl(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final handled = _handleRedirectUrl(request.url);
    return handled ? NavigationDecision.prevent : NavigationDecision.navigate;
  }

  bool _handleRedirectUrl(String url) {
    if (_isCompleting) return true;

    if (_matchesRedirect(url, widget.successRedirectUrl, successHint: true)) {
      _complete(TossPaymentWebViewResult.success);
      return true;
    }
    if (_matchesRedirect(url, widget.failRedirectUrl, successHint: false)) {
      _complete(TossPaymentWebViewResult.failed);
      return true;
    }
    return false;
  }

  bool _matchesRedirect(
    String url,
    String configuredRedirect, {
    required bool successHint,
  }) {
    if (configuredRedirect.isNotEmpty && url.contains(configuredRedirect)) {
      return true;
    }
    final lower = url.toLowerCase();
    if (successHint) {
      return lower.contains('payment/success') || lower.contains('/success');
    }
    return lower.contains('payment/fail') || lower.contains('/fail');
  }

  void _complete(TossPaymentWebViewResult result) {
    if (_isCompleting || !mounted) return;
    _isCompleting = true;
    Navigator.of(context).pop(result);
  }

  void _onUserClose() {
    _complete(TossPaymentWebViewResult.cancelled);
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
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
          ],
        ),
      ),
    );
  }
}
