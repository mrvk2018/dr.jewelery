/// Публичная конфигурация Supabase для Flutter (anon / publishable key).
abstract final class SupabaseConfig {
  static const projectUrl = 'https://iuezgsvihzhfnrdpdbzn.supabase.co';
  static const anonKey =
      'sb_publishable_JO1MyY5BK8O1SJBvKbs7KA_dRci-qja';

  /// PKCE OAuth / link identity callback (добавить в Supabase Auth → Redirect URLs).
  static const oauthRedirectUrl =
      'com.jewelrysunlight.jewelry_sunlight_store://login-callback/';
}
