import 'package:flutter/material.dart';

import 'cart_controller.dart';

/// Доступ к [CartController] из дерева виджетов.
class CartScope extends InheritedNotifier<CartController> {
  const CartScope({
    super.key,
    required CartController controller,
    required super.child,
  }) : super(notifier: controller);

  static CartController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CartScope>();
    assert(scope != null, 'CartScope не найден в дереве виджетов');
    return scope!.notifier!;
  }

  static CartController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CartScope>()
        ?.notifier;
  }
}
