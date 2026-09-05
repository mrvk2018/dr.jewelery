import 'package:flutter/material.dart';

import '../../../../core/l10n/payment_localizations.dart';

/// Тип способа оплаты на экране Payment.
enum PaymentMethodType {
  appCard,
  kakaoPay,
  tossPay,
  bankTransfer,
}

/// Статус оплаты заказа после оформления.
enum OrderPaymentStatus {
  paid,
  awaitingPayment,
}

/// Популярные банки Южной Кореи для App Card.
enum KoreanBank {
  kb(
    id: 'kb',
    labelKo: 'KB국민은행',
    labelEn: 'KB Kookmin Bank',
    shortCode: 'KB',
    brandColor: Color(0xFFFFBC00),
    loadingKey: PaymentStringKeys.loadingKb,
  ),
  shinhan(
    id: 'shinhan',
    labelKo: '신한은행',
    labelEn: 'Shinhan Bank',
    shortCode: 'SH',
    brandColor: Color(0xFF0046FF),
    loadingKey: PaymentStringKeys.loadingShinhan,
  ),
  woori(
    id: 'woori',
    labelKo: '우리은행',
    labelEn: 'Woori Bank',
    shortCode: 'WR',
    brandColor: Color(0xFF0083CA),
    loadingKey: PaymentStringKeys.loadingWoori,
  ),
  hana(
    id: 'hana',
    labelKo: '하나은행',
    labelEn: 'Hana Bank',
    shortCode: 'HN',
    brandColor: Color(0xFF009178),
    loadingKey: PaymentStringKeys.loadingHana,
  ),
  nh(
    id: 'nh',
    labelKo: 'NH농협은행',
    labelEn: 'NH Nonghyup Bank',
    shortCode: 'NH',
    brandColor: Color(0xFF005BAC),
    loadingKey: PaymentStringKeys.loadingNh,
  );

  const KoreanBank({
    required this.id,
    required this.labelKo,
    required this.labelEn,
    required this.shortCode,
    required this.brandColor,
    required this.loadingKey,
  });

  final String id;
  final String labelKo;
  final String labelEn;
  final String shortCode;
  final Color brandColor;
  final String loadingKey;

  String localizedLabel(String languageCode) =>
      languageCode == 'ko' ? labelKo : labelEn;
}
