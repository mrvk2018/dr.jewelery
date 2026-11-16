/// Результат RPC `set_draft_product_store_location` (jsonb ok/store_location/error).
typedef DraftStoreLocationResult = ({
  bool ok,
  String? storeLocation,
  String? error,
});