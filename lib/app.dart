import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_constants.dart';
import 'core/l10n/app_language.dart';
import 'core/services/database_service.dart';
import 'core/services/onboarding_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/presentation/pages/onboarding_screen.dart';
import 'features/shell/presentation/pages/main_screen.dart';
import 'l10n/app_localizations.dart';
import 'shared/providers/cart_controller.dart';
import 'shared/providers/cart_scope.dart';
import 'shared/providers/catalog_controller.dart';
import 'shared/providers/catalog_scope.dart';
import 'shared/providers/feedback_controller.dart';
import 'shared/providers/feedback_scope.dart';
import 'shared/providers/locale_provider.dart';

class JewelrySunlightApp extends StatefulWidget {
  const JewelrySunlightApp({super.key});

  @override
  State<JewelrySunlightApp> createState() => _JewelrySunlightAppState();
}

class _JewelrySunlightAppState extends State<JewelrySunlightApp> {
  late final CartController _cartController = CartController();
  CatalogController? _catalogController;
  FeedbackController? _feedbackController;
  LocaleProvider? _localeProvider;
  OnboardingStorage? _storage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final storage = await OnboardingStorage.create();
    final localeProvider = LocaleProvider(storage);
    final database = await LocalDatabaseService.create();
    final catalogController = CatalogController(database);
    final feedbackController = FeedbackController(database);
    await Future.wait<void>([
      catalogController.load(),
      feedbackController.load(),
    ]);
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _localeProvider = localeProvider;
      _catalogController = catalogController;
      _feedbackController = feedbackController;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _cartController.dispose();
    _catalogController?.dispose();
    _feedbackController?.dispose();
    _localeProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready ||
        _storage == null ||
        _localeProvider == null ||
        _catalogController == null ||
        _feedbackController == null) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return FeedbackScope(
      controller: _feedbackController!,
      child: CatalogScope(
        controller: _catalogController!,
        child: CartScope(
          controller: _cartController,
          child: LocaleScope(
            provider: _localeProvider!,
            child: ListenableBuilder(
              listenable: _localeProvider!,
              builder: (context, _) {
                return MaterialApp(
                  title: AppConstants.appName,
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light,
                  locale: _localeProvider!.locale,
                  supportedLocales: AppLanguage.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: _AppRootGate(storage: _storage!),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AppRootGate extends StatefulWidget {
  const _AppRootGate({required this.storage});

  final OnboardingStorage storage;

  @override
  State<_AppRootGate> createState() => _AppRootGateState();
}

class _AppRootGateState extends State<_AppRootGate> {
  late bool _showOnboarding = !widget.storage.isOnboardingComplete;

  Future<void> _completeOnboarding() async {
    await widget.storage.completeOnboarding();
    if (!mounted) return;
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return OnboardingScreen(
        storage: widget.storage,
        onComplete: _completeOnboarding,
      );
    }
    return const MainScreen();
  }
}
