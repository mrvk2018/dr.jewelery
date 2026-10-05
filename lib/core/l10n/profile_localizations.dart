/// Строки профиля (привязка аккаунта, удаление аккаунта).
abstract final class ProfileStringKeys {
  static const linkAccountMessage = 'profile_link_account_message';
  static const linkGoogle = 'profile_link_google';
  static const linkApple = 'profile_link_apple';
  static const linkFailed = 'profile_link_failed';
  static const linkSuccess = 'profile_link_success';
  static const deleteAccountButton = 'profile_delete_account_button';
  static const deleteAccountTitle = 'profile_delete_account_title';
  static const deleteAccountWarning = 'profile_delete_account_warning';
  static const deleteAccountCancel = 'profile_delete_account_cancel';
  static const deleteAccountConfirm = 'profile_delete_account_confirm';
  static const deleteAccountFailed = 'profile_delete_account_failed';
  static const deleteAccountSuccess = 'profile_delete_account_success';
}

const _profileStrings = <String, Map<String, String>>{
  ProfileStringKeys.linkAccountMessage: {
    'ru':
        'Войдите через Google или Apple, чтобы сохранить бонусы и заказы при '
        'смене телефона или переустановке приложения.',
    'kk':
        'Google немесе Apple арқылы кіріңіз — телефон ауыстырғанда немесе '
        'қосымшаны қайта орнатқанда бонустар мен тапсырыстар сақталады.',
    'ko':
        'Google 또는 Apple로 로그인하면 스마트폰을 바꾸거나 앱을 삭제해도 '
        '적립된 보너스와 주문 내역을 안전하게 유지할 수 있습니다.',
    'en':
        'Sign in with Google or Apple to keep your bonus balance and order '
        'history when you change phones or reinstall the app.',
    'uz':
        'Google yoki Apple orqali kiring — telefon almashtirganda yoki '
        'ilovani qayta o\'rnatganda bonuslar va buyurtmalar saqlanadi.',
  },
  ProfileStringKeys.linkGoogle: {
    'ru': 'Войти через Google',
    'kk': 'Google арқылы кіру',
    'ko': 'Google로 로그인',
    'en': 'Sign in with Google',
    'uz': 'Google orqali kirish',
  },
  ProfileStringKeys.linkApple: {
    'ru': 'Войти через Apple',
    'kk': 'Apple арқылы кіру',
    'ko': 'Apple로 로그인',
    'en': 'Sign in with Apple',
    'uz': 'Apple orqali kirish',
  },
  ProfileStringKeys.linkFailed: {
    'ru': 'Не удалось привязать аккаунт. Попробуйте позже.',
    'kk': 'Тіркелгіні байлау сәтсіз аяқталды. Кейінірек қайталаңыз.',
    'ko': '계정 연결에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    'en': 'Could not link your account. Please try again.',
    'uz': 'Hisobni bog\'lab bo\'lmadi. Keyinroq urinib ko\'ring.',
  },
  ProfileStringKeys.linkSuccess: {
    'ru': 'Аккаунт привязан. Данные сохранены для этого входа.',
    'kk': 'Тіркелгі байланды. Деректер осы кіру үшін сақталды.',
    'ko': '계정이 연결되었습니다. 데이터가 이 기기에 안전하게 저장됩니다.',
    'en': 'Account linked. Your rewards and orders are now tied to this sign-in.',
    'uz': 'Hisob bog\'landi. Ma\'lumotlar ushbu kirish uchun saqlandi.',
  },
  ProfileStringKeys.deleteAccountButton: {
    'ru': 'Удалить аккаунт',
    'kk': 'Тіркелгіні жою',
    'ko': '회원 탈퇴',
    'en': 'Delete Account',
    'uz': 'Hisobni o\'chirish',
  },
  ProfileStringKeys.deleteAccountTitle: {
    'ru': 'Удаление аккаунта',
    'kk': 'Тіркелгіні жою',
    'ko': '회원 탈퇴',
    'en': 'Delete account',
    'uz': 'Hisobni o\'chirish',
  },
  ProfileStringKeys.deleteAccountWarning: {
    'ko':
        '정말로 회원 탈퇴를 진행하시겠습니까? 탈퇴 완료 시 계정 정보는 영구 삭제되며 복구가 불가능합니다. 또한, 현재까지 적립된 모든 마일리지, 보유하신 쿠폰, 등급별 혜택 및 구매 내역이 전액 소멸되며 이에 대한 재복구는 지원되지 않습니다.',
    'ru':
        'Вы действительно хотите безвозвратно удалить свой аккаунт? Данное действие является необратимым. При удалении профиля все накопленные бонусы, персональные скидки, история заказов и статус в программе лояльности будут полностью аннулированы без возможности восстановления.',
    'en':
        'Are you sure you want to permanently delete your account? This action is irreversible. Upon account deletion, all accumulated bonuses, personal discounts, order history, and loyalty program rewards will be permanently forfeited and cannot be recovered.',
    'kk':
        'Тіркелгіңізді біржола жойғыңыз келетініне сенімдісіз бе? Бұл әрекетті кері қайтару мүмкін емес. Профильді жойған кезде барлық жиналған бонустар, жеке жеңілдіктер, тапсырыстар тарихы және адалдық бағдарламасындағы мәртебеңіз қалпына келтіру құқығысыз толықтай жойылады.',
    'uz':
        'Hisobingizni butunlay o\'chirmoqchimisiz? Ushbu amalni orqaga qaytarib bo\'lmaydi. Profil o\'chirilganda, barcha to\'plangan bonuslar, shaxsiy chegirmalar, buyurtmalar tarixi va sodiqlik dasturidagi maqomingiz qayta tiklash imkoniyatisiz to\'liq bekor qilinadi.',
  },
  ProfileStringKeys.deleteAccountCancel: {
    'ru': 'Отмена',
    'kk': 'Бас тарту',
    'ko': '취소',
    'en': 'Cancel',
    'uz': 'Bekor qilish',
  },
  ProfileStringKeys.deleteAccountConfirm: {
    'ru': 'Удалить',
    'kk': 'Жою',
    'ko': '탈퇴',
    'en': 'Delete',
    'uz': 'O\'chirish',
  },
  ProfileStringKeys.deleteAccountFailed: {
    'ru': 'Не удалось удалить аккаунт. Попробуйте позже или обратитесь в поддержку.',
    'kk': 'Тіркелгіні жою мүмкін болмады. Кейінірек қайталаңыз.',
    'ko': '회원 탈퇴에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    'en': 'Could not delete your account. Please try again or contact support.',
    'uz': 'Hisobni o\'chirib bo\'lmadi. Keyinroq urinib ko\'ring.',
  },
  ProfileStringKeys.deleteAccountSuccess: {
    'ru': 'Аккаунт удалён. Создана новая гостевая сессия.',
    'kk': 'Тіркелгі жойылды. Жаңа қонақ сессиясы ашылды.',
    'ko': '회원 탈퇴가 완료되었습니다.',
    'en': 'Your account was deleted. A new guest session was started.',
    'uz': 'Hisob o\'chirildi. Yangi mehmon sessiyasi boshlandi.',
  },
};

String profileTr(String key, String languageCode) {
  return _profileStrings[key]?[languageCode] ??
      _profileStrings[key]?['en'] ??
      key;
}
