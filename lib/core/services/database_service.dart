import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/profile/domain/models/order_item.dart';
import '../../features/profile/domain/models/user_profile.dart';
import '../../shared/models/feedback_item.dart';
import '../../shared/models/product_item.dart';
import 'device_secrets_store.dart';

export 'device_secrets_store.dart' show IntegrationKeys, DeviceSecretKeys;

/// Ключи коллекций облачного/локального хранилища.
abstract final class DatabaseCollections {
  static const products = 'cloud_products_krw_i18n_v2';
  static const feedback = 'cloud_feedback';
  static const cart = 'dj_cart_v1';
  static const favorites = 'dj_favorites_v1';
  static const orders = 'dj_profile_orders_v1';
  static const profileSession = 'dj_profile_session_v1';
  static const adminPasswordHash = DeviceSecretKeys.adminPasswordHash;
  static const adminDeviceClaimed = DeviceSecretKeys.adminDeviceClaimed;
  static const posApiKey = DeviceSecretKeys.posApiKey;
  static const tossApiKey = DeviceSecretKeys.tossApiKey;
}

/// Отказ в записи: роль не соответствует требованиям бэкенда / RLS.
class UnauthorizedWriteException implements Exception {
  UnauthorizedWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Отказ в чтении защищённой коллекции (например, инбокс обращений).
class SecurityException implements Exception {
  SecurityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Контракт доступа к данным витрины, обращений и заказов.
///
/// Реализации:
/// - [LocalDatabaseService] — постоянное JSON-хранилище (текущий MVP).
/// - [CloudDatabaseService] — каркас под Supabase / Firebase.
///
/// Переключение: константа `useCloudBackend` в `lib/app.dart`.
abstract class DatabaseService {
  /// Публичная витрина: чтение доступно гостю без авторизации.
  Future<List<ProductItem>> getProducts();

  /// Запись товара. Только [UserRole.admin] (RLS / Firebase Rules).
  Future<void> saveProduct(ProductItem item, UserRole actorRole);

  /// Удаление товара. Только [UserRole.admin].
  Future<void> deleteProduct(String id, UserRole actorRole);

  /// Синхронизация остатка с кассой (POS): ключ — [ProductItem.sku].
  Future<void> updateProductStock(String sku, int newQuantity);

  /// Чтение обращений. Только [UserRole.admin] на облаке (RLS SELECT).
  Future<List<FeedbackItem>> getFeedback(UserRole actorRole);

  /// Отправка обращения клиентом/гостем — без авторизации (insert-only).
  Future<void> insertFeedback(FeedbackItem feedback);

  /// Удаление обращения. Только [UserRole.admin].
  Future<void> deleteFeedback(String id, UserRole actorRole);

  /// Заказы пользователя. На облаке: `WHERE user_id = :userId`.
  Future<List<OrderItem>> getOrders(String userId);

  /// Создание заказа после успешной оплаты.
  Future<void> createOrder(OrderItem order);

  Future<Map<String, dynamic>?> loadCartSnapshot();

  Future<void> saveCartSnapshot(Map<String, dynamic> snapshot);

  Future<List<String>> loadFavoriteIds();

  Future<void> saveFavoriteIds(List<String> ids);

  Future<Map<String, dynamic>?> loadProfileSession();

  Future<void> saveProfileSession(Map<String, dynamic> session);

  /// First Claim: владелец уже назначен на этом устройстве.
  Future<bool> isAdminDeviceClaimed();

  /// Первый вход: сохранить хэш пароля и поднять флаг claimed.
  Future<void> claimAdminDevice(String password);

  /// Проверка пароля владельца (после First Claim).
  Future<bool> verifyAdminPassword(String password);

  Future<IntegrationKeys> loadIntegrationKeys();

  Future<void> saveIntegrationKeys(IntegrationKeys keys);
}

/// Локальная постоянная реализация (SharedPreferences + JSON, KRW).
///
/// Имитирует облако до переключения `useCloudBackend` в `lib/app.dart`.
class LocalDatabaseService implements DatabaseService {
  LocalDatabaseService(this._prefs) : _secrets = DeviceSecretsStore(_prefs);

