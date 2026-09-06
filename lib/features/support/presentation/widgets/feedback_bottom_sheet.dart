import 'package:flutter/material.dart';

import '../../../../core/l10n/app_language.dart';
import '../../../../core/l10n/support_localizations.dart';
import '../../../../core/services/feedback_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/feedback_scope.dart';

/// Премиальная форма обратной связи.
class FeedbackBottomSheet extends StatefulWidget {
  const FeedbackBottomSheet({
    super.key,
    required this.language,
  });

  final AppLanguage language;

  static Future<void> show(
    BuildContext context, {
    required AppLanguage language,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedbackBottomSheet(language: language),
    );
  }

  @override
  State<FeedbackBottomSheet> createState() => _FeedbackBottomSheetState();
}

class _FeedbackBottomSheetState extends State<FeedbackBottomSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  String tr(String key) => supportTr(key, widget.language.code);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(SupportStringKeys.feedbackEmpty)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await submitFeedback(
        controller: FeedbackScope.of(context),
        message: message,
        languageCode: widget.language.code,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(SupportStringKeys.feedbackSuccess)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(SupportStringKeys.feedbackTitle),
                      style: AppTypography.heading(fontSize: 20),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSending ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLines: 5,
                minLines: 4,
                enabled: !_isSending,
                decoration: InputDecoration(
                  hintText: tr(SupportStringKeys.feedbackHint),
                  hintStyle: AppTypography.productMeta().copyWith(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.all(16),
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
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    disabledBackgroundColor: AppColors.border,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnPrimary,
                          ),
                        )
                      : Text(
                          tr(SupportStringKeys.feedbackSend),
                          style: AppTypography.caption(
                            color: AppColors.textOnPrimary,
                            fontWeight: FontWeight.w700,
                          ).copyWith(fontSize: 15),
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

/// Компактная кнопка «Обратная связь».
class FeedbackButton extends StatelessWidget {
  const FeedbackButton({
    super.key,
    required this.language,
  });

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => FeedbackBottomSheet.show(
        context,
        language: language,
      ),
      icon: const Icon(Icons.support_agent_outlined, size: 18),
      label: Text(
        supportTr(SupportStringKeys.feedbackButton, language.code),
        style: AppTypography.caption(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ).copyWith(fontSize: 13),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// @deprecated Используйте [FeedbackButton].
typedef ReportIssueButton = FeedbackButton;
