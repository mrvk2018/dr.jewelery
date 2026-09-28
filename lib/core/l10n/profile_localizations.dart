/// Строки профиля (привязка аккаунта): корейский и английский.
abstract final class ProfileStringKeys {
  static const linkAccountMessage = 'profile_link_account_message';
  static const linkGoogle = 'profile_link_google';
  static const linkApple = 'profile_link_apple';
  static const linkFailed = 'profile_link_failed';
  static const linkSuccess = 'profile_link_success';
}

const _profileKoEn = <String, Map<String, String>>{
  ProfileStringKeys.linkAccountMessage: {
    'ko':
        'Google 또는 Apple로 로그인하면 스마트폰을 바꾸거나 앱을 삭제해도 '
        '적립된 보너스와 주문 내역을 안전하게 유지할 수 있습니다.',
    'en':
        'Sign in with Google or Apple to keep your bonus balance and order '
        'history when you change phones or reinstall the app.',
  },
  ProfileStringKeys.linkGoogle: {
    'ko': 'Google로 로그인',
    'en': 'Sign in with Google',
  },
  ProfileStringKeys.linkApple: {
    'ko': 'Apple로 로그인',
    'en': 'Sign in with Apple',
  },
  ProfileStringKeys.linkFailed: {
    'ko': '계정 연결에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    'en': 'Could not link your account. Please try again.',
  },
  ProfileStringKeys.linkSuccess: {
    'ko': '계정이 연결되었습니다. 데이터가 이 기기에 안전하게 저장됩니다.',
    'en': 'Account linked. Your rewards and orders are now tied to this sign-in.',
  },
};

/// KO/EN для блока привязки; остальные языки приложения → EN.
String profileTr(String key, String languageCode) {
  final normalized = languageCode == 'ko' ? 'ko' : 'en';
  return _profileKoEn[key]?[normalized] ??
      _profileKoEn[key]?['en'] ??
      key;
}
