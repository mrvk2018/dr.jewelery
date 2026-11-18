/// Результат RPC `delete_product_permanently`.
typedef ProductDeleteResult = ({
  bool ok,
  String? id,
  String? sku,
  int transfersRemoved,
  String? error,
});