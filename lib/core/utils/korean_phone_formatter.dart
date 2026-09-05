import 'package:flutter/services.dart';

/// Маска корейского номера: 010-XXXX-XXXX (11 цифр).
class KoreanPhoneInputFormatter extends TextInputFormatter {
  static final RegExp _digitsOnly = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_digitsOnly, '');
    final limited =
        digits.length > 11 ? digits.substring(0, 11) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 3 || i == 7) {
        buffer.write('-');
      }
      buffer.write(limited[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static bool isValid(String value) {
    final digits = value.replaceAll(_digitsOnly, '');
    return digits.length == 11 && digits.startsWith('010');
  }

  static String digitsOnly(String value) =>
      value.replaceAll(_digitsOnly, '');
}
