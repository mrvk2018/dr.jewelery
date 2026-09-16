import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/supabase_config.dart';
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

/// Supabase Storage для фото товаров (админ-панель).
abstract final class ProductImageStorage {
  static const bucket = 'product-images';
  static const folder = 'products';
}

/// Имена Postgres RPC / Edge-моста к MSSQL DrJaw (анти-дубль перед оплатой).
abstract final class SkladAvailabilityRpc {
  static const checkAvailability = 'check_sklad_availability';
  static const reserveForCheckout = 'reserve_product_for_checkout';
  static const skuParam = 'p_sku';
}

bool _parseSkladAvailabilityRpcResult(dynamic result) {
  if (result is bool) return result;
  if (result is Map) {
    final dynamic available =
        result['available'] ?? result['is_available'] ?? result['success'];
    if (available is bool) return available;
  }
  return false;
}

Future<bool> _invokeSkladAvailabilityRpc(
  SupabaseClient client,
  String rpcName,
  String sku,
) async {
  final result = await client.rpc(
    rpcName,
    params: {SkladAvailabilityRpc.skuParam: sku},
  );
  return _parseSkladAvailabilityRpcResult(result);
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

  /// Выбор фото из галереи (сжатие ~85%, maxWidth 1080). `null` — отмена или ошибка.
  Future<File?> pickProductImageFromGallery();

  /// Загрузка в бакет [ProductImageStorage.bucket]/[ProductImageStorage.folder].
  /// Возвращает публичный URL или `null` при ошибке.
  Future<String?> uploadProductImageToStorage(File file);

  /// Точечная проверка «живого» наличия на складе (MSSQL через Supabase RPC).
  /// `true` — статус «В наличии»; `false` — продано/недоступно или ошибка моста.
  Future<bool> checkSkladAvailability(String sku);

  /// Бронирование SKU на время оплаты (`products.status = reserved` на сервере).
  Future<bool> reserveProductForCheckout(String sku);
}

Future<File?> _pickProductImageFromGalleryImpl() async {
  if (kIsWeb) {
    debugPrint('pickProductImageFromGallery: галерея недоступна на web');
    return null;
  }

  try {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (xFile == null) return null;
    return File(xFile.path);
  } catch (error, stackTrace) {
    debugPrint('pickProductImageFromGallery failed: $error');
    debugPrint('$stackTrace');
    return null;
  }
}

