import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../core/services/korean_address_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Поиск корейского адреса через официальный виджет Daum Postcode (Kakao CDN).
class DaumPostcodeWebViewPage extends StatefulWidget {
  const DaumPostcodeWebViewPage({super.key});

  @override
  State<DaumPostcodeWebViewPage> createState() =>
      _DaumPostcodeWebViewPageState();
}

class _DaumPostcodeWebViewPageState extends State<DaumPostcodeWebViewPage> {
  late final WebViewController _controller;
  var _isLoading = true;
  var _isCompleting = false;

  static const _htmlBaseUrl = 'https://localhost/';
  static const _daumPostcodeScriptUrl =
      'https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'DaumBridge',
        onMessageReceived: _onDaumBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint(
              '[DaumPostcode] onWebResourceError '
              'code=${error.errorCode} description=${error.description}',
            );
          },
        ),
      )
      ..loadHtmlString(_buildPostcodeHtml(), baseUrl: _htmlBaseUrl);

    unawaited(_configurePlatformWebView(_controller));
  }

  Future<void> _configurePlatformWebView(WebViewController controller) async {
    if (!Platform.isAndroid) return;
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return;
    await platform.setMixedContentMode(MixedContentMode.alwaysAllow);
  }

  void _onDaumBridgeMessage(JavaScriptMessage message) {
    if (_isCompleting || !mounted) return;

    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['cancel'] == true) {
        _pop(null);
        return;
      }

      final postalCode = (decoded['zonecode'] as String?)?.trim() ?? '';
      final roadAddress = (decoded['roadAddress'] as String?)?.trim() ?? '';
      if (postalCode.isEmpty || roadAddress.isEmpty) return;

      _pop(
        KoreanAddressLookupResult(
          postalCode: postalCode,
          roadAddress: roadAddress,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[DaumPostcode] bridge parse error: $error');
      debugPrint('$stackTrace');
    }
  }

  void _pop(KoreanAddressLookupResult? result) {
    if (_isCompleting || !mounted) return;
    _isCompleting = true;
    Navigator.of(context).pop(result);
  }

  String _buildPostcodeHtml() {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Daum Postcode</title>
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #fff; }
    #wrap { width: 100%; height: 100%; }
  </style>
  <script src="$_daumPostcodeScriptUrl"></script>
</head>
<body>
  <div id="wrap"></div>
  <script>
    function sendToFlutter(payload) {
      if (window.DaumBridge && window.DaumBridge.postMessage) {
        DaumBridge.postMessage(JSON.stringify(payload));
      }
    }

    function embedPostcode() {
      new daum.Postcode({
        oncomplete: function(data) {
          var roadAddress = data.roadAddress || data.autoRoadAddress || data.address || '';
          sendToFlutter({
            zonecode: String(data.zonecode || ''),
            roadAddress: roadAddress
          });
        },
        onclose: function(state) {
          if (state === 'FORCE_CLOSE') {
            sendToFlutter({ cancel: true });
          }
        },
        width: '100%',
        height: '100%'
      }).embed(document.getElementById('wrap'));
    }

    if (typeof daum !== 'undefined' && daum.Postcode) {
      embedPostcode();
    } else {
      window.addEventListener('load', embedPostcode);
    }
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop(null);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            '주소 검색',
            style: AppTypography.heading(fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _pop(null),
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
