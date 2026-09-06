export 'app_language.dart';

/// Ключи строк онбординга.
abstract final class OnboardingStringKeys {
  static const chooseLanguageTitle = 'choose_language_title';
  static const stepLanguage = 'step_language';
  static const stepCompliance = 'step_compliance';
  static const stepAuth = 'step_auth';
  static const complianceTitle = 'compliance_title';
  static const eulaTitle = 'eula_title';
  static const privacyTitle = 'privacy_title';
  static const permissionsTitle = 'permissions_title';
  static const permissionNotifications = 'permission_notifications';
  static const permissionCamera = 'permission_camera';
  static const permissionDeviceId = 'permission_device_id';
  static const eulaBody = 'eula_body';
  static const privacyBody = 'privacy_body';
  static const agreeCheckbox = 'agree_checkbox';
  static const continueButton = 'continue_button';
  static const authTitle = 'auth_title';
  static const authSubtitle = 'auth_subtitle';
  static const signInGoogle = 'sign_in_google';
  static const signInApple = 'sign_in_apple';
  static const skipGuest = 'skip_guest';
  static const pipaNotice = 'pipa_notice';
  static const viewDocument = 'view_document';
}

/// Локализованные строки онбординга (5 языков).
const onboardingLocalizations = <String, Map<String, String>>{
  OnboardingStringKeys.chooseLanguageTitle: {
    'ru': 'Выберите язык / Choose Language',
    'kk': 'Тілді таңдаңыз / Choose Language',
    'ko': '언어 선택 / Choose Language',
    'en': 'Choose Language / Select Language',
    'uz': 'Tilni tanlang / Choose Language',
  },
  OnboardingStringKeys.stepLanguage: {
    'ru': 'Язык',
    'kk': 'Тіл',
    'ko': '언어',
    'en': 'Language',
    'uz': 'Til',
  },
  OnboardingStringKeys.stepCompliance: {
    'ru': 'Соглашения',
    'kk': 'Келісімдер',
    'ko': '약관',
    'en': 'Agreements',
    'uz': 'Kelishuvlar',
  },
  OnboardingStringKeys.stepAuth: {
    'ru': 'Вход',
    'kk': 'Кіру',
    'ko': '로그인',
    'en': 'Sign in',
    'uz': 'Kirish',
  },
  OnboardingStringKeys.complianceTitle: {
    'ru': 'Согласие с условиями',
    'kk': 'Шарттарға келісім',
    'ko': '약관 동의',
    'en': 'Terms Agreement',
    'uz': 'Shartlarga rozilik',
  },
  OnboardingStringKeys.eulaTitle: {
    'ru': 'Пользовательское соглашение (EULA)',
    'kk': 'Пайдаланушы келісімі (EULA)',
    'ko': '이용약관 (EULA)',
    'en': 'End User License Agreement (EULA)',
    'uz': 'Foydalanuvchi shartnomasi (EULA)',
  },
  OnboardingStringKeys.privacyTitle: {
    'ru': 'Политика конфиденциальности (PIPA)',
    'kk': 'Құпиялылық саясаты (PIPA)',
    'ko': '개인정보 처리방침 (PIPA)',
    'en': 'Privacy Policy (PIPA)',
    'uz': 'Maxfiylik siyosati (PIPA)',
  },
  OnboardingStringKeys.permissionsTitle: {
    'ru': 'Запрос разрешений',
    'kk': 'Рұқсат сұраулары',
    'ko': '권한 요청',
    'en': 'Permission Requests',
    'uz': 'Ruxsat so\'rovlari',
  },
  OnboardingStringKeys.permissionNotifications: {
    'ru': 'Доступ к уведомлениям — для push-уведомлений о заказах и акциях',
    'kk': 'Хабарландыруларға қолжеткізу — тапсырыс пен акция push-хабарлары үшін',
    'ko': '알림 접근 — 주문 및 프로모션 푸시 알림',
    'en': 'Notifications — order updates and promotional push alerts',
    'uz': 'Bildirishnomalar — buyurtma va aksiya push-xabarlari',
  },
  OnboardingStringKeys.permissionCamera: {
    'ru': 'Доступ к камере — для биометрии админа и фото товаров',
    'kk': 'Камераға қолжеткізу — әкімші биометриясы және тауар фотолары үшін',
    'ko': '카메라 접근 — 관리자 생체인증 및 상품 사진',
    'en': 'Camera — admin biometrics and product photos',
    'uz': 'Kamera — admin biometriya va mahsulot suratlari',
  },
  OnboardingStringKeys.permissionDeviceId: {
    'ru': 'Идентификатор устройства — для безопасности сессии и аналитики',
    'kk': 'Құрылғы идентификаторы — сессия қауіпсіздігі мен аналитика үшін',
    'ko': '기기 ID — 세션 보안 및 서비스 분석',
    'en': 'Device ID — session security and service analytics',
    'uz': 'Qurilma ID — sessiya xavfsizligi va tahlil',
  },
  OnboardingStringKeys.eulaBody: {
    'ru':
        'Настоящее Пользовательское соглашение регулирует использование мобильного приложения Dr. Jewelry. Используя приложение, вы подтверждаете согласие с правилами сервиса, условиями покупки ювелирных изделий, политикой возврата и обслуживания клиентов.',
    'kk':
        'Осы Пайдаланушы келісімі Dr. Jewelry мобильді қосымшасын пайдалануды реттейді. Қосымшаны пайдалану арқылы сіз сервис ережелеріне, зергерлік бұйымдарды сатып алу шарттарына, қайтару және клиенттерге қызмет көрсету саясатына келісесіз.',
    'ko':
        '본 이용약관은 Dr. Jewelry 모바일 애플리케이션 이용을 규정합니다. 앱을 사용함으로써 귀하는 서비스 이용 규칙, 주얼리 구매 조건, 반품 및 고객 지원 정책에 동의하게 됩니다.',
    'en':
        'This EULA governs the use of the Dr. Jewelry mobile application. By using the app, you agree to service rules, jewelry purchase terms, return policy, and customer support standards.',
    'uz':
        'Ushbu foydalanuvchi shartnomasi Dr. Jewelry mobil ilovasidan foydalanishni tartibga soladi. Ilovadan foydalanish orqali siz xizmat qoidalari, zargarlik buyumlarini sotib olish shartlari va qaytarish siyosatiga rozilik bildirasiz.',
  },
  OnboardingStringKeys.privacyBody: {
    'ru':
        'В соответствии с Законом о защите персональных данных Республики Корея (PIPA) мы обрабатываем: имя, email, историю заказов, бонусный баланс, идентификатор устройства (Device ID), данные push-уведомлений и доступ к камере (по запросу). Данные хранятся на защищённых серверах, передаются только платёжным и логистическим партнёрам и могут быть удалены по запросу пользователя.',
    'kk':
        'Корея Республикасының жеке деректерді қорғау заңына (PIPA) сәйкес біз өңдейміз: аты, email, тапсырыстар тарихы, бонус балансы, құрылғы идентификаторы (Device ID), push-хабарлар және камераға қолжеткізу (сұраныс бойынша). Деректер қорғалған серверлерде сақталады, тек төлем және логистика серіктестеріне беріледі және пайдаланушы сұрауы бойынша жойылуы мүмкін.',
    'ko':
        '대한민국 개인정보 보호법(PIPA)에 따라 당사는 이름, 이메일, 주문 내역, 보너스 잔액, 기기 ID, 푸시 알림 및 카메라 접근(요청 시) 정보를 처리합니다. 데이터는 보호된 서버에 저장되며, 결제·물류 파트너에게만 전달되고 이용자 요청 시 삭제됩니다.',
    'en':
        'Under the Republic of Korea Personal Information Protection Act (PIPA), we process name, email, order history, bonus balance, device ID, push notification data, and camera access (on request). Data is stored on secure servers, shared only with payment and logistics partners, and deleted upon user request.',
    'uz':
        'Koreya Respublikasi shaxsiy ma\'lumotlarni himoya qilish qonuni (PIPA) asosida biz ism, email, buyurtmalar tarixi, bonus balansi, qurilma ID, push-bildirishnomalar va kamera ruxsatini qayta ishlaymiz. Ma\'lumotlar himoyalangan serverlarda saqlanadi va foydalanuvchi so\'rovi bo\'yicha o\'chiriladi.',
  },
  OnboardingStringKeys.agreeCheckbox: {
    'ru': 'Я согласен с Пользовательским соглашением и Политикой защиты персональных данных (PIPA)',
    'kk': 'Мен Пайдаланушы келісімі мен жеке деректерді қорғау саясатына (PIPA) келісемін',
    'ko': '이용약관 및 개인정보 처리방침에 동의합니다',
    'en': 'I agree to the Terms of Use and Privacy Policy (PIPA)',
    'uz': 'Foydalanish shartlari va maxfiylik siyosatiga (PIPA) roziman',
  },
  OnboardingStringKeys.continueButton: {
    'ru': 'Продолжить',
    'kk': 'Жалғастыру',
    'ko': '계속',
    'en': 'Continue',
    'uz': 'Davom etish',
  },
  OnboardingStringKeys.authTitle: {
    'ru': 'Войдите в аккаунт',
    'kk': 'Аккаунтқа кіріңіз',
    'ko': '계정 로그인',
    'en': 'Sign in to your account',
    'uz': 'Hisobingizga kiring',
  },
  OnboardingStringKeys.authSubtitle: {
    'ru': 'Копите бонусы, оформляйте заказы или продолжите как гость',
    'kk': 'Бонус жинаңыз, тапсырыс рәсімдеңіз немесе қонақ ретінде жалғастырыңыз',
    'ko': '보너스 적립, 주문 또는 게스트로 계속',
    'en': 'Earn bonuses, place orders, or continue as guest',
    'uz': 'Bonus to\'plang, buyurtma bering yoki mehmon sifatida davom eting',
  },
  OnboardingStringKeys.signInGoogle: {
    'ru': 'Войти через Google',
    'kk': 'Google арқылы кіру',
    'ko': 'Google로 로그인',
    'en': 'Sign in with Google',
    'uz': 'Google orqali kirish',
  },
  OnboardingStringKeys.signInApple: {
    'ru': 'Войти через Apple',
    'kk': 'Apple арқылы кіру',
    'ko': 'Apple로 로그인',
    'en': 'Sign in with Apple',
    'uz': 'Apple orqali kirish',
  },
  OnboardingStringKeys.skipGuest: {
    'ru': 'Продолжить как гость',
    'kk': 'Қонақ ретінде жалғастыру',
    'ko': '게스트로 계속',
    'en': 'Continue as guest',
    'uz': 'Mehmon sifatida davom etish',
  },
  OnboardingStringKeys.pipaNotice: {
    'ru': 'Соответствие PIPA · Республика Корея',
    'kk': 'PIPA сәйкестігі · Корея Республикасы',
    'ko': 'PIPA 준수 · 대한민국',
    'en': 'PIPA Compliance · Republic of Korea',
    'uz': 'PIPA muvofiqlik · Koreya Respublikasi',
  },
  OnboardingStringKeys.viewDocument: {
    'ru': 'Просмотреть документ',
    'kk': 'Құжатты қарау',
    'ko': '문서 보기',
    'en': 'View document',
    'uz': 'Hujjatni ko\'rish',
  },
};

/// Возвращает локализованную строку онбординга.
String onboardingTr(String key, String languageCode) {
  return onboardingLocalizations[key]?[languageCode] ??
      onboardingLocalizations[key]?['en'] ??
      key;
}
