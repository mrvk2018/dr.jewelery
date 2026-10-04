import 'dart:async';
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
import '../../shared/models/app_marketing_settings.dart';
import '../../shared/models/seller_item.dart';
import '../../shared/models/seller_referral_apply_result.dart';
import 'device_secrets_store.dart';

export 'device_secrets_store.dart' show IntegrationKeys, DeviceSecretKeys;

/// Ключи коллекций облачного/локального хранилища.
abstract final class DatabaseCollections {
  static const products = 'cloud_products_krw_i18n_v2';
  static const feedback = 'cloud_feedback';
  static const sellers = 'cloud_sellers_v1';
  static const cart = 'dj_cart_v1';
  static const favorites = 'dj_favorites_v1';
  static const orders = 'dj_profile_orders_v1';
  static const profileSession = 'dj_profile_session_v1';
  static const appMarketing = 'local_app_marketing_settings_v1';
  static const localReferralSeller = 'local_referred_by_seller_v1';
  static const adminPinHash = DeviceSecretKeys.adminPinHash;
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
  static const releaseCheckout = 'release_product_checkout';
  static const confirmProductPaid = 'confirm_product_paid';
  static const skuParam = 'p_sku';
  static const productIdParam = 'p_id';
}

/// Postgres RPC для профиля, реферала и маркетинга.
abstract final class ProfileBonusRpc {
  static const applySellerReferralPromo = 'apply_seller_referral_promo';
  static const saveAppMarketingSettings = 'save_app_marketing_settings';
  static const promoCodeParam = 'p_promo_code';
  static const welcomeEnabledParam = 'p_welcome_bonus_enabled';
  static const welcomeAmountParam = 'p_welcome_bonus_amount';
}

/// SECURITY DEFINER RPC для админ-панели (обход RLS при anonymous JWT на клиенте).
abstract final class AdminOrdersRpc {
  static const adminEmail = 'dr.jewelry.korea@gmail.com';
  static const getAllOrders = 'get_all_orders_for_admin';
  static const updateOrderStatus = 'update_order_status_by_admin';
  static const adminEmailParam = 'p_admin_email';
  static const orderIdParam = 'p_order_id';
  static const newStatusParam = 'p_new_status';
}

/// OAuth-провайдер для link identity (аноним → постоянный аккаунт).
enum OAuthLinkProvider {
  google,
  apple,
}

bool _parseSkladAvailabilityCheckResult(dynamic result) {
  if (result is num) return result.toInt() > 0;
  if (result is bool) return result;
  if (result is Map) {
    final dynamic available =
        result['available'] ?? result['is_available'] ?? result['success'];
    if (available is bool) return available;
    if (available is num) return available.toInt() > 0;
  }
  return false;
}

bool _parseReserveCheckoutResult(dynamic result) {
  if (result is bool) return result;
  if (result is Map) {
    final dynamic ok = result['success'] ?? result['reserved'];
    if (ok is bool) return ok;
  }
  return false;
}

Future<bool> _invokeCheckSkladAvailabilityRpc(
  SupabaseClient client,
  String sku,
) async {
  final result = await client.rpc(
    SkladAvailabilityRpc.checkAvailability,
    params: {SkladAvailabilityRpc.skuParam: sku},
  );
  return _parseSkladAvailabilityCheckResult(result);
}

Future<bool> _invokeReserveProductForCheckoutRpc(
  SupabaseClient client,
  String productId,
) async {
  final result = await client.rpc(
    SkladAvailabilityRpc.reserveForCheckout,
    params: {SkladAvailabilityRpc.productIdParam: productId},
  );
  return _parseReserveCheckoutResult(result);
}