  final SharedPreferences _prefs;
  final DeviceSecretsStore _secrets;

  static Future<LocalDatabaseService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalDatabaseService(prefs);
  }

  /// Если база пуста — засевает демо-изделия Dr. Jewelry в вонах.
  @override
  Future<List<ProductItem>> getProducts() async {
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
  Future<void> saveProduct(ProductItem item, UserRole actorRole) async {
    // Локальный дубль RLS: запись в каталог только для admin.
    // Облако: Supabase RLS  USING (auth.jwt() ->> 'role' = 'admin')
    //         Firebase      allow write: if request.auth.token.role == 'admin'
    _assertAdminWrite(actorRole, action: 'saveProduct');

    final products = await getProducts();
    final index = products.indexWhere((product) => product.id == item.id);
    if (index >= 0) {
      products[index] = item;
    } else {
      products.insert(0, item);
    }
    await _writeProducts(products);
  }

  @override
  Future<void> deleteProduct(String id, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'deleteProduct');
    final products = await getProducts();
    products.removeWhere((product) => product.id == id);
    await _writeProducts(products);
  }

  @override
  Future<void> updateProductStock(String sku, int newQuantity) async {
    final products = await getProducts();
    final index = products.indexWhere((product) => product.sku == sku);
    if (index < 0) return;
    final quantity = newQuantity < 0 ? 0 : newQuantity;
    products[index] = products[index].copyWith(stockQuantity: quantity);
    await _writeProducts(products);
  }

  @override
  Future<List<FeedbackItem>> getFeedback(UserRole actorRole) async {
    // На устройстве инбокс один: роль не режем, чтобы MVP админки работал
    // до логина. На облаке [CloudDatabaseService.getFeedback] бросит
    // [SecurityException], если actorRole != UserRole.admin.
    final raw = _prefs.getString(DatabaseCollections.feedback);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => FeedbackItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<void> insertFeedback(FeedbackItem feedback) async {
    // Insert-only: гость и клиент пишут без авторизации.
    final messages = await _readFeedback();
    messages.removeWhere((existing) => existing.id == feedback.id);
    messages.insert(0, feedback);
    await _writeFeedback(messages);
  }

  @override
  Future<void> deleteFeedback(String id, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'deleteFeedback');
    final messages = await _readFeedback();
    messages.removeWhere((item) => item.id == id);
    await _writeFeedback(messages);
  }

  @override
  Future<List<OrderItem>> getOrders(String userId) async {
    final maps = _readOrderMaps();
    final orders = maps.map(OrderItem.fromJson).toList();
    // Локальный MVP хранит заказы устройства целиком (нет колонки user_id).
    // Облако отфильтрует `.eq('user_id', userId)`.
    if (userId.isEmpty) return orders;
    return orders;
  }

  @override
  Future<void> createOrder(OrderItem order) async {
    final orders = await getOrders('');
    orders.removeWhere((existing) => existing.id == order.id);
    orders.insert(0, order);
    await _writeOrders(orders);
  }

  void _assertAdminWrite(UserRole actorRole, {required String action}) {
    if (actorRole != UserRole.admin) {
      throw UnauthorizedWriteException(
        'Отказано в $action: требуется UserRole.admin, получено $actorRole',
      );
    }
  }

