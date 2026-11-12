import 'package:supabase_flutter/supabase_flutter.dart';

import '../extensions/supabase_user_extension.dart';

/// Супер-админ Incheon: JWT owner-email **или** успешный локальный PIN панели.
abstract final class AdminAccess {
  static bool isSuperAdmin({
    User? supabaseUser,
    required bool localPanelAdmin,
  }) {
    if (localPanelAdmin) return true;
    return supabaseUser?.isSuperAdmin ?? false;
  }
}
