import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

String scrapLedgerBranchLabel(String code) => switch (code.toUpperCase()) {
      'ICN' => 'Инчхон (ICN)',
      'ANS' => 'Ансан (ANS)',
      'ALL' => 'Все филиалы',
      _ => code,
    };

String scrapPurityTitle(String purity) {
  final n = double.tryParse(purity) ?? 0;
  if (n >= 800) return 'Серебро $purity°';
  return 'Золото $purity°';
}

String formatScrapGrams(double grams, {int decimals = 3}) {
  if (grams == 0) return '0 г';
  final text = grams.toStringAsFixed(decimals);
  final trimmed = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '$trimmed г';
}

String formatScrapDelta(double delta) {
  final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '');
  return '$sign${formatScrapGrams(delta.abs())}';
}

String scrapLedgerWhen(DateTime? value) {
  if (value == null) return '—';
  final kst = value.toUtc().add(const Duration(hours: 9));
  return DateFormat('dd.MM.yyyy HH:mm').format(kst);
}

String scrapLedgerErrorMessage(Object? raw) {
  final text = raw?.toString() ?? '';
  final lower = text.toLowerCase();
  return switch (true) {
    _ when lower.contains('insufficient_scrap_weight') =>
      'Недостаточно лома на остатке по этой пробе.',
    _ when text == 'invalid_branch' => 'Укажите филиал ICN или ANS.',
    _ when text == 'invalid_purity' => 'Укажите корректную пробу.',
    _ when text == 'invalid_weight' => 'Вес должен быть больше 0.',
    _ when text == 'recipient_required' =>
      'Укажите, куда передан металл или причину списания.',
    _ when text == 'invalid_filter' => 'Неизвестный фильтр журнала.',
    _ when text == 'invalid_range' => 'Проверьте период дат.',
    _ => text.isEmpty ? 'Операция не выполнена.' : text,
  };
}

String scrapMovementLabel(String type) => switch (type) {
      'intake' => 'Приёмка',
      'trade_in' => 'Trade-In',
      'write_off' => 'Списание',
      'adjustment' => 'Корректировка',
      _ => type,
    };

Color scrapMovementColor(String type) => switch (type) {
      'intake' => const Color(0xFF2E7D32),
      'trade_in' => AppColors.primary,
      'write_off' => const Color(0xFFE65100),
      'adjustment' => const Color(0xFF6A1B9A),
      _ => AppColors.textSecondary,
    };

class ScrapMovementBadge extends StatelessWidget {
  const ScrapMovementBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color = scrapMovementColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        scrapMovementLabel(type),
        style: AppTypography.productMeta().copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}