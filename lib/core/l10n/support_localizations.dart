/// Ключи строк обратной связи.
abstract final class SupportStringKeys {
  static const feedbackButton = 'feedback_button';
  static const feedbackTitle = 'feedback_title';
  static const feedbackHint = 'feedback_hint';
  static const feedbackSend = 'feedback_send';
  static const feedbackSuccess = 'feedback_success';
  static const feedbackEmpty = 'feedback_empty';
}

const supportLocalizations = <String, Map<String, String>>{
  SupportStringKeys.feedbackButton: {
    'ru': 'Обратная связь',
    'kk': 'Кері байланыс',
    'ko': '문의하기 / 고객-центр',
    'en': 'Feedback',
    'uz': 'Kayta aloqa',
  },
  SupportStringKeys.feedbackTitle: {
    'ru': 'Обратная связь',
    'kk': 'Кері байланыс',
    'ko': '문의하기 / 고객-센터',
    'en': 'Feedback',
    'uz': 'Kayta aloqa',
  },
  SupportStringKeys.feedbackHint: {
    'ru':
        'Напишите благодарность, вопрос, жалобу или сообщите об ошибке — мы обязательно ответим…',
    'kk':
        'Алғыс, сұрақ, шағым немесе қате туралы жазыңыз — міндетті түрде жауап береміз…',
    'ko':
        '감사 인사, 문의, 불만 또는 오류를 남겨 주세요. 빠르게 답변드리겠습니다…',
    'en':
        'Share thanks, ask a question, leave a complaint, or report a bug — we will respond…',
    'uz':
        'Minnatdorchilik, savol, shikoyat yoki xato haqida yozing — albatta javob beramiz…',
  },
  SupportStringKeys.feedbackSend: {
    'ru': 'Отправить',
    'kk': 'Жіберу',
    'ko': '보내기',
    'en': 'Send',
    'uz': 'Yuborish',
  },
  SupportStringKeys.feedbackSuccess: {
    'ru': 'Спасибо! Ваше сообщение отправлено в службу поддержки.',
    'kk': 'Рақмет! Хабарламаңыз қолдау қызметіне жіберілді.',
    'ko': '감사합니다! 메시지가 고객센터로 전송되었습니다.',
    'en': 'Thank you! Your message was sent to our support team.',
    'uz': 'Rahmat! Xabaringiz qo\'llab-quvvatlash xizmatiga yuborildi.',
  },
  SupportStringKeys.feedbackEmpty: {
    'ru': 'Пожалуйста, введите текст сообщения.',
    'kk': 'Хабарлама мәтінін енгізіңіз.',
    'ko': '메시지를 입력해 주세요.',
    'en': 'Please enter your message.',
    'uz': 'Iltimos, xabar matnini kiriting.',
  },
};

String supportTr(String key, String languageCode) {
  return supportLocalizations[key]?[languageCode] ??
      supportLocalizations[key]?['en'] ??
      key;
}
