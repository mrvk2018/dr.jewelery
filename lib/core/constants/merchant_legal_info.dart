/// 사업자등록증 · 결제 화면 법적 고지 (Toss Payments 심사).
///
/// 이 파일의 문자열은 **항상 한국어**로 UI에 표시합니다.
/// `.tr()`, `paymentTr`, ARB 등 앱 로케일을 사용하지 마세요.
abstract final class MerchantLegalInfo {
  static const legalTradeName = '닥터 유벨리르카 (Dr. Juvelirka)';
  static const brandName = 'Jewelry Sunlight';
  static const representative = 'PAK ANDREI';
  static const businessRegistrationNumber = '727-09-01295';
  static const address = '인천광역시 연수구 함박로 81, 101호(연수동)';
  static const supportPhone = '010-2337-7069';
  static const supportEmail = 'support@jewelrysunlight.com';

  static const businessInfoExpansionTitleKo = '사업자 정보 확인';

  static const businessInfoBodyKo =
      '• 상호: $legalTradeName\n'
      '• 브랜드명: $brandName\n'
      '• 대표자 성명: $representative\n'
      '• 사업자등록번호: $businessRegistrationNumber\n'
      '• 사업장 소재지: $address\n'
      '• 고객센터: $supportPhone / $supportEmail';

  static const refundPolicyExpansionTitleKo = '환불 및 교환 정책 안내';

  static const refundPolicyKo =
      '전자상거래법에 의거하여 상품 수령 후 7일 이내에 교환 및 반품 신청이 가능합니다. '
      '단, 고객 맞춤 제작 상품(사이즈 주문 제작 등) 및 상품 태그 제거, 착용 흔적이 있는 경우 '
      '교환/반품이 제한될 수 있습니다. 단순 변심으로 인한 반품의 경우 왕복 배송비는 구매자가 부담합니다.';

  static const paymentTermsCheckboxLabelKo =
      '[필수] 구매 조건 및 결제 진행 동의';
}
