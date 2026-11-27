import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../../../core/widgets/krw_text.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../utils/jewelry_qr_parser.dart';
import '../../../../widgets/universal_qr_scanner_sheet.dart';
import '../../application/pos_cart_controller.dart';
import '../widgets/admin_toast.dart';

class PosQrScannerSheet {
  static Future<void> open({
    required BuildContext context,
    required PosCartController cart,
    required DatabaseService database,
    String staffStoreCode = StoreLocationCode.icn,
  }) {
    return UniversalQrScannerSheet.show(
      context,
      title: 'POS · сканирование',
      onScan: (payload) => _onScan(
        context: context,
        cart: cart,
        database: database,
        staffStoreCode: staffStoreCode,
        payload: payload,
      ),
      footer: ListenableBuilder(
        listenable: cart,
        builder: (context, _) => _PosCartLiveFooter(
          cart: cart,
          onRemove: (id) => cart.removeFromCart(id),
        ),
      ),
    );
  }

  static Future<void> _onScan({
    required BuildContext context,
    required PosCartController cart,
    required DatabaseService database,
    required String staffStoreCode,
    required String payload,
  }) async {
    final parsed = JewelryQrParser.parse(payload);
    final lookup = parsed.lookupKey;
    if (lookup.isEmpty) {
      showAdminToast(context, 'Пустой QR', error: true);
      return;
    }

    final row = await database.fetchProductRowForPosLookup(lookup);
    if (!context.mounted) return;
    if (row == null) {
      showAdminToast(context, 'Товар не найден', error: true);
      return;
    }

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    final sku = row['sku']?.toString() ?? '';
    if (status == 'sold') {
      showAdminToast(context, 'Уже продано: $sku', error: true);
      return;
    }
    if (status == 'reserved') {
      showAdminToast(context, 'Изделие в брони: $sku', error: true);
      return;
    }
    if (status == 'in_transfer') {
      showAdminToast(context, 'Товар в трансфере: $sku', error: true);
      return;
    }

    final productId = row['id']?.toString() ?? '';
    if (productId.isNotEmpty && cart.containsProduct(productId)) {
      showAdminToast(context, 'Уже в POS-корзине: $sku');
      return;
    }

    final productStore = storeLocationCodeFromProductRow(row);
    if (productStore != StoreLocationCode.unselected &&
        productStore != staffStoreCode.toUpperCase()) {
      showAdminToast(
        context,
        'Другой филиал (${storeLocationDisplayLabel(productStore)}): $sku',
        error: true,
      );
    }

    try {
      final product = ProductItem.fromJson(
        CloudDatabaseService.productRowToClientJson(row),
      );
      if (!product.isCatalogPurchasable || product.isOutOfStock) {
        showAdminToast(context, 'Недоступно для продажи: $sku', error: true);
        return;
      }
      cart.addToCart(product);
      showAdminToast(context, 'В корзине: $sku');
    } catch (error) {
      showAdminToast(context, 'Ошибка: $error', error: true);
    }
  }
}

class _PosCartLiveFooter extends StatelessWidget {
  const _PosCartLiveFooter({
    required this.cart,
    required this.onRemove,
  });

  final PosCartController cart;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final lines = cart.items;
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      constraints: const BoxConstraints(maxHeight: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'POS-корзина',
                style: AppTypography.heading(fontSize: 14),
              ),
              const Spacer(),
              KrwText(
                amount: cart.totalFinalKrw,
                style: AppTypography.heading(fontSize: 16),
                digitStyle: AppTypography.heading(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            Text(
              'Сканируйте бирки…',
              style: AppTypography.productMeta(),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: lines.length,
                separatorBuilder: (_, __) => const Divider(height: 8),
                itemBuilder: (context, index) {
                  final line = lines[index];
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.product.sku,
                          style: AppTypography.productMeta().copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      KrwText(
                        amount: line.finalPriceKrw,
                        style: AppTypography.productMeta(),
                        digitStyle: AppTypography.productMeta(),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onRemove(line.product.id),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}