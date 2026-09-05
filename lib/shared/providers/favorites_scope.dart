import 'package:flutter/material.dart';

import 'favorites_controller.dart';

/// Доступ к [FavoritesController] из дерева виджетов.
class FavoritesScope extends InheritedNotifier<FavoritesController> {
  const FavoritesScope({
    super.key,
    required FavoritesController controller,
    required super.child,
  }) : super(notifier: controller);

  static FavoritesController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FavoritesScope>();
    assert(scope != null, 'FavoritesScope не найден в дереве виджетов');
    return scope!.notifier!;
  }

  static FavoritesController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FavoritesScope>()
        ?.notifier;
  }
}
