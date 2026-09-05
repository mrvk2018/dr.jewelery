import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/profile/domain/models/user_profile.dart';
import '../../shared/models/feedback_item.dart';
import '../../shared/models/product_item.dart';

/// Ключи коллекций облачного/локального хранилища.
abstract final class DatabaseCollections {
  static const products = 'cloud_products';
  static const feedback = 'cloud_feedback';
}

/// Отказ в записи: роль не соответствует требованиям бэкенда.
class UnauthorizedWriteException implements Exception {
  UnauthorizedWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Абстрактный репозиторий данных витрины и обратной связи.
///
/// Реализации:
/// - [LocalDatabaseService] — постоянное JSON-хранилище (сейчас).
/// - [CloudDatabaseService] — каркас под Supabase / Firebase (позже).
abstract class DatabaseService {
  Future<List<ProductItem>> loadProducts();

  /// Сохранение товара.
  ///
  /// SECURITY (backend / RLS / Firebase Rules):
  /// запись в коллекцию `products` разрешена ТОЛЬКО если
  /// `auth.uid.role == UserRole.admin`. Клиентский вызов без
  /// роли admin должен быть отклонён и на устройстве, и на сервере.
  Future<void> saveProduct(
    ProductItem item, {
    required UserRole actorRole,
  });

  Future<void> deleteProduct(
    String id, {
    required UserRole actorRole,
  });

  Future<List<FeedbackItem>> loadFeedback();

  Future<void> saveFeedback(FeedbackItem item);

  Future<void> deleteFeedback(
    String id, {
    required UserRole actorRole,
  });
}

/// Локальная постоянная реализация (SharedPreferences + JSON).
/// Имитирует облако до подключения Supabase/Firebase.
class LocalDatabaseService implements DatabaseService {
  LocalDatabaseService(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalDatabaseService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalDatabaseService(prefs);
  }

  /// Если база пуста — засевает 6 демо-изделий Dr. Jewelry.
  @override
  Future<List<ProductItem>> loadProducts() async {
    final raw = _prefs.getString(DatabaseCollections.products);
    if (raw == null || raw.isEmpty) {
      final seeded = List<ProductItem>.from(initialCatalogProducts);
      await _writeProducts(seeded);
      return seeded;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final products = decoded
        .whereType<Map>()
        .map((item) => ProductItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    if (products.isEmpty) {
      final seeded = List<ProductItem>.from(initialCatalogProducts);
      await _writeProducts(seeded);
      return seeded;
    }

    return products;
  }

  @override
  Future<void> saveProduct(
    ProductItem item, {
    required UserRole actorRole,
  }) async {
    // Жёсткая проверка роли: только UserRole.admin пишет в каталог.
    // На облаке это дублируется политикой:
    //   Supabase RLS:  USING (auth.jwt() ->> 'role' = 'admin')
    //   Firebase:      allow write: if request.auth.token.role == 'admin'
    _assertAdmin(actorRole, action: 'saveProduct');

    final products = await loadProducts();
    final index = products.indexWhere((product) => product.id == item.id);
    if (index >= 0) {
      products[index] = item;
    } else {
      products.insert(0, item);
    }
    await _writeProducts(products);
  }

  @override
  Future<void> deleteProduct(
    String id, {
    required UserRole actorRole,
  }) async {
    _assertAdmin(actorRole, action: 'deleteProduct');
    final products = await loadProducts();
    products.removeWhere((product) => product.id == id);
    await _writeProducts(products);
  }

  @override
  Future<List<FeedbackItem>> loadFeedback() async {
    final raw = _prefs.getString(DatabaseCollections.feedback);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => FeedbackItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<void> saveFeedback(FeedbackItem item) async {
    // Обратная связь доступна гостю и клиенту: insert-only на бэкенде.
    final messages = await loadFeedback();
    messages.removeWhere((existing) => existing.id == item.id);
    messages.insert(0, item);
    await _writeFeedback(messages);
  }

  @override
  Future<void> deleteFeedback(
    String id, {
    required UserRole actorRole,
  }) async {
    _assertAdmin(actorRole, action: 'deleteFeedback');
    final messages = await loadFeedback();
    messages.removeWhere((item) => item.id == id);
    await _writeFeedback(messages);
  }

  void _assertAdmin(UserRole actorRole, {required String action}) {
    if (actorRole != UserRole.admin) {
      throw UnauthorizedWriteException(
        'Отказано в $action: требуется UserRole.admin, получено $actorRole',
      );
    }
  }

  Future<void> _writeProducts(List<ProductItem> products) {
    return _prefs.setString(
      DatabaseCollections.products,
      jsonEncode(products.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _writeFeedback(List<FeedbackItem> messages) {
    return _prefs.setString(
      DatabaseCollections.feedback,
      jsonEncode(messages.map((item) => item.toJson()).toList()),
    );
  }
}

/// Каркас облачного хранилища (Supabase / Firebase).
///
/// Подключение: заменить [LocalDatabaseService] в `app.dart` на этот класс
/// и реализовать вызовы REST/SDK. Политики безопасности — только на сервере.
class CloudDatabaseService implements DatabaseService {
  CloudDatabaseService({this.endpoint = 'https://api.dr-jewelry.cloud'});

  final String endpoint;

  @override
  Future<List<ProductItem>> loadProducts() async {
    // TODO: GET $endpoint/products
    throw UnimplementedError('Подключите Supabase/Firebase SDK');
  }

  @override
  Future<void> saveProduct(
    ProductItem item, {
    required UserRole actorRole,
  }) async {
    // TODO: POST $endpoint/products
    // Header: Authorization + role claim. Сервер отклонит не-admin.
    throw UnimplementedError('Подключите Supabase/Firebase SDK');
  }

  @override
  Future<void> deleteProduct(
    String id, {
    required UserRole actorRole,
  }) async {
    throw UnimplementedError('Подключите Supabase/Firebase SDK');
  }

  @override
  Future<List<FeedbackItem>> loadFeedback() async {
    throw UnimplementedError('Подключите Supabase/Firebase SDK');
  }

  @override
  Future<void> saveFeedback(FeedbackItem item) async {
    throw UnimplementedError('Подключите Supabase/Firebase SDK');
  }

  @override
  Future<void> deleteFeedback(
    String id, {
    required UserRole actorRole,
  }) async {
    throw UnimplementedError('Подключите Supabase/Firebase SDK');
  }
}
