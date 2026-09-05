import 'app_language.dart';

/// Плашка отсутствия товара (витрина, карточка, деталка).
String outOfStockLabel(AppLanguage language) {
  return switch (language) {
    AppLanguage.ru => 'Нет в наличии',
    AppLanguage.kk => 'Қолда жоқ',
    AppLanguage.ko => '품절',
    AppLanguage.en => 'Out of stock',
    AppLanguage.uz => 'Mavjud emas',
  };
}

String outOfStockLabelForCode(String languageCode) {
  return outOfStockLabel(AppLanguage.fromCode(languageCode));
}
