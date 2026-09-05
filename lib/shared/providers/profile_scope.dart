import 'package:flutter/material.dart';

import 'profile_controller.dart';

/// Доступ к [ProfileController] из дерева виджетов.
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfileController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'ProfileScope не найден в дереве виджетов');
    return scope!.notifier!;
  }

  static ProfileController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ProfileScope>()
        ?.notifier;
  }
}
