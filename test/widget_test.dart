import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jewelry_sunlight_store/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'app_language': 'ru',
    });
  });
  testWidgets('App renders home screen with live countdown and products',
      (tester) async {
    await tester.pumpWidget(const JewelrySunlightApp());
    await tester.pump();

    expect(find.text('DR. JEWELRY'), findsOneWidget);
    expect(find.textContaining('Скидки'), findsOneWidget);
    expect(find.textContaining('ГРАНДИОЗНАЯ'), findsOneWidget);
    expect(find.textContaining('До конца осталось 02:14:'), findsOneWidget);
    expect(find.text('Рекомендуем для вас'), findsOneWidget);
    expect(find.text('Кольцо из белого золота с бриллиантом'), findsOneWidget);
    expect(find.text('В корзину'), findsWidgets);
    expect(find.text('Главная'), findsOneWidget);
  });

  testWidgets('Catalog tab shows search, categories and filters', (tester) async {
    await tester.pumpWidget(const JewelrySunlightApp());
    await tester.pump();

    await tester.tap(find.text('Каталог'));
    await tester.pumpAndSettle();

    expect(find.text('Поиск украшений'), findsOneWidget);
    expect(find.text('Фильтры'), findsOneWidget);
    expect(find.text('Кольца'), findsWidgets);
    expect(find.text('Серьги'), findsWidgets);

    await tester.tap(find.text('Фильтры'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Показать результаты'), findsOneWidget);
    expect(find.text('Металл'), findsOneWidget);
    expect(find.text('Вставка'), findsOneWidget);
    expect(find.text('Размер'), findsOneWidget);
  });

  testWidgets('Profile guest view and admin access flow', (tester) async {
    await tester.pumpWidget(const JewelrySunlightApp());
    await tester.pump();

    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();

    expect(
      find.text('Войдите, чтобы копить бонусы и оформлять заказы'),
      findsOneWidget,
    );
    expect(find.text('Войти через Google'), findsOneWidget);

    await tester.tap(find.text('Войти через Google'));
    await tester.pumpAndSettle();

    expect(find.text('Анна Иванова'), findsWidgets);

    final secretAvatar = find.byKey(const Key('profile_secret_avatar'));
    expect(secretAvatar, findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(secretAvatar);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();

    expect(find.text('Инициализация владельца Dr. Jewelry'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin_claim_password')),
      'owner-passphrase',
    );
    await tester.enterText(
      find.byKey(const Key('admin_claim_confirm')),
      'owner-passphrase',
    );
    await tester.tap(find.byKey(const Key('admin_claim_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Владелец Dr. Jewelry'), findsWidgets);
    expect(
      find.text('Режим администратора Dr. Jewelry активирован'),
      findsOneWidget,
    );

    await tester.pumpAndSettle(const Duration(seconds: 4));

    await tester.scrollUntilVisible(
      find.text('Панель управления'),
      120,
    );
    expect(find.text('Панель управления'), findsOneWidget);

    await tester.tap(find.text('Панель управления'));
    await tester.pump();
    expect(find.text('Запрос биометрии...'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Панель управления'), findsWidgets);
    expect(find.text('Заказы'), findsOneWidget);
    expect(find.text('Товары'), findsOneWidget);
  });

  testWidgets('Product detail and cart flow works', (tester) async {
    await tester.pumpWidget(const JewelrySunlightApp());
    await tester.pump();

    await tester.tap(find.text('Каталог'));
    await tester.pumpAndSettle();

    final productCard = find.ancestor(
      of: find.text('Кольцо из белого золота с бриллиантом'),
      matching: find.byType(InkWell),
    );
    await tester.scrollUntilVisible(
      productCard,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(productCard);
    await tester.pumpAndSettle();

    expect(find.text('Добавить в корзину'), findsOneWidget);
    expect(find.textContaining('Оплата Долями'), findsOneWidget);

    await tester.tap(find.text('Добавить в корзину'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Корзина'));
    await tester.pumpAndSettle();

    expect(find.text('Кольцо из белого золота с бриллиантом'), findsOneWidget);
    expect(find.text('Перейти к оплате'), findsOneWidget);
  });

  testWidgets('Onboarding shows on first launch with PIPA compliance',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JewelrySunlightApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Choose Language'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Terms Agreement'), findsOneWidget);

    expect(find.text('Continue'), findsOneWidget);
    final continueButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(
      tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Continue'),
      ).onPressed,
      isNotNull,
    );
  });
}
