import 'admin_pos_sale_exception.dart';

class AdminPosArchiveResult {
  const AdminPosArchiveResult._({
    required this.ok,
    this.orderId,
    this.error,
  });

  final bool ok;
  final String? orderId;
  final AdminPosSaleException? error;

  factory AdminPosArchiveResult.success({String? orderId}) =>
      AdminPosArchiveResult._(ok: true, orderId: orderId);

  factory AdminPosArchiveResult.failure(AdminPosSaleException error) =>
      AdminPosArchiveResult._(ok: false, error: error);
}
