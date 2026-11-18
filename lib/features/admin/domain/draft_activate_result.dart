/// Результат RPC `activate_draft_product_by_id`.
typedef DraftActivateResult = ({
  bool ok,
  String? id,
  String? sku,
  String? storeLocation,
  String? error,
  /// `completed` | `cancelled` при авто-закрытии висящего `product_transfers` (045).
  String? transferResolution,
  String? transferFrom,
  String? transferTo,
});