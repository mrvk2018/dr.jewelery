import '../utils/won_format.dart';

export '../utils/won_format.dart';

export 'app_language.dart';

/// Ключи строк экрана оформления заказа.
abstract final class CheckoutStringKeys {
  static const title = 'checkout_title';
  static const deliveryAddress = 'delivery_address';
  static const postalCode = 'postal_code';
  static const postalCodeHint = 'postal_code_hint';
  static const search = 'search';
  static const roadAddress = 'road_address';
  static const roadAddressHint = 'road_address_hint';
  static const detailAddress = 'detail_address';
  static const detailAddressHint = 'detail_address_hint';
  static const recipient = 'recipient';
  static const recipientName = 'recipient_name';
  static const recipientNameHint = 'recipient_name_hint';
  static const phone = 'phone';
  static const phoneHint = 'phone_hint';
  static const deliveryMethod = 'delivery_method';
  static const courierTitle = 'courier_title';
  static const courierSubtitle = 'courier_subtitle';
  static const pickupTitle = 'pickup_title';
  static const pickupSubtitle = 'pickup_subtitle';
  static const free = 'free';
  static const orderSummary = 'order_summary';
  static const productsTotal = 'products_total';
  static const deliveryFee = 'delivery_fee';
  static const placeOrder = 'place_order';
  static const errorPostalCode = 'error_postal_code';
  static const errorRoadAddress = 'error_road_address';
  static const errorDetailAddress = 'error_detail_address';
  static const errorRecipientName = 'error_recipient_name';
  static const errorPhone = 'error_phone';
  static const orderPlaced = 'order_placed';
}

