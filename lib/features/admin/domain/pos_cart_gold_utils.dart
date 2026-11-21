import '../../../core/utils/jewelry_metal_category.dart';
import '../../../shared/models/product_item.dart';
import 'models/pos_cart_item.dart';

bool isPosCartProductGold(ProductItem product) {
  final cat = classifyJewelryMetalCategory(
    metal: product.metal,
    metalType: product.metal,
  );
  if (cat == JewelryMetalCategory.gold) return true;
  final lower = product.metal.toLowerCase();
  return lower.contains('gold') || lower.contains('золото');
}

double sumPosCartGoldWeightGrams(Iterable<PosCartItem> lines) {
  var sum = 0.0;
  for (final line in lines) {
    if (!isPosCartProductGold(line.product)) continue;
    final w = line.product.weightGrams;
    if (w != null && w > 0) sum += w;
  }
  return sum;
}

int countPosCartGoldLines(Iterable<PosCartItem> lines) {
  return lines.where((l) => isPosCartProductGold(l.product)).length;
}