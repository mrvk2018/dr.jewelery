/// Сообщения о недоступных товарах (KO / EN) для checkout.
abstract final class CheckoutUnavailableMessages {
  static String dialogBody(String languageCode) {
    return switch (languageCode) {
      'ko' =>
        '장바구니의 일부 상품은 더 이상 주문할 수 없습니다. 장바구니를 확인해 주세요.',
      'en' =>
        'Some items in your cart are no longer available for order. Please review your cart.',
      _ =>
        'Some items in your cart are no longer available for order. Please review your cart.',
    };
  }

  static String dialogTitle(String languageCode) {
    return switch (languageCode) {
      'ko' => '주문 불가',
      'en' => 'Items unavailable',
      _ => 'Items unavailable',
    };
  }

  static String snackBar(String languageCode) => dialogBody(languageCode);
}
