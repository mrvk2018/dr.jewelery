import 'app_language.dart';

export 'app_language.dart';

/// Ключи строк экрана оплаты.
abstract final class PaymentStringKeys {
  static const title = 'payment_title';
  static const totalToPay = 'total_to_pay';
  static const selectMethod = 'select_method';
  static const appCard = 'app_card';
  static const appCardSubtitle = 'app_card_subtitle';
  static const kakaoPay = 'kakao_pay';
  static const tossPay = 'toss_pay';
  static const bankTransfer = 'bank_transfer';
  static const bankTransferSubtitle = 'bank_transfer_subtitle';
  static const bankDetailsTitle = 'bank_details_title';
  static const accountNumber = 'account_number';
  static const recipient = 'recipient';
  static const copy = 'copy';
  static const copied = 'copied';
  static const confirmPay = 'confirm_pay';
  static const selectBank = 'select_bank';
  static const loadingKb = 'loading_kb';
  static const loadingShinhan = 'loading_shinhan';
  static const loadingWoori = 'loading_woori';
  static const loadingHana = 'loading_hana';
  static const loadingNh = 'loading_nh';
  static const loadingKakao = 'loading_kakao';
  static const loadingToss = 'loading_toss';
  static const successTitle = 'success_title';
  static const successSubtitlePaid = 'success_subtitle_paid';
  static const successSubtitleAwaiting = 'success_subtitle_awaiting';
  static const backToHome = 'back_to_home';
  static const errorSelectMethod = 'error_select_method';
  static const errorSelectBank = 'error_select_bank';
  static const recipientName = 'recipient_name_value';
}

