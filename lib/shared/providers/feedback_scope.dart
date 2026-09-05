import 'package:flutter/material.dart';

import 'feedback_controller.dart';

/// Доступ к [FeedbackController] из дерева виджетов.
class FeedbackScope extends InheritedNotifier<FeedbackController> {
  const FeedbackScope({
    super.key,
    required FeedbackController controller,
    required super.child,
  }) : super(notifier: controller);

  static FeedbackController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FeedbackScope>();
    assert(scope != null, 'FeedbackScope не найден в дереве виджетов');
    return scope!.notifier!;
  }

  static FeedbackController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FeedbackScope>()
        ?.notifier;
  }
}
