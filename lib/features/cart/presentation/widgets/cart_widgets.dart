import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/cart_controller.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../../product/presentation/widgets/product_size_selector.dart';

/// Карточка товара в корзине.
class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
  });

  final CartItem item;
  final VoidCallback onRemove;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  static const _icons = [
    Icons.diamond_outlined,
    Icons.blur_circular_outlined,
    Icons.link_rounded,
    Icons.watch_outlined,
    Icons.favorite_border_rounded,
    Icons.circle_outlined,
    Icons.watch_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final icon = _icons[product.iconIndex % _icons.length];
    final languageCode = LocaleScope.of(context).languageCode;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              icon,
              size: 36,
              color: AppColors.accent.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.localizedName(languageCode),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.productName(),
                ),
                if (item.selectedSize != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Размер: ${formatSizeLabel(item.selectedSize!)}',
                    style: AppTypography.productMeta(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  formatWon(product.salePrice),
                  style: AppTypography.price(
                    fontSize: 16,
                    color: AppColors.saleRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _CartQtyStepper(
                  quantity: item.quantity,
                  canIncrement: item.quantity < product.stockQuantity,
                  onIncrement: onIncrement,
                  onDecrement: onDecrement,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.saleRed,
          ),
        ],
      ),
    );
  }
}

/// Блок промокода и списания бонусов.
class _CartQtyStepper extends StatelessWidget {
  const _CartQtyStepper({
    required this.quantity,
    required this.canIncrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final bool canIncrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyIconButton(
            icon: Icons.remove_rounded,
            onTap: onDecrement,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$quantity',
              style: AppTypography.caption(fontWeight: FontWeight.w700)
                  .copyWith(fontSize: 13),
            ),
          ),
          _QtyIconButton(
            icon: Icons.add_rounded,
            onTap: canIncrement ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

class _QtyIconButton extends StatelessWidget {
  const _QtyIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textPrimary : AppColors.border,
        ),
      ),
    );
  }
}

class CartLoyaltySection extends StatelessWidget {
  const CartLoyaltySection({
    super.key,
    required this.promoController,
    required this.useBonuses,
    required this.availableBonuses,
    required this.bonusDeduction,
    required this.onPromoChanged,
    required this.onUseBonusesChanged,
  });

  final TextEditingController promoController;
  final bool useBonuses;
  final int availableBonuses;
  final int bonusDeduction;
  final ValueChanged<String> onPromoChanged;
  final ValueChanged<bool> onUseBonusesChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Лояльность',
            style: AppTypography.heading(fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: promoController,
            onChanged: onPromoChanged,
            decoration: InputDecoration(
              hintText: 'Промокод',
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Списать бонусы (₩)',
                      style: AppTypography.caption(fontWeight: FontWeight.w600)
                          .copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Доступно: $availableBonuses бонусов',
                      style: AppTypography.productMeta(),
                    ),
                  ],
                ),
              ),
              Switch(
                value: useBonuses,
                onChanged: onUseBonusesChanged,
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.accent.withValues(alpha: 0.35),
              ),
            ],
          ),
          if (useBonuses && bonusDeduction > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Будет списано: $bonusDeduction бонусов',
                style: AppTypography.caption(color: AppColors.accent)
                    .copyWith(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Итоговый расчёт корзины.
class CartSummarySection extends StatelessWidget {
  const CartSummarySection({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.promoDiscount,
    required this.bonusDeduction,
    required this.total,
  });

  final int subtotal;
  final int discount;
  final int promoDiscount;
  final int bonusDeduction;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Стоимость', value: formatWon(subtotal)),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Скидка',
            value: '- ${formatWon(discount)}',
            valueColor: AppColors.saleRed,
          ),
          if (promoDiscount > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Промокод',
              value: '- ${formatWon(promoDiscount)}',
              valueColor: AppColors.accent,
            ),
          ],
          if (bonusDeduction > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Списано бонусов',
              value: '- ${formatWon(bonusDeduction)}',
              valueColor: AppColors.accent,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppColors.border, height: 1),
          ),
          _SummaryRow(
            label: 'Итого к оплате',
            value: formatWon(total),
            isTotal: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? AppTypography.heading(fontSize: 16)
              : AppTypography.productMeta().copyWith(fontSize: 14),
        ),
        Text(
          value,
          style: isTotal
              ? AppTypography.price(fontSize: 18, color: AppColors.primary)
              : AppTypography.price(
                  fontSize: 14,
                  color: valueColor ?? AppColors.textPrimary,
                ),
        ),
      ],
    );
  }
}

/// Нижняя панель оплаты корзины.
class CartCheckoutBar extends StatelessWidget {
  const CartCheckoutBar({
    super.key,
    required this.total,
    required this.onCheckout,
  });

  final int total;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: AppTypography.caption(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.w700,
                  ).copyWith(fontSize: 16),
                ),
                child: const Text('Перейти к оплате'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Доступна рассрочка: Яндекс Сплит и Долями',
              textAlign: TextAlign.center,
              style: AppTypography.productMeta().copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
