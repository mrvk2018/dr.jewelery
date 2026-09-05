import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/checkout_localizations.dart';
import '../../../../core/l10n/payment_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../domain/models/payment_models.dart';
import '../widgets/payment_loading_overlay.dart';
import 'payment_success_screen.dart';

/// Экран оплаты с корейскими способами (App Card, KakaoPay, TossPay, перевод).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.productsTotalKrw,
    required this.deliveryFeeKrw,
  });

  final int productsTotalKrw;
  final int deliveryFeeKrw;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PaymentMethodType? _selectedMethod;
  KoreanBank? _selectedBank;
  String? _validationMessage;

  AppLanguage get _language => LocaleScope.of(context).language;

  String tr(String key) => paymentTr(key, _language);

  String get _totalLabel {
    final products = formatWon(widget.productsTotalKrw);
    if (widget.deliveryFeeKrw > 0) {
      return '${tr(PaymentStringKeys.totalToPay)}: $products + ${formatWon(widget.deliveryFeeKrw)}';
    }
    return '${tr(PaymentStringKeys.totalToPay)}: $products';
  }

  void _selectMethod(PaymentMethodType method) {
    setState(() {
      _selectedMethod = method;
      _validationMessage = null;
      if (method != PaymentMethodType.appCard) {
        _selectedBank = null;
      }
    });
  }

  void _selectBank(KoreanBank bank) {
    setState(() {
      _selectedMethod = PaymentMethodType.appCard;
      _selectedBank = bank;
      _validationMessage = null;
    });
  }

  String? _validateSelection() {
    if (_selectedMethod == null) {
      return tr(PaymentStringKeys.errorSelectMethod);
    }
    if (_selectedMethod == PaymentMethodType.appCard && _selectedBank == null) {
      return tr(PaymentStringKeys.errorSelectBank);
    }
    return null;
  }

  Future<void> _confirmPayment() async {
    final error = _validateSelection();
    if (error != null) {
      setState(() => _validationMessage = error);
      return;
    }

    setState(() => _validationMessage = null);

    if (_selectedMethod == PaymentMethodType.bankTransfer) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PaymentSuccessScreen(
            status: OrderPaymentStatus.awaitingPayment,
          ),
        ),
      );
      return;
    }

    final loadingMessage = switch (_selectedMethod!) {
      PaymentMethodType.appCard => tr(_selectedBank!.loadingKey),
      PaymentMethodType.kakaoPay => tr(PaymentStringKeys.loadingKakao),
      PaymentMethodType.tossPay => tr(PaymentStringKeys.loadingToss),
      PaymentMethodType.bankTransfer => '',
    };

    PaymentLoadingOverlay.show(context, message: loadingMessage);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.of(context).pop();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const PaymentSuccessScreen(
          status: OrderPaymentStatus.paid,
        ),
      ),
    );
  }

  void _copyBankDetails() {
    final details =
        '${tr(PaymentStringKeys.accountNumber)}: $hanaBankAccountNumber\n'
        '${tr(PaymentStringKeys.recipient)}: ${tr(PaymentStringKeys.recipientName)}';
    Clipboard.setData(ClipboardData(text: details));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(PaymentStringKeys.copied)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          tr(PaymentStringKeys.title),
          style: AppTypography.heading(fontSize: 22),
        ),
      ),
      bottomNavigationBar: _PaymentBottomBar(
        validationMessage: _validationMessage,
        onConfirm: _confirmPayment,
        bottomInset: bottomInset,
        label: tr(PaymentStringKeys.confirmPay),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.bannerDark],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                _totalLabel,
                textAlign: TextAlign.center,
                style: AppTypography.heading(
                  fontSize: 20,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr(PaymentStringKeys.selectMethod),
              style: AppTypography.heading(fontSize: 18),
            ),
            const SizedBox(height: 12),
            _AppCardPaymentTile(
              isSelected: _selectedMethod == PaymentMethodType.appCard,
              title: tr(PaymentStringKeys.appCard),
              subtitle: tr(PaymentStringKeys.appCardSubtitle),
              selectedBank: _selectedBank,
              languageCode: _language.code,
              onTap: () => _selectMethod(PaymentMethodType.appCard),
              onBankSelected: _selectBank,
              selectBankLabel: tr(PaymentStringKeys.selectBank),
            ),
            const SizedBox(height: 12),
            _BrandPaymentTile(
              isSelected: _selectedMethod == PaymentMethodType.kakaoPay,
              title: tr(PaymentStringKeys.kakaoPay),
              backgroundColor: const Color(0xFFFEE500),
              foregroundColor: AppColors.primary,
              icon: Icons.chat_bubble_rounded,
              onTap: () => _selectMethod(PaymentMethodType.kakaoPay),
            ),
            const SizedBox(height: 12),
            _BrandPaymentTile(
              isSelected: _selectedMethod == PaymentMethodType.tossPay,
              title: tr(PaymentStringKeys.tossPay),
              backgroundColor: const Color(0xFF0064FF),
              foregroundColor: AppColors.textOnPrimary,
              icon: Icons.account_balance_wallet_rounded,
              onTap: () => _selectMethod(PaymentMethodType.tossPay),
            ),
            const SizedBox(height: 12),
            _BankTransferTile(
              isSelected: _selectedMethod == PaymentMethodType.bankTransfer,
              title: tr(PaymentStringKeys.bankTransfer),
              subtitle: tr(PaymentStringKeys.bankTransferSubtitle),
              onTap: () => _selectMethod(PaymentMethodType.bankTransfer),
              detailsTitle: tr(PaymentStringKeys.bankDetailsTitle),
              accountLabel: tr(PaymentStringKeys.accountNumber),
              recipientLabel: tr(PaymentStringKeys.recipient),
              recipientName: tr(PaymentStringKeys.recipientName),
              copyLabel: tr(PaymentStringKeys.copy),
              onCopy: _copyBankDetails,
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class _AppCardPaymentTile extends StatelessWidget {
  const _AppCardPaymentTile({
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.selectedBank,
    required this.languageCode,
    required this.onTap,
    required this.onBankSelected,
    required this.selectBankLabel,
  });

  final bool isSelected;
  final String title;
  final String subtitle;
  final KoreanBank? selectedBank;
  final String languageCode;
  final VoidCallback onTap;
  final ValueChanged<KoreanBank> onBankSelected;
  final String selectBankLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color:
                        isSelected ? AppColors.accent : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.caption(
                            fontWeight: FontWeight.w700,
                          ).copyWith(fontSize: 15),
                        ),
                        Text(
                          subtitle,
                          style: AppTypography.productMeta()
                              .copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.credit_card_rounded,
                    color: AppColors.accent,
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: isSelected
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        selectBankLabel,
                        style: AppTypography.caption(fontWeight: FontWeight.w600)
                            .copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.4,
                        ),
                        itemCount: KoreanBank.values.length,
                        itemBuilder: (context, index) {
                          final bank = KoreanBank.values[index];
                          final isBankSelected = selectedBank == bank;
                          return _BankGridTile(
                            bank: bank,
                            label: bank.localizedLabel(languageCode),
                            isSelected: isBankSelected,
                            onTap: () => onBankSelected(bank),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankGridTile extends StatelessWidget {
  const _BankGridTile({
    required this.bank,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final KoreanBank bank;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bank.brandColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  bank.shortCode,
                  style: AppTypography.caption(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textOnPrimary,
                  ).copyWith(fontSize: 10),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(fontWeight: FontWeight.w600)
                      .copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPaymentTile extends StatelessWidget {
  const _BrandPaymentTile({
    required this.isSelected,
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.onTap,
  });

  final bool isSelected;
  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accent : Colors.transparent,
              width: isSelected ? 2.5 : 0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: foregroundColor.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: foregroundColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.caption(
                    fontWeight: FontWeight.w800,
                    color: foregroundColor,
                  ).copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankTransferTile extends StatelessWidget {
  const _BankTransferTile({
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.detailsTitle,
    required this.accountLabel,
    required this.recipientLabel,
    required this.recipientName,
    required this.copyLabel,
    required this.onCopy,
  });

  final bool isSelected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String detailsTitle;
  final String accountLabel;
  final String recipientLabel;
  final String recipientName;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color:
                        isSelected ? AppColors.accent : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.caption(
                            fontWeight: FontWeight.w700,
                          ).copyWith(fontSize: 15),
                        ),
                        Text(
                          subtitle,
                          style: AppTypography.productMeta()
                              .copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.account_balance_outlined,
                    color: AppColors.accent,
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: isSelected
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          detailsTitle,
                          style: AppTypography.heading(fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                        _DetailRow(
                          label: accountLabel,
                          value: hanaBankAccountNumber,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: recipientLabel,
                          value: recipientName,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: onCopy,
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: Text(copyLabel),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: AppColors.accent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: AppTypography.productMeta().copyWith(fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.caption(fontWeight: FontWeight.w700)
                .copyWith(fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _PaymentBottomBar extends StatelessWidget {
  const _PaymentBottomBar({
    required this.validationMessage,
    required this.onConfirm,
    required this.bottomInset,
    required this.label,
  });

  final String? validationMessage;
  final VoidCallback onConfirm;
  final double bottomInset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (validationMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.saleRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.saleRed.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  validationMessage!,
                  style: AppTypography.caption(color: AppColors.saleRed)
                      .copyWith(fontSize: 12),
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
                  onPressed: onConfirm,
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
                    label,
                    style: AppTypography.caption(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ).copyWith(fontSize: 16),
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