const paymentLocalizations = <String, Map<String, String>>{
  PaymentStringKeys.title: {
    'ru': 'Оплата',
    'kk': 'Төлем',
    'ko': '결제',
    'en': 'Payment',
    'uz': 'To\'lov',
  },
  PaymentStringKeys.totalToPay: {
    'ru': 'Итого к оплате',
    'kk': 'Төлем сомасы',
    'ko': '결제 금액',
    'en': 'Total to pay',
    'uz': 'To\'lov summasi',
  },
  PaymentStringKeys.selectMethod: {
    'ru': 'Способ оплаты',
    'kk': 'Төлем тәсілі',
    'ko': '결제 수단',
    'en': 'Payment method',
    'uz': 'To\'lov usuli',
  },
  PaymentStringKeys.appCard: {
    'ru': 'Быстрая оплата картой банка',
    'kk': 'Банк картасымен жылдам төлем',
    'ko': '앱카드',
    'en': 'App Card (Bank App)',
    'uz': 'Bank ilovasi orqali tez to\'lov',
  },
  PaymentStringKeys.appCardSubtitle: {
    'ru': 'App-to-App · KB, Shinhan, Woori, Hana, NH',
    'kk': 'App-to-App · KB, Shinhan, Woori, Hana, NH',
    'ko': '앱카드 · KB, 신한, 우리, 하나, NH',
    'en': 'App-to-App · KB, Shinhan, Woori, Hana, NH',
    'uz': 'App-to-App · KB, Shinhan, Woori, Hana, NH',
  },
  PaymentStringKeys.kakaoPay: {
    'ru': 'KakaoPay',
    'kk': 'KakaoPay',
    'ko': '카카오페이',
    'en': 'KakaoPay',
    'uz': 'KakaoPay',
  },
  PaymentStringKeys.tossPay: {
    'ru': 'TossPay',
    'kk': 'TossPay',
    'ko': '토스페이',
    'en': 'TossPay',
    'uz': 'TossPay',
  },
  PaymentStringKeys.bankTransfer: {
    'ru': 'Банковский перевод',
    'kk': 'Банк аударымы',
    'ko': '무통장입금',
    'en': 'Bank Transfer',
    'uz': 'Bank o\'tkazmasi',
  },
  PaymentStringKeys.bankTransferSubtitle: {
    'ru': 'Перевод на счёт Hana Bank',
    'kk': 'Hana Bank шотына аудару',
    'ko': '하나은행 계좌이체',
    'en': 'Transfer to Hana Bank account',
    'uz': 'Hana Bank hisobiga o\'tkazma',
  },
  PaymentStringKeys.bankDetailsTitle: {
    'ru': 'Реквизиты для перевода',
    'kk': 'Аударым деректемелері',
    'ko': '입금 계좌 정보',
    'en': 'Transfer details',
    'uz': 'O\'tkazma rekvizitlari',
  },
  PaymentStringKeys.accountNumber: {
    'ru': 'Номер счёта',
    'kk': 'Шот нөмірі',
    'ko': '계좌번호',
    'en': 'Account number',
    'uz': 'Hisob raqami',
  },
  PaymentStringKeys.recipient: {
    'ru': 'Получатель',
    'kk': 'Алушы',
    'ko': '예금주',
    'en': 'Recipient',
    'uz': 'Qabul qiluvchi',
  },
  PaymentStringKeys.recipientName: {
    'ru': 'Dr.Jewelry',
    'kk': 'Dr.Jewelry',
    'ko': 'Dr.Jewelry',
    'en': 'Dr.Jewelry',
    'uz': 'Dr.Jewelry',
  },
  PaymentStringKeys.copy: {
    'ru': 'Скопировать',
    'kk': 'Көшіру',
    'ko': '복사',
    'en': 'Copy',
    'uz': 'Nusxalash',
  },
  PaymentStringKeys.copied: {
    'ru': 'Реквизиты скопированы',
    'kk': 'Деректемелер көшірілді',
    'ko': '계좌 정보가 복사되었습니다',
    'en': 'Account details copied',
    'uz': 'Rekvizitlar nusxalandi',
  },
  PaymentStringKeys.confirmPay: {
    'ru': 'Подтвердить и оплатить',
    'kk': 'Растау және төлеу',
    'ko': '결제 확인',
    'en': 'Confirm & Pay',
    'uz': 'Tasdiqlash va to\'lash',
  },
  PaymentStringKeys.selectBank: {
    'ru': 'Выберите банк',
    'kk': 'Банкті таңдаңыз',
    'ko': '은행 선택',
    'en': 'Select a bank',
    'uz': 'Bankni tanlang',
  },
  PaymentStringKeys.loadingKb: {
    'ru': 'Переход в приложение банка KB Pay…',
    'kk': 'KB Pay қосымшасына өту…',
    'ko': 'KB Pay 앱으로 이동 중…',
    'en': 'Opening KB Pay app…',
    'uz': 'KB Pay ilovasiga o\'tish…',
  },
  PaymentStringKeys.loadingShinhan: {
    'ru': 'Открытие Shinhan SOL Pay…',
    'kk': 'Shinhan SOL Pay ашылуда…',
    'ko': '신한 SOL Pay 실행 중…',
    'en': 'Opening Shinhan SOL Pay…',
    'uz': 'Shinhan SOL Pay ochilmoqda…',
  },
  PaymentStringKeys.loadingWoori: {
    'ru': 'Открытие шлюза Woori Won Pay…',
    'kk': 'Woori Won Pay шлюзі ашылуда…',
    'ko': '우리 Won Pay 연결 중…',
    'en': 'Opening Woori Won Pay gateway…',
    'uz': 'Woori Won Pay ochilmoqda…',
  },
  PaymentStringKeys.loadingHana: {
    'ru': 'Переход в Hana 1Q Pay…',
    'kk': 'Hana 1Q Pay-ға өту…',
    'ko': '하나 1Q Pay로 이동 중…',
    'en': 'Opening Hana 1Q Pay…',
    'uz': 'Hana 1Q Pay ochilmoqda…',
  },
  PaymentStringKeys.loadingNh: {
    'ru': 'Открытие NH Pay…',
    'kk': 'NH Pay ашылуда…',
    'ko': 'NH Pay 실행 중…',
    'en': 'Opening NH Pay…',
    'uz': 'NH Pay ochilmoqda…',
  },
  PaymentStringKeys.loadingKakao: {
    'ru': 'Открытие KakaoPay…',
    'kk': 'KakaoPay ашылуда…',
    'ko': '카카오페이 실행 중…',
    'en': 'Opening KakaoPay…',
    'uz': 'KakaoPay ochilmoqda…',
  },
  PaymentStringKeys.loadingToss: {
    'ru': 'Открытие TossPay…',
    'kk': 'TossPay ашылуда…',
    'ko': '토스페이 실행 중…',
    'en': 'Opening TossPay…',
    'uz': 'TossPay ochilmoqda…',
  },
  PaymentStringKeys.successTitle: {
    'ru': 'Заказ успешно оформлен!',
    'kk': 'Тапсырыс сәтті рәсімделді!',
    'ko': '주문이 완료되었습니다!',
    'en': 'Order placed successfully!',
    'uz': 'Buyurtma muvaffaqiyatli rasmiylashtirildi!',
  },
  PaymentStringKeys.successSubtitlePaid: {
    'ru': 'Оплата прошла успешно. Мы уже готовим ваш заказ.',
    'kk': 'Төлем сәтті өтті. Тапсырысыңыз дайындалуда.',
    'ko': '결제가 완료되었습니다. 주문을 준비 중입니다.',
    'en': 'Payment successful. We are preparing your order.',
    'uz': 'To\'lov muvaffaqiyatli. Buyurtmangiz tayyorlanmoqda.',
  },
  PaymentStringKeys.successSubtitleAwaiting: {
    'ru': 'Ожидает оплаты. Переведите сумму на указанные реквизиты.',
    'kk': 'Төлем күтілуде. Көрсетілген деректемелерге аударыңыз.',
    'ko': '입금 대기 중입니다. 안내 계좌로 입금해 주세요.',
    'en': 'Awaiting payment. Please transfer to the account provided.',
    'uz': 'To\'lov kutilmoqda. Ko\'rsatilgan rekvizitlarga o\'tkazing.',
  },
  PaymentStringKeys.backToHome: {
    'ru': 'Вернуться на главную',
    'kk': 'Басты бетке оралу',
    'ko': '홈으로 돌아가기',
    'en': 'Back to Home',
    'uz': 'Bosh sahifaga qaytish',
  },
  PaymentStringKeys.errorSelectMethod: {
    'ru': 'Выберите способ оплаты',
    'kk': 'Төлем тәсілін таңдаңыз',
    'ko': '결제 수단을 선택해 주세요',
    'en': 'Select a payment method',
    'uz': 'To\'lov usulini tanlang',
  },
  PaymentStringKeys.errorSelectBank: {
    'ru': 'Выберите банк для App Card оплаты',
    'kk': 'App Card төлемі үшін банкті таңдаңыз',
    'ko': '앱카드 결제 은행을 선택해 주세요',
    'en': 'Select a bank for App Card payment',
    'uz': 'App Card uchun bankni tanlang',
  },
};

String paymentTr(String key, AppLanguage language) {
  return paymentLocalizations[key]?[language.code] ??
      paymentLocalizations[key]?['en'] ??
      key;
}

/// Номер счёта Hana Bank для безналичного перевода.
const hanaBankAccountNumber = '123-456789-01234';