Future<bool> _invokeReleaseProductCheckoutRpc(
  SupabaseClient client,
  String productId,
) async {
  final result = await client.rpc(
    SkladAvailabilityRpc.releaseCheckout,
    params: {SkladAvailabilityRpc.productIdParam: productId},
  );
  return _parseReserveCheckoutResult(result);
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

  /// Картотека продавцов (промокоды). Только [UserRole.admin].
  Future<List<SellerItem>> getSellers(UserRole actorRole);

  /// Добавление или обновление продавца. Только [UserRole.admin].
  Future<void> saveSeller(SellerItem seller, UserRole actorRole);

  /// Удаление продавца по промокоду. Только [UserRole.admin].
  Future<void> deleteSeller(String promoCode, UserRole actorRole);

  /// Заказы пользователя. На облаке: `WHERE user_id = :userId`.
  Future<List<OrderItem>> getOrders(String userId);

  /// Все заказы для админ-панели (`created_at` DESC).
  Future<List<OrderItem>> getAllOrders(UserRole actorRole);

  /// Смена статуса доставки (админ).
  Future<void> updateOrderStatus(
    String orderId,
    String status,
    UserRole actorRole,
  );

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

  /// First Claim: сохранить хэш 4-значного PIN и поднять флаг claimed.
  Future<void> claimAdminDevicePin(String pin);

  /// Проверка локального PIN (после First Claim).
  Future<bool> verifyAdminPin(String pin);

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
  /// Бронирование строки витрины по [products.id] (MSSQL Items.Id), не по SKU.
  Future<bool> reserveProductForCheckout(String productId);

  /// Отмена брони после ошибки/отмены Toss (возврат `active` в Supabase).
  Future<void> releaseProductCheckout(String productId);

  /// Подтверждение оплаты: перевод `reservation` → `paid` на сервере.
  Future<bool> confirmProductPaid(String productId);

  /// UUID текущего Supabase Auth пользователя или `null`.
  Future<String?> currentAuthUserId();

  /// Вход покупателя (anonymous auth) + загрузка `public.profiles`.
  Future<UserProfile> signInCustomerWithSupabase();

  /// Выход из Supabase Auth (покупатель).
  Future<void> signOutSupabaseAuth();

  /// Текущая сессия — anonymous (до привязки Google/Apple).
  Future<bool> isCurrentAuthAnonymous();

  /// Link Identity: привязать OAuth к текущему UUID без смены `user.id`.
  Future<UserProfile> linkOAuthProvider(OAuthLinkProvider provider);

  /// Актуальный профиль из `profiles` для текущей сессии.
  Future<UserProfile?> refreshCustomerProfileFromCloud();

  /// `profiles.bonus_balance` для текущего auth user.
  Future<int> fetchBonusBalanceForCurrentUser();

  /// Серверная привязка промокода продавца (anti-abuse RPC).
  Future<SellerReferralApplyResult> applySellerReferralPromo(String promoCode);

  /// Глобальные настройки welcome-акции (`app_settings`).
  Future<AppMarketingSettings> getAppMarketingSettings();

  /// Сохранение welcome-акции (админ).
  Future<void> saveAppMarketingSettings(
    AppMarketingSettings settings,
    UserRole actorRole,
  );
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
  Future<List<SellerItem>> getSellers(UserRole actorRole) async {
    _assertAdminRead(actorRole, action: 'getSellers');
    return _readSellers();
  }

  @override
  Future<void> saveSeller(SellerItem seller, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'saveSeller');
    final sellers = _readSellers();
    final code = SellerItem.normalizePromoCode(seller.promoCode);
    final index = sellers.indexWhere((item) => item.promoCode == code);
    final normalized = seller.copyWith(promoCode: code);
    if (index >= 0) {
      sellers[index] = normalized;
    } else {
      sellers.insert(0, normalized);
    }
    await _writeSellers(sellers);
  }

  @override
  Future<void> deleteSeller(String promoCode, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'deleteSeller');
    final code = SellerItem.normalizePromoCode(promoCode);
    final sellers = _readSellers();
    sellers.removeWhere((item) => item.promoCode == code);
    await _writeSellers(sellers);
  }

  void _assertAdminRead(UserRole actorRole, {required String action}) {
    if (actorRole != UserRole.admin) {
      throw SecurityException(
        'Отказано в $action: чтение разрешено только UserRole.admin',
      );
    }
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

  @override
  Future<List<OrderItem>> getAllOrders(UserRole actorRole) async {
    _assertAdminRead(actorRole, action: 'getAllOrders');
    final orders = await getOrders('');
    orders.sort((a, b) => b.dateLabel.compareTo(a.dateLabel));
    return orders;
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    String status,
    UserRole actorRole,
  ) async {
    _assertAdminWrite(actorRole, action: 'updateOrderStatus');
    final orders = await getOrders('');
    final index = orders.indexWhere((o) => o.id == orderId);
    if (index < 0) return;
    final mapped = OrderStatus.fromSupabaseStatus(status);
    orders[index] = orders[index].copyWith(status: mapped);
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

  List<SellerItem> _readSellers() {
    final raw = _prefs.getString(DatabaseCollections.sellers);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => SellerItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _writeSellers(List<SellerItem> sellers) {
    return _prefs.setString(
      DatabaseCollections.sellers,
      jsonEncode(sellers.map((item) => item.toJson()).toList()),
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
  Future<void> claimAdminDevicePin(String pin) {
    return _secrets.claimAdminDevicePin(pin);
  }

  @override
  Future<bool> verifyAdminPin(String pin) async {
    return _secrets.verifyAdminPin(pin);
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

  Future<void> _localReleaseProductId(String productId) async {
    final products = await getProducts();
    final index = products.indexWhere((product) => product.id == productId);
    if (index < 0) return;
    final qty = products[index].stockQuantity;
    products[index] = products[index].copyWith(
      stockQuantity: qty <= 0 ? 1 : qty,
    );
    await _writeProducts(products);
  }

  @override
  Future<bool> checkSkladAvailability(String sku) async {
    if (sku.trim().isEmpty) return false;
    try {
      return await _invokeCheckSkladAvailabilityRpc(
        Supabase.instance.client,
        sku,
      );
    } catch (error, stackTrace) {
      debugPrint('LocalDatabaseService.checkSkladAvailability RPC: $error');
      debugPrint('$stackTrace');
      return _localStockAvailable(sku);
    }
  }

  @override
  Future<bool> reserveProductForCheckout(String productId) async {
    if (productId.trim().isEmpty) return false;
    try {
      final reserved = await _invokeReserveProductForCheckoutRpc(
        Supabase.instance.client,
        productId,
      );
      if (reserved) return true;
    } catch (error, stackTrace) {
      debugPrint('LocalDatabaseService.reserveProductForCheckout RPC: $error');
      debugPrint('$stackTrace');
    }
    final products = await getProducts();
    final index = products.indexWhere((product) => product.id == productId);
    if (index < 0) return false;
    return _localReserveSku(products[index].sku);
  }

  @override
  Future<void> releaseProductCheckout(String productId) async {
    if (productId.trim().isEmpty) return;
    try {
      await _invokeReleaseProductCheckoutRpc(
        Supabase.instance.client,
        productId,
      );
      return;
    } catch (error, stackTrace) {
      debugPrint('LocalDatabaseService.releaseProductCheckout RPC: $error');
      debugPrint('$stackTrace');
    }
    await _localReleaseProductId(productId);
  }

  @override
  Future<bool> confirmProductPaid(String productId) async {
    if (productId.trim().isEmpty) return false;
    try {
      final result = await Supabase.instance.client.rpc(
        SkladAvailabilityRpc.confirmProductPaid,
        params: {SkladAvailabilityRpc.productIdParam: productId},
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Ошибка confirmProductPaid: $e');
      return false;
    }
  }

  @override
  Future<String?> currentAuthUserId() async => null;

  @override
  Future<UserProfile> signInCustomerWithSupabase() async {
    return UserProfile.demoCustomer;
  }

  @override
  Future<void> signOutSupabaseAuth() async {}

  @override
  Future<bool> isCurrentAuthAnonymous() async => false;

  @override
  Future<UserProfile> linkOAuthProvider(OAuthLinkProvider provider) async {
    throw UnimplementedError(
      'linkOAuthProvider доступен только с CloudDatabaseService',
    );
  }

  @override
  Future<UserProfile?> refreshCustomerProfileFromCloud() async => null;

  @override
  Future<int> fetchBonusBalanceForCurrentUser() async {
    final session = await loadProfileSession();
    if (session == null) return 0;
    final rawUser = session['user'];
    if (rawUser is! Map) return 0;
    return UserProfile.fromJson(Map<String, dynamic>.from(rawUser)).bonusBalance;
  }

  @override
  Future<SellerReferralApplyResult> applySellerReferralPromo(
    String promoCode,
  ) async {
    final code = SellerItem.normalizePromoCode(promoCode);
    if (code.isEmpty) {
      return const SellerReferralApplyResult(
        ok: false,
        errorCode: 'empty_code',
      );
    }

    SellerItem? seller;
    for (final item in _readSellers()) {
      if (item.promoCode == code && item.isActive) {
        seller = item;
        break;
      }
    }
    if (seller == null) {
      return const SellerReferralApplyResult(
        ok: false,
        errorCode: 'invalid_code',
      );
    }

    final existing = _prefs.getString(DatabaseCollections.localReferralSeller);
    if (existing != null && existing.isNotEmpty && existing != code) {
      return const SellerReferralApplyResult(
        ok: true,
        alreadyReferred: true,
        discountPercent: 0,
        message: 'У вас уже привязан другой промокод продавца',
      );
    }

    if (existing == null || existing.isEmpty) {
      await _prefs.setString(DatabaseCollections.localReferralSeller, code);
    }

    return SellerReferralApplyResult(
      ok: true,
      discountPercent: seller.buyerBonusPercent,
      sellerCode: code,
    );
  }

  @override
  Future<AppMarketingSettings> getAppMarketingSettings() async {
    final raw = _prefs.getString(DatabaseCollections.appMarketing);
    if (raw == null || raw.isEmpty) return AppMarketingSettings.defaults;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return AppMarketingSettings.defaults;
    final map = Map<String, dynamic>.from(decoded);
    return AppMarketingSettings(
      welcomeBonusEnabled: map['welcomeBonusEnabled'] as bool? ?? false,
      welcomeBonusAmountKrw: (map['welcomeBonusAmountKrw'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> saveAppMarketingSettings(
    AppMarketingSettings settings,
    UserRole actorRole,
  ) async {
    _assertAdminWrite(actorRole, action: 'saveAppMarketingSettings');
    await _prefs.setString(
      DatabaseCollections.appMarketing,
      jsonEncode({
        'welcomeBonusEnabled': settings.welcomeBonusEnabled,
        'welcomeBonusAmountKrw': settings.welcomeBonusAmountKrw,
      }),
    );
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

  static List<dynamic> _parseAvailableSizesField(Object? raw) {
    if (raw == null) return const <dynamic>[];
    if (raw is List) return raw;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const <dynamic>[];
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) return decoded;
      } catch (_) {
        return const <dynamic>[];
      }
    }
    return const <dynamic>[];
  }

  /// Строка Supabase (snake_case) → JSON для [ProductItem.fromJson].
  ///
  /// Складской sync часто оставляет [metal], [insert], [category] пустыми — без
  /// дефолтов [ProductItem.fromJson] падает и [getProducts] возвращал [] целиком.
  static Map<String, dynamic> _productRowToClientJson(
    Map<String, dynamic> row,
  ) {
    final salePrice = (row['sale_price'] as num?)?.toInt() ?? 0;
    final oldPrice = (row['old_price'] as num?)?.toInt() ?? salePrice;
    return {
      'id': row['id']?.toString() ?? '',
      'sku': row['sku']?.toString() ?? '',
      'stockQuantity': (row['stock_quantity'] as num?)?.toInt() ?? 0,
      'name': row['name'] is Map ? row['name'] : <String, String>{},
      'description':
          row['description'] is Map ? row['description'] : <String, String>{},
      'metal': (row['metal'] as String?)?.trim() ?? '',
      'salePrice': salePrice,
      'oldPrice': oldPrice,
      'discountPercent': (row['discount_percent'] as num?)?.toInt() ?? 0,
      'category': (row['category'] as String?)?.trim() ?? '',
      'insert': (row['insert'] as String?)?.trim() ?? '',
      'iconIndex': (row['icon_index'] as num?)?.toInt() ?? 0,
      'availableSizes': _parseAvailableSizesField(row['available_sizes']),
      'imageUrl': row['image_url'] as String?,
      'weightGrams': (row['weight_grams'] as num?)?.toDouble(),
    };
  }

  Future<List<ProductItem>> _readCloudProductCache() async {
    final raw = (await _localPrefs()).getString(DatabaseCollections.products);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => ProductItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _writeCloudProductCache(List<ProductItem> products) async {
    final prefs = await _localPrefs();
    await prefs.setString(
      DatabaseCollections.products,
      jsonEncode(products.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<List<ProductItem>> getProducts() async {
    try {
      final rows = await _supabaseClient
          .from('products')
          .select()
          .range(0, 4999);
      final products = <ProductItem>[];
      for (final dynamic row in rows) {
        if (row is! Map) continue;
        try {
          products.add(
            ProductItem.fromJson(
              _productRowToClientJson(Map<String, dynamic>.from(row)),
            ),
          );
        } catch (error, stackTrace) {
          debugPrint(
            'CloudDatabaseService.getProducts: skip row '
            '${row['id']}: $error',
          );
          debugPrint('$stackTrace');
        }
      }
      if (products.isNotEmpty) {
        await _writeCloudProductCache(products);
      }
      return products;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getProducts failed: $error');
      debugPrint('$stackTrace');
      return _readCloudProductCache();
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

  static SellerItem _sellerRowToItem(Map<String, dynamic> row) {
    final createdRaw = row['created_at'];
    DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.parse(createdRaw);
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else {
      createdAt = DateTime.now();
    }
    return SellerItem(
      promoCode: SellerItem.normalizePromoCode(row['promo_code'] as String),
      name: (row['name'] as String).trim(),
      isActive: row['is_active'] as bool? ?? true,
      buyerBonusKrw: (row['buyer_bonus_krw'] as num?)?.toInt() ?? 0,
      buyerBonusPercent: (row['buyer_bonus_percent'] as num?)?.toInt() ?? 0,
      createdAt: createdAt,
    );
  }

  Future<List<SellerItem>> _readCloudSellersCache() async {
    final raw = (await _localPrefs()).getString(DatabaseCollections.sellers);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => SellerItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _writeCloudSellersCache(List<SellerItem> sellers) async {
    final prefs = await _localPrefs();
    await prefs.setString(
      DatabaseCollections.sellers,
      jsonEncode(sellers.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<List<SellerItem>> getSellers(UserRole actorRole) async {
    _assertAdminRead(actorRole, action: 'getSellers');
    try {
      final rows = await _supabaseClient
          .from('sellers')
          .select()
          .order('created_at', ascending: false);
      final sellers = rows
          .map((row) => Map<String, dynamic>.from(row))
          .map(_sellerRowToItem)
          .toList();
      await _writeCloudSellersCache(sellers);
      return sellers;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getSellers failed: $error');
      debugPrint('$stackTrace');
      return _readCloudSellersCache();
    }
  }

  @override
  Future<void> saveSeller(SellerItem seller, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'saveSeller');
    final code = SellerItem.normalizePromoCode(seller.promoCode);
    try {
      await _supabaseClient.from('sellers').upsert(
        {
          'promo_code': code,
          'name': seller.name.trim(),
          'is_active': seller.isActive,
          'buyer_bonus_percent': seller.buyerBonusPercent.clamp(0, 100),
        },
        onConflict: 'promo_code',
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.saveSeller failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
    final cached = await _readCloudSellersCache();
    final index = cached.indexWhere((item) => item.promoCode == code);
    final normalized = seller.copyWith(promoCode: code);
    if (index >= 0) {
      cached[index] = normalized;
    } else {
      cached.insert(0, normalized);
    }
    await _writeCloudSellersCache(cached);
  }

  @override
  Future<void> deleteSeller(String promoCode, UserRole actorRole) async {
    _assertAdminWrite(actorRole, action: 'deleteSeller');
    final code = SellerItem.normalizePromoCode(promoCode);
    try {
      await _supabaseClient.from('sellers').delete().eq('promo_code', code);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.deleteSeller failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
    final cached = await _readCloudSellersCache();
    cached.removeWhere((item) => item.promoCode == code);
    await _writeCloudSellersCache(cached);
  }

  @override
  Future<List<OrderItem>> getOrders(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final response = await _supabaseClient
          .from('orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (response as List)
          .map(
            (row) => OrderItem.fromSupabase(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getOrders failed: $error');
      debugPrint('$stackTrace');
      return [];
    }
  }

  @override
  Future<List<OrderItem>> getAllOrders(UserRole actorRole) async {
    _assertAdminRead(actorRole, action: 'getAllOrders');
    try {
      final response = await _supabaseClient.rpc(
        AdminOrdersRpc.getAllOrders,
        params: {AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail},
      );
      if (response is! List) return [];
      return response
          .map(
            (row) => OrderItem.fromSupabase(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getAllOrders failed: $error');
      debugPrint('$stackTrace');
      return [];
    }
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    String status,
    UserRole actorRole,
  ) async {
    _assertAdminWrite(actorRole, action: 'updateOrderStatus');
    try {
      await _supabaseClient.rpc(
        AdminOrdersRpc.updateOrderStatus,
        params: {
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
          AdminOrdersRpc.orderIdParam: orderId,
          AdminOrdersRpc.newStatusParam: status,
        },
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.updateOrderStatus failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Map<String, dynamic> _orderInsertRow(OrderItem order, String userId) {
    return {
      'id': order.id,
      'user_id': userId,
      'product_name': order.productName,
      'amount': order.amount,
      'status': OrderItem.statusToSupabase(order.status),
      'customer_name': order.customerName,
      'shipping_postal_code': order.shippingPostalCode,
      'shipping_road_address': order.shippingRoadAddress,
      'shipping_detail_address': order.shippingDetailAddress,
      'recipient_name': order.recipientName,
      'recipient_phone': order.recipientPhone,
      if (order.sellerCode.isNotEmpty) 'seller_code': order.sellerCode,
      if (order.sellerName.isNotEmpty) 'seller_name': order.sellerName,
    };
  }

  @override
  Future<void> createOrder(OrderItem order) async {
    final userId = _supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('createOrder: нет auth user для user_id');
    }
    try {
      await _supabaseClient.from('orders').insert(_orderInsertRow(order, userId));
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.createOrder failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
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

  Future<void> _writeCloudFeedback(List<FeedbackItem> messages) async {
    final prefs = await _localPrefs();
    await prefs.setString(
      DatabaseCollections.feedback,
      jsonEncode(messages.map((item) => item.toJson()).toList()),
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
  Future<void> claimAdminDevicePin(String pin) async {
    await (await _deviceSecrets()).claimAdminDevicePin(pin);
  }

  @override
  Future<bool> verifyAdminPin(String pin) async {
    return (await _deviceSecrets()).verifyAdminPin(pin);
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
      return await _invokeCheckSkladAvailabilityRpc(
        _supabaseClient,
        sku,
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.checkSkladAvailability failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> reserveProductForCheckout(String productId) async {
    if (productId.trim().isEmpty) return false;
    try {
      return await _invokeReserveProductForCheckoutRpc(
        _supabaseClient,
        productId,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.reserveProductForCheckout failed: $error',
      );
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<void> releaseProductCheckout(String productId) async {
    if (productId.trim().isEmpty) return;
    try {
      await _invokeReleaseProductCheckoutRpc(_supabaseClient, productId);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.releaseProductCheckout failed: $error');
      debugPrint('$stackTrace');
    }
  }

  @override
  Future<bool> confirmProductPaid(String productId) async {
    try {
      final result = await _supabaseClient.rpc(
        SkladAvailabilityRpc.confirmProductPaid,
        params: {SkladAvailabilityRpc.productIdParam: productId},
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Ошибка confirmProductPaid: $e');
      return false;
    }
  }

  UserProfile _userProfileFromAuth(User authUser, Map<String, dynamic>? row) {
    final bonus = (row?['bonus_balance'] as num?)?.toInt() ?? 0;
    final referred = row?['referred_by_seller'] as String?;
    final metaName = authUser.userMetadata?['name'] as String?;
    final shortId = authUser.id.replaceAll('-', '').substring(0, 8).toUpperCase();
    return UserProfile(
      id: authUser.id,
      name: metaName?.trim().isNotEmpty == true ? metaName!.trim() : 'Покупатель',
      email: authUser.email ?? '',
      bonusBalance: bonus,
      role: UserRole.customer,
      loyaltyCardNumber: 'DJ-$shortId',
      referredBySeller: referred,
    );
  }

  Future<Map<String, dynamic>?> _fetchProfileRow(String userId) async {
    final row = await _supabaseClient
        .from('profiles')
        .select('bonus_balance, referred_by_seller')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) {
      await _supabaseClient
          .from('profiles')
          .upsert({'id': userId}, onConflict: 'id');
      return _supabaseClient
          .from('profiles')
          .select('bonus_balance, referred_by_seller')
          .eq('id', userId)
          .maybeSingle();
    }
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<String?> currentAuthUserId() async {
    return _supabaseClient.auth.currentUser?.id;
  }

  @override
  Future<UserProfile> signInCustomerWithSupabase() async {
    final auth = _supabaseClient.auth;
    if (auth.currentUser == null) {
      try {
        await auth.signInAnonymously();
      } on AuthException catch (error, stackTrace) {
        debugPrint(
          'CloudDatabaseService.signInAnonymously failed: '
          '${error.message} status=${error.statusCode}',
        );
        debugPrint('$stackTrace');
        rethrow;
      } catch (error, stackTrace) {
        debugPrint('CloudDatabaseService.signInAnonymously failed: $error');
        debugPrint('$stackTrace');
        rethrow;
      }
    }
    final authUser = auth.currentUser;
    if (authUser == null) {
      debugPrint(
        'CloudDatabaseService.signInCustomerWithSupabase: '
        'currentUser null after signInAnonymously',
      );
      throw StateError('Supabase auth session missing after sign-in');
    }
    debugPrint(
      'CloudDatabaseService.signInCustomerWithSupabase: session uid=${authUser.id}',
    );
    final row = await _fetchProfileRow(authUser.id);
    return _userProfileFromAuth(authUser, row);
  }

  @override
  Future<void> signOutSupabaseAuth() async {
    await _supabaseClient.auth.signOut();
  }

  static bool isAnonymousAuthUser(User? authUser) {
    if (authUser == null) return false;
    if (authUser.isAnonymous) return true;
    final provider = authUser.appMetadata['provider'];
    return provider == 'anonymous';
  }

  @override
  Future<bool> isCurrentAuthAnonymous() async {
    return isAnonymousAuthUser(_supabaseClient.auth.currentUser);
  }

  @override
  Future<UserProfile> linkOAuthProvider(OAuthLinkProvider provider) async {
    final current = _supabaseClient.auth.currentUser;
    if (current == null) {
      throw StateError('linkOAuthProvider: нет активной сессии');
    }
    if (!isAnonymousAuthUser(current)) {
      throw StateError('linkOAuthProvider: аккаунт уже привязан');
    }

    final oauthProvider = switch (provider) {
      OAuthLinkProvider.google => OAuthProvider.google,
      OAuthLinkProvider.apple => OAuthProvider.apple,
    };

    final completer = Completer<void>();
    late final StreamSubscription<AuthState> subscription;
    subscription = _supabaseClient.auth.onAuthStateChange.listen((data) {
      final linked = data.session?.user;
      if (linked == null) return;
      if (!isAnonymousAuthUser(linked)) {
        if (!completer.isCompleted) completer.complete();
      }
    });

    try {
      final launched = await _supabaseClient.auth.linkIdentity(
        oauthProvider,
        redirectTo: SupabaseConfig.oauthRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('linkOAuthProvider: не удалось открыть OAuth');
      }

      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException(
            'linkOAuthProvider: истекло время ожидания OAuth',
          );
        },
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint(
        'linkOAuthProvider failed: ${error.message} status=${error.statusCode}',
      );
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      await subscription.cancel();
    }

    final refreshed = await refreshCustomerProfileFromCloud();
    if (refreshed == null) {
      throw StateError('linkOAuthProvider: профиль недоступен после link');
    }
    debugPrint(
      'linkOAuthProvider: linked uid=${refreshed.id} provider=$provider',
    );
    return refreshed;
  }

  @override
  Future<UserProfile?> refreshCustomerProfileFromCloud() async {
    final authUser = _supabaseClient.auth.currentUser;
    if (authUser == null) return null;
    final row = await _fetchProfileRow(authUser.id);
    return _userProfileFromAuth(authUser, row);
  }

  @override
  Future<int> fetchBonusBalanceForCurrentUser() async {
    final userId = await currentAuthUserId();
    if (userId == null) return 0;
    final row = await _fetchProfileRow(userId);
    return (row?['bonus_balance'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<SellerReferralApplyResult> applySellerReferralPromo(
    String promoCode,
  ) async {
    try {
      final result = await _supabaseClient.rpc(
        ProfileBonusRpc.applySellerReferralPromo,
        params: {ProfileBonusRpc.promoCodeParam: promoCode},
      );
      if (result is Map) {
        return SellerReferralApplyResult.fromJson(
          Map<String, dynamic>.from(result),
        );
      }
      return const SellerReferralApplyResult(ok: false, errorCode: 'bad_response');
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.applySellerReferralPromo failed: $error');
      debugPrint('$stackTrace');
      return const SellerReferralApplyResult(ok: false, errorCode: 'network');
    }
  }

  @override
  Future<AppMarketingSettings> getAppMarketingSettings() async {
    try {
      final row = await _supabaseClient
          .from('app_settings')
          .select('welcome_bonus_enabled, welcome_bonus_amount')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return AppMarketingSettings.defaults;
      final map = Map<String, dynamic>.from(row);
      return AppMarketingSettings(
        welcomeBonusEnabled: map['welcome_bonus_enabled'] as bool? ?? false,
        welcomeBonusAmountKrw:
            (map['welcome_bonus_amount'] as num?)?.toInt() ?? 0,
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getAppMarketingSettings failed: $error');
      debugPrint('$stackTrace');
      return AppMarketingSettings.defaults;
    }
  }

  @override
  Future<void> saveAppMarketingSettings(
    AppMarketingSettings settings,
    UserRole actorRole,
  ) async {
    _assertAdminWrite(actorRole, action: 'saveAppMarketingSettings');
    try {
      await _supabaseClient.rpc(
        ProfileBonusRpc.saveAppMarketingSettings,
        params: {
          ProfileBonusRpc.welcomeEnabledParam: settings.welcomeBonusEnabled,
          ProfileBonusRpc.welcomeAmountParam: settings.welcomeBonusAmountKrw,
        },
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.saveAppMarketingSettings failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }
}
