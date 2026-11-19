import 'dart:convert';

/// Парсит положительное число размера (скаляр или строка).
double? parsePositiveProductSize(Object? raw) {
  if (raw == null) return null;
  if (raw is num) {
    final value = raw.toDouble();
    return value > 0 ? value : null;
  }
  final text = raw.toString().trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value <= 0) return null;
  return value;
}

/// Сырой jsonb/list `available_sizes` → список элементов.
List<Object?> parseAvailableSizesFieldElements(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) return raw;
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) return decoded;
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

/// Первое положительное число в `available_sizes`.
double? firstPositiveSizeFromAvailableSizes(Object? raw) {
  for (final elem in parseAvailableSizesFieldElements(raw)) {
    final value = parsePositiveProductSize(elem);
    if (value != null) return value;
  }
  return null;
}

/// Размер для UI админки: `size_value`, иначе первый элемент `available_sizes`.
double productDisplaySizeFromRow(Map<String, dynamic> row) {
  final fromScalar = parsePositiveProductSize(row['size_value']);
  if (fromScalar != null) return fromScalar;
  return firstPositiveSizeFromAvailableSizes(row['available_sizes']) ?? 0.0;
}

/// Payload для Supabase: согласованная пара полей.
Map<String, dynamic> productSizeDbFieldsFromInput(double? sizeValue) {
  if (sizeValue != null && sizeValue > 0) {
    return {
      'size_value': sizeValue,
      'available_sizes': [sizeValue],
    };
  }
  return {
    'size_value': null,
    'available_sizes': const <double>[],
  };
}