Future<String?> _uploadProductImageToStorageImpl(
  SupabaseClient client,
  File file,
) async {
  try {
    if (!await file.exists()) {
      debugPrint('uploadProductImageToStorage: файл не найден');
      return null;
    }

    final objectPath =
        '${ProductImageStorage.folder}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final bytes = await file.readAsBytes();

    await client.storage.from(ProductImageStorage.bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    return client.storage
        .from(ProductImageStorage.bucket)
        .getPublicUrl(objectPath);
  } catch (error, stackTrace) {
    debugPrint('uploadProductImageToStorage failed: $error');
    debugPrint('$stackTrace');
    return null;
  }
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

  @override
  Future<File?> pickProductImageFromGallery() =>
      _pickProductImageFromGalleryImpl();

  @override
  Future<String?> uploadProductImageToStorage(File file) {
    try {
      return _uploadProductImageToStorageImpl(Supabase.instance.client, file);
    } catch (error, stackTrace) {
      debugPrint(
        'LocalDatabaseService.uploadProductImageToStorage failed: $error',
      );
      debugPrint('$stackTrace');
      return Future<String?>.value(null);
    }
  }

  Future<bool> _localStockAvailable(String sku) async {
    final products = await getProducts();
    for (final product in products) {
      if (product.sku == sku) {
        return product.stockQuantity > 0;
      }
    }
    return false;
  }

  Future<bool> _localReserveSku(String sku) async {
    final products = await getProducts();
    final index = products.indexWhere((product) => product.sku == sku);
    if (index < 0) return false;
    if (products[index].stockQuantity <= 0) return false;
    products[index] = products[index].copyWith(stockQuantity: 0);
    await _writeProducts(products);
    return true;
  }

  @override
  Future<bool> checkSkladAvailability(String sku) async {
    if (sku.trim().isEmpty) return false;
    try {
      return await _invokeSkladAvailabilityRpc(
        Supabase.instance.client,
        SkladAvailabilityRpc.checkAvailability,
        sku,
      );
    } catch (error, stackTrace) {
      debugPrint('LocalDatabaseService.checkSkladAvailability RPC: $error');
      debugPrint('$stackTrace');
      return _localStockAvailable(sku);
    }
  }

  @override
  Future<bool> reserveProductForCheckout(String sku) async {
    if (sku.trim().isEmpty) return false;
    try {
      final reserved = await _invokeSkladAvailabilityRpc(
        Supabase.instance.client,
        SkladAvailabilityRpc.reserveForCheckout,
        sku,
      );
      if (reserved) return true;
    } catch (error, stackTrace) {
      debugPrint('LocalDatabaseService.reserveProductForCheckout RPC: $error');
      debugPrint('$stackTrace');
    }
    return _localReserveSku(sku);
  }
}

/// Каркас облачного хранилища (Supabase / Firebase).
///
/// Включается флагом `JewelrySunlightApp.useCloudBackend = true`.
/// Каждый метод описывает целевой SDK-вызов и политику RLS.
class CloudDatabaseService implements DatabaseService {
  CloudDatabaseService({
    this.supabaseUrl = SupabaseConfig.projectUrl,
    this.anonKey = SupabaseConfig.anonKey,
    this.firebaseProjectId = 'dr-jewelry',
  });

  final String supabaseUrl;
  final String anonKey;
  final String firebaseProjectId;

  SupabaseClient get _supabaseClient => Supabase.instance.client;

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

  /// Строка Supabase (snake_case) → JSON для [ProductItem.fromJson].
  static Map<String, dynamic> _productRowToClientJson(
    Map<String, dynamic> row,
  ) {
    return {
      'id': row['id'],
      'sku': row['sku'],
      'stockQuantity': row['stock_quantity'],
      'name': row['name'],
      'description': row['description'],
      'metal': row['metal'],
      'salePrice': row['sale_price'],
      'oldPrice': row['old_price'],
      'discountPercent': row['discount_percent'],
      'category': row['category'],
      'insert': row['insert'],
      'iconIndex': row['icon_index'],
      'availableSizes': row['available_sizes'],
      'imageUrl': row['image_url'],
      'weightGrams': row['weight_grams'],
    };
  }

  @override
  Future<List<ProductItem>> getProducts() async {
    try {
      final rows = await _supabaseClient
          .from('products')
          .select()
          .range(0, 4999);
      return rows
          .map((row) => Map<String, dynamic>.from(row))
          .map(_productRowToClientJson)
          .map(ProductItem.fromJson)
          .toList();
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getProducts failed: $error');
      debugPrint('$stackTrace');
      return [];
    }
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
    // --- Складской sync (Node.js/Python): НЕ вызывать из Flutter-клиента ---
    //
    // Supabase JS (только на сервере, env SUPABASE_SERVICE_ROLE_KEY):
    //   const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    //   await supabase
    //     .from('products')
    //     .update({ stock_quantity: Math.max(0, newQuantity) })
    //     .eq('sku', sku);
    //
    // Supabase REST (PostgREST), тот же эффект:
    //   PATCH {SUPABASE_URL}/rest/v1/products?sku=eq.{sku}
    //   Headers:
    //     apikey: {SERVICE_ROLE_KEY}
    //     Authorization: Bearer {SERVICE_ROLE_KEY}
    //     Content-Type: application/json
    //     Prefer: return=minimal
    //   Body: {"stock_quantity": 4}
    //
    // RLS: у anon/authenticated UPDATE запрещён; service_role обходит RLS.
    // Поток: [SQL склад] → sync-скрипт → Supabase products → Flutter getProducts().
    //
    // Клиентское приложение не имеет права менять остатки (.cursorrules).
    throw SecurityException(
      'Отказано в updateProductStock: изменение остатков по sku="$sku" '
      'запрещено на мобильном клиенте. Используйте серверный sync с service_role.',
    );
  }

  @override
  Future<List<FeedbackItem>> getFeedback(UserRole actorRole) async {
    // MVP: инбокс на устройстве (как Local), пока нет Supabase `feedback`.
    // TODO: для admin — SELECT из Supabase с RLS admin-only.
    final raw = (await _localPrefs()).getString(DatabaseCollections.feedback);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => FeedbackItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<void> insertFeedback(FeedbackItem feedback) async {
    final messages = await getFeedback(UserRole.guest);
    messages.removeWhere((existing) => existing.id == feedback.id);
    messages.insert(0, feedback);
    await _writeCloudFeedback(messages);
  }

  @override
  Future<void> deleteFeedback(String id, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'deleteFeedback');
    final messages = await getFeedback(UserRole.guest);
    messages.removeWhere((item) => item.id == id);
    await _writeCloudFeedback(messages);
  }

  @override
  Future<List<OrderItem>> getOrders(String userId) async {
    final maps = _readCloudOrderMaps(await _localPrefs());
    final orders = maps.map(OrderItem.fromJson).toList();
    if (userId.isEmpty) return orders;
    return orders;
  }

  @override
  Future<void> createOrder(OrderItem order) async {
    final orders = await getOrders('');
    orders.removeWhere((existing) => existing.id == order.id);
    orders.insert(0, order);
    await _writeCloudOrders(orders);
  }

  @override
  Future<Map<String, dynamic>?> loadCartSnapshot() async {
    final raw = (await _localPrefs()).getString(DatabaseCollections.cart);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> saveCartSnapshot(Map<String, dynamic> snapshot) async {
    final prefs = await _localPrefs();
    await prefs.setString(DatabaseCollections.cart, jsonEncode(snapshot));
  }

  @override
  Future<List<String>> loadFavoriteIds() async {
    final raw = (await _localPrefs()).getString(DatabaseCollections.favorites);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.map((id) => id.toString()).toList();
  }

  @override
  Future<void> saveFavoriteIds(List<String> ids) async {
    final prefs = await _localPrefs();
    await prefs.setString(DatabaseCollections.favorites, jsonEncode(ids));
  }

  @override
  Future<Map<String, dynamic>?> loadProfileSession() async {
    final raw =
        (await _localPrefs()).getString(DatabaseCollections.profileSession);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> saveProfileSession(Map<String, dynamic> session) async {
    final prefs = await _localPrefs();
    await prefs.setString(
      DatabaseCollections.profileSession,
      jsonEncode(session),
    );
  }

  Future<SharedPreferences> _localPrefs() => SharedPreferences.getInstance();

  List<Map<String, dynamic>> _readCloudOrderMaps(SharedPreferences prefs) {
    final raw = prefs.getString(DatabaseCollections.orders);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _writeCloudFeedback(List<FeedbackItem> messages) async {
    final prefs = await _localPrefs();
    await prefs.setString(
      DatabaseCollections.feedback,
      jsonEncode(messages.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _writeCloudOrders(List<OrderItem> orders) async {
    final prefs = await _localPrefs();
    await prefs.setString(
      DatabaseCollections.orders,
      jsonEncode(orders.map((item) => item.toJson()).toList()),
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

  @override
  Future<File?> pickProductImageFromGallery() =>
      _pickProductImageFromGalleryImpl();

  @override
  Future<String?> uploadProductImageToStorage(File file) {
    try {
      return _uploadProductImageToStorageImpl(_supabaseClient, file);
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.uploadProductImageToStorage failed: $error',
      );
      debugPrint('$stackTrace');
      return Future<String?>.value(null);
    }
  }

  @override
  Future<bool> checkSkladAvailability(String sku) async {
    if (sku.trim().isEmpty) return false;
    try {
      return await _invokeSkladAvailabilityRpc(
        _supabaseClient,
        SkladAvailabilityRpc.checkAvailability,
        sku,
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.checkSkladAvailability failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> reserveProductForCheckout(String sku) async {
    if (sku.trim().isEmpty) return false;
    try {
      return await _invokeSkladAvailabilityRpc(
        _supabaseClient,
        SkladAvailabilityRpc.reserveForCheckout,
        sku,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.reserveProductForCheckout failed: $error',
      );
      debugPrint('$stackTrace');
      return false;
    }
  }
}
