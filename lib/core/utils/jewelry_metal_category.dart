/// Категория металла (совпадает с [classify_jewelry_metal_category] в Supabase).
enum JewelryMetalCategory { gold, silver, other }

final RegExp _goldProbePattern = RegExp(
  r'(^|[^0-9])(585|750|583|375)([^0-9]|$)',
  caseSensitive: false,
);

JewelryMetalCategory classifyJewelryMetalCategory({
  String? metal,
  String? metalType,
}) {
  final parts = <String>[
    if (metal != null && metal.trim().isNotEmpty) metal.trim(),
    if (metalType != null && metalType.trim().isNotEmpty) metalType.trim(),
  ];
  if (parts.isEmpty) return JewelryMetalCategory.other;

  final haystack = parts.join(' ').toLowerCase();

  if (haystack.contains('золото') || _goldProbePattern.hasMatch(haystack)) {
    return JewelryMetalCategory.gold;
  }
  if (haystack.contains('серебр') || haystack.contains('925')) {
    return JewelryMetalCategory.silver;
  }
  return JewelryMetalCategory.other;
}