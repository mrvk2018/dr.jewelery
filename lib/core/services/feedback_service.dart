import '../../shared/providers/feedback_controller.dart';

/// Отправка обратной связи через глобальный контроллер.
Future<void> submitFeedback({
  required FeedbackController controller,
  required String message,
  required String languageCode,
}) {
  return controller.submitMessage(
    message: message,
    languageCode: languageCode,
  );
}
