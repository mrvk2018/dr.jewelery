import 'package:supabase_flutter/supabase_flutter.dart';

/// Must match Supabase policy allowlist for Incheon (super-admin).
const superAdminOwnerEmail = 'dr.jewelry.korea@gmail.com';

extension SupabaseUserExtension on User {
  bool get isSuperAdmin {
    final address = email?.trim().toLowerCase();
    if (address == null || address.isEmpty) return false;
    return address == superAdminOwnerEmail.toLowerCase();
  }

  String get branchLocation => isSuperAdmin ? 'incheon' : 'ansan';
}
