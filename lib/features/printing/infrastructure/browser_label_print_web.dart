// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../domain/jewelry_label_data.dart';
import '../presentation/widgets/jewelry_retail_tag_preview.dart';
import '../../../../core/utils/won_format.dart';

/// PWA: системный диалог печати браузера (HTML + @page 30×20 mm).
Future<void> printJewelryLabelPlatform(
  JewelryLabelData data, {
  dynamic labelPrintService,
}) async {
  final doc = _buildPrintHtml(data);
  final iframe = html.IFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = 'none';
  html.document.body?.append(iframe);

  iframe.srcdoc = doc;
  await iframe.onLoad.first;
  final win = iframe.contentWindow;
  if (win is html.Window) {
    win.print();
  }

  Future<void>.delayed(const Duration(milliseconds: 800), () {
    iframe.remove();
  });
}

String _htmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _buildPrintHtml(JewelryLabelData data) {

  final name = _htmlEscape(data.productName);
  final sku = _htmlEscape(data.sku);
  final meta = _htmlEscape(data.probeSizeWeightLine);
  final price = _htmlEscape(formatWon(data.priceKrw));
  final w = JewelryRetailTagPreview.tagWidthMm;
  final h = JewelryRetailTagPreview.tagHeightMm;

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Label $sku</title>
<style>
@page { size: ${w}mm ${h}mm; margin: 0; }
html, body { margin: 0; padding: 0; width: ${w}mm; height: ${h}mm; }
.tag {
  box-sizing: border-box;
  width: ${w}mm;
  height: ${h}mm;
  padding: 1.2mm 1.5mm;
  font-family: Arial, Helvetica, sans-serif;
  border: 0.2mm solid #000;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.name { font-size: 6.5pt; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sku { font-size: 9pt; font-weight: 800; text-align: center; letter-spacing: 0.3pt; margin: 0.5mm 0; }
.bars {
  flex: 1;
  min-height: 6mm;
  background: repeating-linear-gradient(
    90deg,
    #000 0 0.4mm,
    #fff 0.4mm 0.9mm,
    #000 0.9mm 1.1mm,
    #fff 1.1mm 1.7mm
  );
  border: 0.15mm solid #ccc;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  padding-bottom: 0.3mm;
}
.bars span { font-size: 5pt; font-family: monospace; background: #fff; padding: 0 0.5mm; }
.meta { font-size: 6pt; line-height: 1.15; }
.price { font-size: 7.5pt; font-weight: 700; }
</style>
</head>
<body>
<div class="tag">
  <div class="name">$name</div>
  <div class="sku">$sku</div>
  <div class="bars"><span>$sku</span></div>
  <div class="meta">$meta</div>
  <div class="price">$price</div>
</div>
<script>window.onload = function() { window.focus(); };</script>
</body>
</html>''';
}
