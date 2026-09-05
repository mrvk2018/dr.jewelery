import 'app_language.dart';

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
  static const errorDetailAddress = 'error_detail_address';
  static const errorRecipientName = 'error_recipient_name';
  static const errorPhone = 'error_phone';
  static const orderPlaced = 'order_placed';
}

const checkoutLocalizations = <String, Map<String, String>>{
  CheckoutStringKeys.title: {
    'ru': 'Оформление заказа',
    'ko': '주문하기',
    'en': 'Checkout',
    'uz': 'Buyurtmani rasmiylashtirish',
  },
  CheckoutStringKeys.deliveryAddress: {
    'ru': 'Адрес доставки',
    'ko': '배송 주소',
    'en': 'Delivery Address',
    'uz': 'Yetkazib berish manzili',
  },
  CheckoutStringKeys.postalCode: {
    'ru': 'Почтовый индекс',
    'ko': '우편번호',
    'en': 'Postal Code',
    'uz': 'Pochta indeksi',
  },
  CheckoutStringKeys.postalCodeHint: {
    'ru': '5 цифр',
    'ko': '5자리',
    'en': '5 digits',
    'uz': '5 raqam',
  },
  CheckoutStringKeys.search: {
    'ru': 'Поиск',
    'ko': '검색',
    'en': 'Search',
    'uz': 'Qidirish',
  },
  CheckoutStringKeys.roadAddress: {
    'ru': 'Основной адрес',
    'ko': '도로명주소',
    'en': 'Road Address',
    'uz': 'Asosiy manzil',
  },
  CheckoutStringKeys.roadAddressHint: {
    'ru': 'Заполняется автоматически',
    'ko': '자동으로 입력됩니다',
    'en': 'Filled automatically',
    'uz': 'Avtomatik to\'ldiriladi',
  },
  CheckoutStringKeys.detailAddress: {
    'ru': 'Детальный адрес',
    'ko': '상세주소',
    'en': 'Detailed Address',
    'uz': 'Batafsil manzil',
  },
  CheckoutStringKeys.detailAddressHint: {
    'ru': '101동 502호',
    'ko': '101동 502호',
    'en': 'Apt 502, Bldg 101',
    'uz': '101-dom 502-xona',
  },
  CheckoutStringKeys.recipient: {
    'ru': 'Данные получателя',
    'ko': '수령인 정보',
    'en': 'Recipient Details',
    'uz': 'Qabul qiluvchi ma\'lumotlari',
  },
  CheckoutStringKeys.recipientName: {
    'ru': 'Имя (ФИО)',
    'ko': '이름',
    'en': 'Full Name',
    'uz': 'F.I.O.',
  },
  CheckoutStringKeys.recipientNameHint: {
    'ru': 'Kim Min-jun',
    'ko': '김민준',
    'en': 'Kim Min-jun',
    'uz': 'Kim Min-jun',
  },
  CheckoutStringKeys.phone: {
    'ru': 'Номер телефона',
    'ko': '휴대폰 번호',
    'en': 'Phone Number',
    'uz': 'Telefon raqami',
  },
  CheckoutStringKeys.phoneHint: {
    'ru': '010-0000-0000',
    'ko': '010-0000-0000',
    'en': '010-0000-0000',
    'uz': '010-0000-0000',
  },
  CheckoutStringKeys.deliveryMethod: {
    'ru': 'Способ доставки',
    'ko': '배송 방법',
    'en': 'Delivery Method',
    'uz': 'Yetkazib berish usuli',
  },
  CheckoutStringKeys.courierTitle: {
    'ru': 'Стандартная доставка',
    'ko': '택배',
    'en': 'Standard Delivery',
    'uz': 'Standart yetkazib berish',
  },
  CheckoutStringKeys.courierSubtitle: {
    'ru': 'Курьерская служба · 1–3 рабочих дня',
    'ko': '택배 · 1–3 영업일',
    'en': 'Courier · 1–3 business days',
    'uz': 'Kuryer · 1–3 ish kuni',
  },
  CheckoutStringKeys.pickupTitle: {
    'ru': 'Самовывоз из магазина',
    'ko': '방문수령',
    'en': 'Store Pickup',
    'uz': 'Do\'kondan olib ketish',
  },
  CheckoutStringKeys.pickupSubtitle: {
    'ru': 'Сеул / Инчхон · Sunlight Jewelry',
    'ko': '서울 / 인천 · Sunlight Jewelry',
    'en': 'Seoul / Incheon · Sunlight Jewelry',
    'uz': 'Seul / Inchxon · Sunlight Jewelry',
  },
  CheckoutStringKeys.free: {
    'ru': 'Бесплатно',
    'ko': '무료',
    'en': 'Free',
    'uz': 'Bepul',
  },
  CheckoutStringKeys.orderSummary: {
    'ru': 'Итого',
    'ko': '합계',
    'en': 'Summary',
    'uz': 'Jami',
  },
  CheckoutStringKeys.productsTotal: {
    'ru': 'Товары',
    'ko': '상품',
    'en': 'Products',
    'uz': 'Mahsulotlar',
  },
  CheckoutStringKeys.deliveryFee: {
    'ru': 'Доставка',
    'ko': '배송비',
    'en': 'Delivery',
    'uz': 'Yetkazib berish',
  },
  CheckoutStringKeys.placeOrder: {
    'ru': 'Оформить заказ',
    'ko': '주문하기',
    'en': 'Place Order',
    'uz': 'Buyurtma berish',
  },
  CheckoutStringKeys.errorPostalCode: {
    'ru': 'Введите корректный почтовый индекс (5 цифр)',
    'ko': '올바른 우편번호(5자리)를 입력해 주세요',
    'en': 'Enter a valid 5-digit postal code',
    'uz': 'To\'g\'ri pochta indeksini kiriting (5 raqam)',
  },
  CheckoutStringKeys.errorDetailAddress: {
    'ru': 'Укажите детальный адрес (квартира, этаж)',
    'ko': '상세주소(동/호)를 입력해 주세요',
    'en': 'Enter detailed address (unit, floor)',
    'uz': 'Batafsil manzilni kiriting',
  },
  CheckoutStringKeys.errorRecipientName: {
    'ru': 'Укажите имя получателя',
    'ko': '수령인 이름을 입력해 주세요',
    'en': 'Enter recipient name',
    'uz': 'Qabul qiluvchi ismini kiriting',
  },
  CheckoutStringKeys.errorPhone: {
    'ru': 'Введите номер в формате 010-XXXX-XXXX',
    'ko': '010-XXXX-XXXX 형식으로 입력해 주세요',
    'en': 'Enter phone as 010-XXXX-XXXX',
    'uz': '010-XXXX-XXXX formatida kiriting',
  },
  CheckoutStringKeys.orderPlaced: {
    'ru': 'Заказ успешно оформлен!',
    'ko': '주문이 완료되었습니다!',
    'en': 'Order placed successfully!',
    'uz': 'Buyurtma muvaffaqiyatli rasmiylashtirildi!',
  },
};

String checkoutTr(String key, AppLanguage language) {
  return checkoutLocalizations[key]?[language.code] ??
      checkoutLocalizations[key]?['en'] ??
      key;
}

/// Форматирует сумму в южнокорейских вонах: 3 000 ₩.
String formatKrw(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }

  return '${buffer.toString()} ₩';
}
