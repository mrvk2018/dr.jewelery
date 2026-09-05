/// Результат поиска корейского адреса по почтовому индексу.
class KoreanAddressLookupResult {
  const KoreanAddressLookupResult({
    required this.postalCode,
    required this.roadAddress,
  });

  final String postalCode;
  final String roadAddress;
}

/// Заглушка поиска адреса по индексу (Daum/Kakao Postcode API).
Future<KoreanAddressLookupResult> lookupAddressByPostalCode(
  String postalCode,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));

  if (postalCode == '22012') {
    return const KoreanAddressLookupResult(
      postalCode: '22012',
      roadAddress: '인천광역시 연수구 경원대로',
    );
  }

  return KoreanAddressLookupResult(
    postalCode: postalCode,
    roadAddress: '인천광역시 연수구 경원대로',
  );
}

/// Демо-заполнение для кнопки «Поиск».
Future<KoreanAddressLookupResult> lookupDemoAddress() =>
    lookupAddressByPostalCode('22012');
