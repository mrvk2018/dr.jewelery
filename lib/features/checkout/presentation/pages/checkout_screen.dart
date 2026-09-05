import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../payment/presentation/pages/payment_screen.dart';
import '../../../../core/l10n/checkout_localizations.dart';
import '../../../../core/services/korean_address_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/korean_phone_formatter.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../domain/models/delivery_method.dart';

/// Экран оформления заказа с корейской логистикой (PIPA / Daum Postcode).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.productsTotal,
  });

  final int productsTotal;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _roadAddressController = TextEditingController();
  final TextEditingController _detailAddressController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  DeliveryMethod _deliveryMethod = DeliveryMethod.courier;
  bool _isSearchingAddress = false;
  String? _validationMessage;

  AppLanguage get _language => LocaleScope.of(context).language;

  String tr(String key) => checkoutTr(key, _language);

  int get _deliveryFee => _deliveryMethod.feeKrw;

  @override
  void dispose() {
    _postalCodeController.dispose();
    _roadAddressController.dispose();
    _detailAddressController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _searchAddress() async {
    setState(() {
      _isSearchingAddress = true;
      _validationMessage = null;
    });

    try {
      final result = await lookupDemoAddress();
      if (!mounted) return;
      setState(() {
        _postalCodeController.text = result.postalCode;
        _roadAddressController.text = result.roadAddress;
      });
    } finally {
      if (mounted) setState(() => _isSearchingAddress = false);
    }
  }

  String? _validateForm() {
    final postalCode = _postalCodeController.text.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(postalCode)) {
      return tr(CheckoutStringKeys.errorPostalCode);
    }
    if (_detailAddressController.text.trim().isEmpty) {
      return tr(CheckoutStringKeys.errorDetailAddress);
    }
    if (_nameController.text.trim().isEmpty) {
      return tr(CheckoutStringKeys.errorRecipientName);
    }
    if (!KoreanPhoneInputFormatter.isValid(_phoneController.text)) {
      return tr(CheckoutStringKeys.errorPhone);
    }
    return null;
  }

  void _placeOrder() {
    final error = _validateForm();
    if (error != null) {
      setState(() => _validationMessage = error);
      return;
    }

    setState(() => _validationMessage = null);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaymentScreen(
          productsTotalRub: widget.productsTotal,
          deliveryFeeKrw: _deliveryFee,
        ),
      ),
    );
  }

  String get _orderButtonLabel {
    final base = tr(CheckoutStringKeys.placeOrder);
    final totalRub = formatRubPrice(widget.productsTotal);
    if (_deliveryFee > 0) {
      return '$base · $totalRub + ${formatKrw(_deliveryFee)}';
    }
    return '$base · $totalRub';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          tr(CheckoutStringKeys.title),
          style: AppTypography.heading(fontSize: 22),
        ),
      ),
      bottomNavigationBar: _CheckoutBottomBar(
        validationMessage: _validationMessage,
        buttonLabel: _orderButtonLabel,
        onPlaceOrder: _placeOrder,
        bottomInset: bottomInset,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CheckoutSection(
              title: tr(CheckoutStringKeys.deliveryAddress),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(CheckoutStringKeys.postalCode),
                    style: AppTypography.caption(fontWeight: FontWeight.w600)
                        .copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CheckoutTextField(
                          controller: _postalCodeController,
                          hint: tr(CheckoutStringKeys.postalCodeHint),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          onChanged: (_) {
                            if (_validationMessage != null) {
                              setState(() => _validationMessage = null);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _isSearchingAddress ? null : _searchAddress,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.textOnAccent,
                            disabledBackgroundColor:
                                AppColors.accent.withValues(alpha: 0.5),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSearchingAddress
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textOnAccent,
                                  ),
                                )
                              : Text(
                                  tr(CheckoutStringKeys.search),
                                  style: AppTypography.caption(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textOnAccent,
                                  ).copyWith(fontSize: 14),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _CheckoutLabeledField(
                    label: tr(CheckoutStringKeys.roadAddress),
                    child: _CheckoutTextField(
                      controller: _roadAddressController,
                      hint: tr(CheckoutStringKeys.roadAddressHint),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CheckoutLabeledField(
                    label: tr(CheckoutStringKeys.detailAddress),
                    child: _CheckoutTextField(
                      controller: _detailAddressController,
                      hint: tr(CheckoutStringKeys.detailAddressHint),
                      onChanged: (_) {
                        if (_validationMessage != null) {
                          setState(() => _validationMessage = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CheckoutSection(
              title: tr(CheckoutStringKeys.recipient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CheckoutLabeledField(
                    label: tr(CheckoutStringKeys.recipientName),
                    child: _CheckoutTextField(
                      controller: _nameController,
                      hint: tr(CheckoutStringKeys.recipientNameHint),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) {
                        if (_validationMessage != null) {
                          setState(() => _validationMessage = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CheckoutLabeledField(
                    label: tr(CheckoutStringKeys.phone),
                    child: _CheckoutTextField(
                      controller: _phoneController,
                      hint: tr(CheckoutStringKeys.phoneHint),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [KoreanPhoneInputFormatter()],
                      onChanged: (_) {
                        if (_validationMessage != null) {
                          setState(() => _validationMessage = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CheckoutSection(
              title: tr(CheckoutStringKeys.deliveryMethod),
              child: Column(
                children: [
                  _DeliveryOptionTile(
                    title: tr(CheckoutStringKeys.courierTitle),
                    subtitle: tr(CheckoutStringKeys.courierSubtitle),
                    priceLabel: formatKrw(DeliveryMethod.courier.feeKrw),
                    isSelected: _deliveryMethod == DeliveryMethod.courier,
                    onTap: () => setState(
                      () => _deliveryMethod = DeliveryMethod.courier,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DeliveryOptionTile(
                    title: tr(CheckoutStringKeys.pickupTitle),
                    subtitle: tr(CheckoutStringKeys.pickupSubtitle),
                    priceLabel: tr(CheckoutStringKeys.free),
                    isSelected: _deliveryMethod == DeliveryMethod.pickup,
                    onTap: () => setState(
                      () => _deliveryMethod = DeliveryMethod.pickup,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CheckoutSection(
              title: tr(CheckoutStringKeys.orderSummary),
              child: Column(
                children: [
                  _SummaryRow(
                    label: tr(CheckoutStringKeys.productsTotal),
                    value: formatRubPrice(widget.productsTotal),
                  ),
                  const SizedBox(height: 8),
                  _SummaryRow(
                    label: tr(CheckoutStringKeys.deliveryFee),
                    value: _deliveryMethod.isFree
                        ? tr(CheckoutStringKeys.free)
                        : formatKrw(_deliveryFee),
                    valueColor: _deliveryMethod.isFree
                        ? AppColors.accent
                        : AppColors.textPrimary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class _CheckoutSection extends StatelessWidget {
  const _CheckoutSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.heading(fontSize: 18)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _CheckoutLabeledField extends StatelessWidget {
  const _CheckoutLabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTypography.caption(fontWeight: FontWeight.w600)
              .copyWith(fontSize: 13),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _CheckoutTextField extends StatelessWidget {
  const _CheckoutTextField({
    required this.controller,
    required this.hint,
    this.readOnly = false,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool readOnly;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: AppTypography.productMeta().copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.productMeta().copyWith(
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
        filled: true,
        fillColor: readOnly
            ? AppColors.cardBackground
            : AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class _DeliveryOptionTile extends StatelessWidget {
  const _DeliveryOptionTile({
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String priceLabel;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppColors.accent.withValues(alpha: 0.08)
          : AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.caption(fontWeight: FontWeight.w700)
                          .copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.productMeta().copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                priceLabel,
                style: AppTypography.price(
                  fontSize: 14,
                  color: isSelected ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.productMeta().copyWith(fontSize: 14),
        ),
        Text(
          value,
          style: AppTypography.price(
            fontSize: 14,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _CheckoutBottomBar extends StatelessWidget {
  const _CheckoutBottomBar({
    required this.validationMessage,
    required this.buttonLabel,
    required this.onPlaceOrder,
    required this.bottomInset,
  });

  final String? validationMessage;
  final String buttonLabel;
  final VoidCallback onPlaceOrder;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (validationMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.saleRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.saleRed.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.saleRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validationMessage!,
                        style: AppTypography.caption(
                          color: AppColors.saleRed,
                          fontWeight: FontWeight.w500,
                        ).copyWith(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.bannerDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: onPlaceOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppColors.accent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ).copyWith(fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
