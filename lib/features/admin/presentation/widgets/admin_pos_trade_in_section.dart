import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/krw_text.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../application/pos_cart_controller.dart';
import '../../domain/trade_in_scrap_draft.dart';

class AdminPosTradeInSection extends StatelessWidget {
  const AdminPosTradeInSection({
    super.key,
    required this.cart,
    required this.storeLocation,
    required this.onStoreChanged,
    required this.onOpenTradeIn,
    required this.onEditTradeIn,
    required this.onRemoveTradeIn,
    required this.onRecalculateTradeIn,
    required this.checkoutBusy,
  });

  final PosCartController cart;
  final String storeLocation;
  final ValueChanged<String> onStoreChanged;
  final VoidCallback onOpenTradeIn;
  final VoidCallback onEditTradeIn;
  final VoidCallback onRemoveTradeIn;
  final VoidCallback onRecalculateTradeIn;
  final bool checkoutBusy;

  @override
  Widget build(BuildContext context) {
    final draft = cart.tradeInDraft;
    final hasGold = cart.hasGoldInCart;
    final stale = cart.tradeInGoldWeightStale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Магазин:', style: AppTypography.caption()),
            ChoiceChip(
              label: const Text('Инчхон'),
              selected: storeLocation == StoreLocationCode.icn,
              onSelected: checkoutBusy
                  ? null
                  : (_) => onStoreChanged(StoreLocationCode.icn),
            ),
            ChoiceChip(
              label: const Text('Ансан'),
              selected: storeLocation == StoreLocationCode.ans,
              onSelected: checkoutBusy
                  ? null
                  : (_) => onStoreChanged(StoreLocationCode.ans),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (draft == null) ...[
          Tooltip(
            message: hasGold ? '' : 'В корзине нет золотых изделий',
            child: FilledButton.icon(
              onPressed: checkoutBusy || !hasGold || cart.lineCount == 0
                  ? null
                  : onOpenTradeIn,
              icon: const Icon(Icons.recycling_outlined),
              label: const Text('Продажа с ломом'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textOnPrimary,
              ),
            ),
          ),
        ] else ...[
          _TradeInAttachedCard(
            draft: draft,
            cartTotalKrw: cart.totalFinalKrw,
            onEdit: onEditTradeIn,
            onRemove: onRemoveTradeIn,
          ),
          if (stale)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFC107)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFF57F17)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Вес золота в корзине изменился — пересчитайте лом',
                      style: AppTypography.productMeta(),
                    ),
                  ),
                  TextButton(
                    onPressed: checkoutBusy ? null : onRecalculateTradeIn,
                    child: const Text('Пересчитать'),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _TradeInAttachedCard extends StatelessWidget {
  const _TradeInAttachedCard({
    required this.draft,
    required this.cartTotalKrw,
    required this.onEdit,
    required this.onRemove,
  });

  final TradeInScrapDraft draft;
  final int cartTotalKrw;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final net = cartTotalKrw - draft.scrapTotalKrw;
    final badge = _netBadge(net);

    return Card(
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Продажа с ломом', style: AppTypography.heading(fontSize: 15)),
            const SizedBox(height: 8),
            _lineAmount('Сумма изделий', cartTotalKrw),
            _lineAmount(
              'Зачтено ломом (${draft.goldEquivalent585.toStringAsFixed(2)} г 585 экв.)',
              -draft.scrapTotalKrw,
            ),
            const SizedBox(height: 8),
            KrwText(
              amount: net,
              showPlusSign: net > 0,
              style: AppTypography.heading(fontSize: 22).copyWith(color: badge.color),
              digitStyle:
                  AppTypography.heading(fontSize: 22).copyWith(color: badge.color),
            ),
            Chip(
              label: Text(badge.label),
              backgroundColor: badge.color.withValues(alpha: 0.12),
              side: BorderSide(color: badge.color.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(onPressed: onEdit, child: const Text('Изменить')),
                TextButton(
                  onPressed: onRemove,
                  child: Text('Убрать', style: TextStyle(color: AppColors.saleRed)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _lineAmount(String label, int amount) {
    final valueStyle =
        AppTypography.productMeta().copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: AppTypography.productMeta())),
          KrwText(amount: amount, style: valueStyle, digitStyle: valueStyle),
        ],
      ),
    );
  }

  static ({String label, Color color}) _netBadge(int net) {
    if (net > 0) {
      return (label: 'Получить оплату', color: const Color(0xFF1B5E20));
    }
    if (net < 0) {
      return (label: 'Доплатить покупателю', color: AppColors.saleRed);
    }
    return (label: 'Обмен без доплаты', color: AppColors.textSecondary);
  }
}