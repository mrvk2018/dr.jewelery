import 'package:flutter/material.dart';

import 'catalog_controller.dart';

/// Доступ к [CatalogController] из дерева виджетов.
class CatalogScope extends InheritedNotifier<CatalogController> {
  const CatalogScope({
    super.key,
    required CatalogController controller,
    required super.child,
  }) : super(notifier: controller);

  static CatalogController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CatalogScope>();
    assert(scope != null, 'CatalogScope не найден в дереве виджетов');
    return scope!.notifier!;
  }

  static CatalogController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CatalogScope>()
        ?.notifier;
  }
}