const checkoutLocalizations = <String, Map<String, String>>{
  CheckoutStringKeys.title: {
    'ru': 'Оформление заказа',
    'kk': 'Тапсырысты рәсімдеу',
    'ko': '주문하기',
    'en': 'Checkout',
    'uz': 'Buyurtmani rasmiylashtirish',
  },
  CheckoutStringKeys.deliveryAddress: {
    'ru': 'Адрес доставки',
    'kk': 'Жеткізу мекенжайы',
    'ko': '배송 주소',
    'en': 'Delivery Address',
    'uz': 'Yetkazib berish manzili',
  },
  CheckoutStringKeys.postalCode: {
    'ru': 'Почтовый индекс',
    'kk': 'Пошта индексі',
    'ko': '우편번호',
    'en': 'Postal Code',
    'uz': 'Pochta indeksi',
  },
  CheckoutStringKeys.postalCodeHint: {
    'ru': '5 цифр',
    'kk': '5 цифр',
    'ko': '5자리',
    'en': '5 digits',
    'uz': '5 raqam',
  },
  CheckoutStringKeys.search: {
    'ru': 'Поиск',
    'kk': 'Іздеу',
    'ko': '검색',
    'en': 'Search',
    'uz': 'Qidirish',
  },
  CheckoutStringKeys.roadAddress: {
    'ru': 'Основной адрес',
    'kk': 'Негізгі мекенжай',
    'ko': '도로명주소',
    'en': 'Road Address',
    'uz': 'Asosiy manzil',
  },
  CheckoutStringKeys.roadAddressHint: {
    'ru': 'Заполняется автоматически',
    'kk': 'Автоматты түрде толтырылады',
    'ko': '자동으로 입력됩니다',
    'en': 'Filled automatically',
    'uz': 'Avtomatik to\'ldiriladi',
  },
  CheckoutStringKeys.detailAddress: {
    'ru': 'Детальный адрес',
    'kk': 'Толық мекенжай',
    'ko': '상세주소',
    'en': 'Detailed Address',
    'uz': 'Batafsil manzil',
  },
  CheckoutStringKeys.detailAddressHint: {
    'ru': '101동 502호',
    'kk': '101-ғимарат 502-пәтер',
    'ko': '101동 502호',
    'en': 'Apt 502, Bldg 101',
    'uz': '101-dom 502-xona',
  },
  CheckoutStringKeys.recipient: {
    'ru': 'Данные получателя',
    'kk': 'Алушы деректері',
    'ko': '수령인 정보',
    'en': 'Recipient Details',
    'uz': 'Qabul qiluvchi ma\'lumotlari',
  },
  CheckoutStringKeys.recipientName: {
    'ru': 'Имя (ФИО)',
    'kk': 'Аты-жөні',
    'ko': '이름',
    'en': 'Full Name',
    'uz': 'F.I.O.',
  },
  CheckoutStringKeys.recipientNameHint: {
    'ru': 'Kim Min-jun',
    'kk': 'Kim Min-jun',
    'ko': '김민준',
    'en': 'Kim Min-jun',
    'uz': 'Kim Min-jun',
  },
  CheckoutStringKeys.phone: {
    'ru': 'Номер телефона',
    'kk': 'Телефон нөмірі',
    'ko': '휴대폰 번호',
    'en': 'Phone Number',
    'uz': 'Telefon raqami',
  },
  CheckoutStringKeys.phoneHint: {
    'ru': '010-0000-0000',
    'kk': '010-0000-0000',
    'ko': '010-0000-0000',
    'en': '010-0000-0000',
    'uz': '010-0000-0000',
  },
  CheckoutStringKeys.deliveryMethod: {
    'ru': 'Способ доставки',
    'kk': 'Жеткізу тәсілі',
    'ko': '배송 방법',
    'en': 'Delivery Method',
    'uz': 'Yetkazib berish usuli',
  },
  CheckoutStringKeys.courierTitle: {
    'ru': 'Стандартная доставка',
    'kk': 'Стандартты жеткізу',
    'ko': '택배',
    'en': 'Standard Delivery',
    'uz': 'Standart yetkazib berish',
  },
  CheckoutStringKeys.courierSubtitle: {
    'ru': 'Курьерская служба · 1–3 рабочих дня',
    'kk': 'Курьерлік қызмет · 1–3 жұмыс күні',
    'ko': '택배 · 1–3 영업일',
    'en': 'Courier · 1–3 business days',
    'uz': 'Kuryer · 1–3 ish kuni',
  },
  CheckoutStringKeys.pickupTitle: {
    'ru': 'Самовывоз из магазина',
    'kk': 'Дүкеннен алу',
    'ko': '방문수령',
    'en': 'Store Pickup',
    'uz': 'Do\'kondan olib ketish',
  },
  CheckoutStringKeys.pickupSubtitle: {
    'ru': 'Сеул / Инчхон · Dr. Jewelry',
    'kk': 'Сеул / Инчхон · Dr. Jewelry',
    'ko': '서울 / 인천 · Dr. Jewelry',
    'en': 'Seoul / Incheon · Dr. Jewelry',
    'uz': 'Seul / Inchxon · Dr. Jewelry',
  },
  CheckoutStringKeys.free: {
    'ru': 'Бесплатно',
    'kk': 'Тегін',
    'ko': '무료',
    'en': 'Free',
    'uz': 'Bepul',
  },
  CheckoutStringKeys.orderSummary: {
    'ru': 'Итого',
    'kk': 'Жиыны',
    'ko': '합계',
    'en': 'Summary',
    'uz': 'Jami',
  },
  CheckoutStringKeys.productsTotal: {
    'ru': 'Товары',
    'kk': 'Тауарлар',
    'ko': '상품',
    'en': 'Products',
    'uz': 'Mahsulotlar',
  },
  CheckoutStringKeys.deliveryFee: {
    'ru': 'Доставка',
    'kk': 'Жеткізу',
    'ko': '배송비',
    'en': 'Delivery',
    'uz': 'Yetkazib berish',
  },
  CheckoutStringKeys.placeOrder: {
    'ru': 'Оформить заказ',
    'kk': 'Тапсырыс беру',
    'ko': '주문하기',
    'en': 'Place Order',
    'uz': 'Buyurtma berish',
  },
  CheckoutStringKeys.errorPostalCode: {
    'ru': 'Введите корректный почтовый индекс (5 цифр)',
    'kk': 'Дұрыс пошта индексін енгізіңіз (5 цифр)',
    'ko': '올바른 우편번호(5자리)를 입력해 주세요',
    'en': 'Enter a valid 5-digit postal code',
    'uz': 'To\'g\'ri pochta indeksini kiriting (5 raqam)',
  },
  CheckoutStringKeys.errorRoadAddress: {
    'ru': 'Укажите адрес улицы (кнопка «Поиск» или ввод)',
    'kk': 'Көше мекенжайын көрсетіңіз («Іздеу» батырması)',
    'ko': '도로명 주소를 입력해 주세요 (주소 검색)',
    'en': 'Enter road address (use address search)',
    'uz': 'Ko\'cha manzilini kiriting (qidiruv tugmasi)',
  },
  CheckoutStringKeys.errorDetailAddress: {
    'ru': 'Укажите детальный адрес (квартира, этаж)',
    'kk': 'Толық мекенжайды көрсетіңіз (пәтер, қабат)',
    'ko': '상세주소(동/호)를 입력해 주세요',
    'en': 'Enter detailed address (unit, floor)',
    'uz': 'Batafsil manzilni kiriting',
  },
  CheckoutStringKeys.errorRecipientName: {
    'ru': 'Укажите имя получателя',
    'kk': 'Алушының атын көрсетіңіз',
    'ko': '수령인 이름을 입력해 주세요',
    'en': 'Enter recipient name',
    'uz': 'Qabul qiluvchi ismini kiriting',
  },
  CheckoutStringKeys.errorPhone: {
    'ru': 'Введите номер в формате 010-XXXX-XXXX',
    'kk': 'Нөмірді 010-XXXX-XXXX форматында енгізіңіз',
    'ko': '010-XXXX-XXXX 형식으로 입력해 주세요',
    'en': 'Enter phone as 010-XXXX-XXXX',
    'uz': '010-XXXX-XXXX formatida kiriting',
  },
  CheckoutStringKeys.orderPlaced: {
    'ru': 'Заказ успешно оформлен!',
    'kk': 'Тапсырыс сәтті рәсімделді!',
    'ko': '주문이 완료되었습니다!',
    'en': 'Order placed successfully!',
    'uz': 'Buyurtma muvaffaqiyatli rasmiylashtirildi!',
  },
};

String checkoutTr(String key, String languageCode) {
  return checkoutLocalizations[key]?[languageCode] ??
      checkoutLocalizations[key]?['en'] ??
      key;
}

/// Форматирует сумму в южнокорейских вонах: `₩3,000`.
String formatKrw(int amount) => formatWon(amount);
