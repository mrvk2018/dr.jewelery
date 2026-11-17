/// Результат RPC `activate_draft_product_by_id`.
typedef DraftActivateResult = ({
  bool ok,
  String? id,
  String? sku,
  String? storeLocation,
  String? error,
});