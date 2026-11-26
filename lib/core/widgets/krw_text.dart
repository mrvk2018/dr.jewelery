import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/won_format.dart';

/// Визуальный стандарт сумм: `−₩··2,217,000` / `+₩··141,000` / `₩··2,217,000`.
class KrwText extends StatelessWidget {
  const KrwText({
    super.key,
    required this.amount,
    this.style,
    this.currencyColor,
    this.digitStyle,
    this.showPlusSign = false,
    this.suffix,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.decoration,
    this.decorationColor,
  });

  final num amount;
  final TextStyle? style;
  final Color? currencyColor;
  final TextStyle? digitStyle;
  final bool showPlusSign;
  final String? suffix;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDecoration? decoration;
  final Color? decorationColor;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = buildKrwAmountSpans(
      amount: amount,
      baseStyle: base,
      currencyColor: currencyColor,
      digitStyle: digitStyle,
      showPlusSign: showPlusSign,
      suffix: suffix,
      decoration: decoration,
      decorationColor: decorationColor,
    );

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

/// Вставка суммы в `Text.rich` рядом с обычным текстом.
List<InlineSpan> buildKrwAmountSpans({
  required num amount,
  TextStyle? baseStyle,
  Color? currencyColor,
  TextStyle? digitStyle,
  bool showPlusSign = false,
  String? suffix,
  TextDecoration? decoration,
  Color? decorationColor,
}) {
  final rounded = amount.round();
  final sign = rounded < 0 ? '−' : (showPlusSign && rounded > 0 ? '+' : '');
  final wonColor = currencyColor ?? AppColors.currencyWonAccent;
  final base = baseStyle ?? const TextStyle();
  final digits = formatKrwDigits(rounded);
  final digitsStyle = (digitStyle ?? base).copyWith(
    decoration: decoration,
    decorationColor: decorationColor ?? base.color,
  );
  final signStyle = base.copyWith(
    decoration: decoration,
    decorationColor: decorationColor ?? base.color,
  );

  return [
    if (sign.isNotEmpty) TextSpan(text: sign, style: signStyle),
    TextSpan(
      text: '₩$kKrwWonNumberGap',
      style: base.copyWith(color: wonColor),
    ),
    TextSpan(text: digits, style: digitsStyle),
    if (suffix != null && suffix.isNotEmpty) TextSpan(text: suffix, style: base),
  ];
}