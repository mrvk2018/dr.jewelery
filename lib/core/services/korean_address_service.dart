/// Результат выбора адреса через Daum Postcode (WebView).
class KoreanAddressLookupResult {
  const KoreanAddressLookupResult({
    required this.postalCode,
    required this.roadAddress,
  });

  final String postalCode;
  final String roadAddress;
}