  Future<List<FeedbackItem>> _readFeedback() async {
    final raw = _prefs.getString(DatabaseCollections.feedback);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => FeedbackItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  List<Map<String, dynamic>> _readOrderMaps() {
    final raw = _prefs.getString(DatabaseCollections.orders);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
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

  Future<void> _writeOrders(List<OrderItem> orders) {
    return _prefs.setString(
      DatabaseCollections.orders,
      jsonEncode(orders.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<Map<String, dynamic>?> loadCartSnapshot() async {
    final raw = _prefs.getString(DatabaseCollections.cart);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> saveCartSnapshot(Map<String, dynamic> snapshot) {
    return _prefs.setString(DatabaseCollections.cart, jsonEncode(snapshot));
  }

  @override
  Future<List<String>> loadFavoriteIds() async {
    final raw = _prefs.getString(DatabaseCollections.favorites);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.map((id) => id.toString()).toList();
  }

  @override
  Future<void> saveFavoriteIds(List<String> ids) {
    return _prefs.setString(DatabaseCollections.favorites, jsonEncode(ids));
  }

  @override
  Future<Map<String, dynamic>?> loadProfileSession() async {
    final raw = _prefs.getString(DatabaseCollections.profileSession);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> saveProfileSession(Map<String, dynamic> session) {
    return _prefs.setString(
      DatabaseCollections.profileSession,
      jsonEncode(session),
    );
  }

  @override
  Future<bool> isAdminDeviceClaimed() async => _secrets.isAdminDeviceClaimed;

  @override
  Future<void> claimAdminDevice(String password) {
    return _secrets.claimAdminDevice(password);
  }

  @override
  Future<bool> verifyAdminPassword(String password) async {
    return _secrets.verifyAdminPassword(password);
  }

  @override
  Future<IntegrationKeys> loadIntegrationKeys() async {
    return _secrets.loadIntegrationKeys();
  }

  @override
  Future<void> saveIntegrationKeys(IntegrationKeys keys) {
    return _secrets.saveIntegrationKeys(keys);
  }
}

/// Каркас облачного хранилища (Supabase / Firebase).
///
/// Включается флагом `JewelrySunlightApp.useCloudBackend = true`.
/// Каждый метод описывает целевой SDK-вызов и политику RLS.
class CloudDatabaseService implements DatabaseService {
  CloudDatabaseService({
    this.supabaseUrl = 'https://YOUR_PROJECT.supabase.co',
    this.anonKey = 'YOUR_SUPABASE_ANON_KEY',
    this.firebaseProjectId = 'dr-jewelry',
  });

  final String supabaseUrl;
  final String anonKey;
  final String firebaseProjectId;

  void _assertAdminWrite(UserRole actorRole, {required String action}) {
    if (actorRole != UserRole.admin) {
      throw UnauthorizedWriteException(
        'Отказано в $action: требуется UserRole.admin, получено $actorRole',
      );
    }
  }

  void _assertAdminRead(UserRole actorRole, {required String action}) {
    if (actorRole != UserRole.admin) {
      throw SecurityException(
        'Отказано в $action: чтение разрешено только UserRole.admin',
      );
    }
  }

  @override
  Future<List<ProductItem>> getProducts() async {
    // TODO: Публичная витрина — SELECT без auth.
    // Supabase:
    //   final rows = await Supabase.instance.client.from('products').select();
    //   return rows.map(ProductItem.fromJson).toList();
    // Firebase:
    //   final snap = await FirebaseFirestore.instance.collection('products').get();
    // RLS: allow SELECT to anon/authenticated. Цены только KRW (int).
    throw UnimplementedError(
      'CloudDatabaseService.getProducts: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> saveProduct(ProductItem item, UserRole actorRole) async {
    // SECURITY / RLS: запись в `products` только для admin.
    // Клиентская проверка дублирует серверную политику — не заменяет её.
    _assertAdminWrite(actorRole, action: 'saveProduct');

    // TODO: Supabase upsert товара (цены в KRW, без копеек).
    //   await Supabase.instance.client.from('products').upsert(item.toJson());
    //   RLS: CREATE POLICY products_write_admin ON products
    //        FOR ALL USING (auth.jwt() ->> 'role' = 'admin')
    //        WITH CHECK (auth.jwt() ->> 'role' = 'admin');
    // TODO: Firebase
    //   await FirebaseFirestore.instance
    //       .collection('products').doc(item.id).set(item.toJson());
    //   allow write: if request.auth.token.role == 'admin';
    throw UnimplementedError(
      'CloudDatabaseService.saveProduct: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> deleteProduct(String id, UserRole actorRole) async {
    // SECURITY / RLS: удаление товара только UserRole.admin.
    _assertAdminWrite(actorRole, action: 'deleteProduct');

    // TODO: Supabase
    //   await Supabase.instance.client.from('products').delete().eq('id', id);
    //   Та же policy products_write_admin, что и для saveProduct.
    // TODO: Firebase
    //   await FirebaseFirestore.instance.collection('products').doc(id).delete();
    //   allow delete: if request.auth.token.role == 'admin';
    throw UnimplementedError(
      'CloudDatabaseService.deleteProduct: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> updateProductStock(String sku, int newQuantity) async {
    // TODO: Realtime-синхронизация остатков с POS-терминалом магазина.
    // Касса шлёт webhook / пишет в `products.stock_quantity` по SKU/штрихкоду.
    // Supabase:
    //   await Supabase.instance.client
    //       .from('products')
    //       .update({'stock_quantity': newQuantity})
    //       .eq('sku', sku);
    //   Затем Realtime subscribe:
    //   Supabase.instance.client
    //       .from('products')
    //       .stream(primaryKey: ['sku'])
    //       .listen((rows) => catalog.applyStockSnapshot(rows));
    // Firebase:
    //   await FirebaseFirestore.instance
    //       .collection('products')
    //       .where('sku', isEqualTo: sku)
    //       .get()
    //       .then((snap) => snap.docs.first.reference
    //           .update({'stockQuantity': newQuantity}));
    // RLS: UPDATE stock разрешён service_role / POS-интеграции, не клиенту.
    throw UnimplementedError(
      'CloudDatabaseService.updateProductStock: подключите POS + Supabase/Firebase',
    );
  }

  @override
  Future<List<FeedbackItem>> getFeedback(UserRole actorRole) async {
    // SECURITY / RLS: SELECT из `feedback` только admin.
    // Гость и клиент не читают чужие обращения.
    _assertAdminRead(actorRole, action: 'getFeedback');

    // TODO: Supabase
    //   final rows = await Supabase.instance.client
    //       .from('feedback')
    //       .select()
    //       .order('created_at', ascending: false);
    //   RLS: CREATE POLICY feedback_read_admin ON feedback
    //        FOR SELECT USING (auth.jwt() ->> 'role' = 'admin');
    // TODO: Firebase
    //   allow read: if request.auth.token.role == 'admin';
    throw UnimplementedError(
      'CloudDatabaseService.getFeedback: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> insertFeedback(FeedbackItem feedback) async {
    // SECURITY: insert-only без авторизации (анонимный клиент / гость).
    // Не проверяем UserRole — обращение уходит с витрины и из поддержки.
    // RLS INSERT: WITH CHECK (true) для anon; UPDATE/DELETE запрещены.
    // Защита от спама — rate limit / captcha на Edge Function, не роль.

    // TODO: Supabase
    //   await Supabase.instance.client.from('feedback').insert(feedback.toJson());
    //   CREATE POLICY feedback_insert_anon ON feedback
    //        FOR INSERT TO anon, authenticated WITH CHECK (true);
    // TODO: Firebase
    //   await FirebaseFirestore.instance.collection('feedback').add(...);
    //   allow create: if true;
    //   allow update, delete: if request.auth.token.role == 'admin';
    throw UnimplementedError(
      'CloudDatabaseService.insertFeedback: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> deleteFeedback(String id, UserRole actorRole) async {
    // SECURITY / RLS: удаление обращения только admin.
    _assertAdminWrite(actorRole, action: 'deleteFeedback');

    // TODO: Supabase
    //   await Supabase.instance.client.from('feedback').delete().eq('id', id);
    // TODO: Firebase
    //   await FirebaseFirestore.instance.collection('feedback').doc(id).delete();
    throw UnimplementedError(
      'CloudDatabaseService.deleteFeedback: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<List<OrderItem>> getOrders(String userId) async {
    // TODO: Заказы текущего пользователя (или все — если JWT role = admin).
    // Supabase:
    //   var query = Supabase.instance.client.from('orders').select();
    //   if (jwt.role != 'admin') query = query.eq('user_id', userId);
    //   RLS: пользователь читает только свои строки
    //        USING (auth.uid()::text = user_id OR jwt.role = 'admin');
    // Firebase:
    //   allow read: if request.auth.uid == resource.data.user_id
    //               || request.auth.token.role == 'admin';
    throw UnimplementedError(
      'CloudDatabaseService.getOrders: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> createOrder(OrderItem order) async {
    // TODO: INSERT после успешной оплаты (сумма уже в KRW).
    // Supabase:
    //   await Supabase.instance.client.from('orders').insert({
    //     ...order.toJson(),
    //     'user_id': Supabase.instance.client.auth.currentUser?.id,
    //   });
    // RLS: WITH CHECK (auth.uid()::text = user_id);
    // Firebase:
    //   allow create: if request.auth.uid == request.resource.data.user_id;
    throw UnimplementedError(
      'CloudDatabaseService.createOrder: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<Map<String, dynamic>?> loadCartSnapshot() async {
    // TODO: Корзина в `carts` по auth.uid() либо в local cache до логина.
    //   await Supabase.instance.client.from('carts').select().eq('user_id', uid).maybeSingle();
    throw UnimplementedError(
      'CloudDatabaseService.loadCartSnapshot: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> saveCartSnapshot(Map<String, dynamic> snapshot) async {
    // TODO: upsert `carts` WHERE user_id = auth.uid().
    throw UnimplementedError(
      'CloudDatabaseService.saveCartSnapshot: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<List<String>> loadFavoriteIds() async {
    // TODO: SELECT product_id FROM favorites WHERE user_id = auth.uid();
    throw UnimplementedError(
      'CloudDatabaseService.loadFavoriteIds: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<void> saveFavoriteIds(List<String> ids) async {
    // TODO: заменить набор favorites пользователя (transaction / upsert).
    throw UnimplementedError(
      'CloudDatabaseService.saveFavoriteIds: подключите Supabase/Firebase SDK',
    );
  }

  @override
  Future<Map<String, dynamic>?> loadProfileSession() async {
    // TODO: сессия живёт в Auth SDK (Supabase Auth / Firebase Auth), не в таблице.
    //   final user = Supabase.instance.client.auth.currentUser;
    throw UnimplementedError(
      'CloudDatabaseService.loadProfileSession: подключите Auth SDK',
    );
  }

  @override
  Future<void> saveProfileSession(Map<String, dynamic> session) async {
    // TODO: профильные поля — таблица `profiles` (name, bonuses, loyalty_card).
    // Роль admin назначается только через dashboard / custom claim, не с клиента.
    throw UnimplementedError(
      'CloudDatabaseService.saveProfileSession: подключите Auth SDK',
    );
  }

  Future<DeviceSecretsStore> _deviceSecrets() async {
    final prefs = await SharedPreferences.getInstance();
    return DeviceSecretsStore(prefs);
  }

  @override
  Future<bool> isAdminDeviceClaimed() async {
    // First Claim остаётся на устройстве даже при облачном каталоге.
    return (await _deviceSecrets()).isAdminDeviceClaimed;
  }

  @override
  Future<void> claimAdminDevice(String password) async {
    await (await _deviceSecrets()).claimAdminDevice(password);
  }

  @override
  Future<bool> verifyAdminPassword(String password) async {
    return (await _deviceSecrets()).verifyAdminPassword(password);
  }

  @override
  Future<IntegrationKeys> loadIntegrationKeys() async {
    // TODO: в проде ключи POS/Toss — только на устройстве владельца,
    // не в общей таблице Supabase.
    return (await _deviceSecrets()).loadIntegrationKeys();
  }

  @override
  Future<void> saveIntegrationKeys(IntegrationKeys keys) async {
    await (await _deviceSecrets()).saveIntegrationKeys(keys);
  }
}
