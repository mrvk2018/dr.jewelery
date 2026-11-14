import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/catalog/domain/models/catalog_constants.dart';
import '../../features/admin/domain/admin_pos_archive_result.dart';
import '../../features/admin/domain/admin_pos_sale_exception.dart';

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

/// Ключи device-кэша (SharedPreferences) и облачных снимков на устройстве.
abstract final class DatabaseCollections {
  static const products = 'cloud_products_krw_i18n_v2';
  static const feedback = 'cloud_feedback';
  static const sellers = 'cloud_sellers_v1';
  static const cart = 'dj_cart_v1';
  static const favorites = 'dj_favorites_v1';
  static const profileSession = 'dj_profile_session_v1';
  static const adminPinHash = DeviceSecretKeys.adminPinHash;
  static const adminDeviceClaimed = DeviceSecretKeys.adminDeviceClaimed;
  static const posApiKey = DeviceSecretKeys.posApiKey;
  static const tossApiKey = DeviceSecretKeys.tossApiKey;
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
  static const promoCodeParam = 'p_promo_code';
}

/// SECURITY DEFINER RPC для админ-панели (обход RLS при anonymous JWT на клиенте).
abstract final class AdminOrdersRpc {
  static const adminEmail = 'dr.jewelry.korea@gmail.com';
  static const getAllOrders = 'get_all_orders_for_admin';
  static const adminEmailParam = 'p_admin_email';
}

/// RPC ручной продажи в админ-PWA (обход GRANT/RLS на products).
abstract final class AdminCatalogRpc {
  static const markProductSoldManual = 'mark_product_sold_manual';
  static const archiveAdminPosSale = 'archive_admin_pos_sale';
  static const posSaleLinesParam = 'p_lines';
  static const posSellerNameParam = 'p_seller_name';
  static const posPaymentMethodParam = 'p_payment_method';
  static const productIdParam = 'p_product_id';
  static const activateDraftBySku = 'activate_draft_product_by_sku';
  static const activateAllDrafts = 'activate_all_draft_products';
  static const adminGetProductGalleryContextBySku =
      'admin_get_product_gallery_context_by_sku';
  static const adminSetProductAdditionalImages =
      'admin_set_product_additional_images';
  static const deleteDraftBySku = 'delete_draft_product_by_sku';
  static const processProductReturnManual = 'process_product_return_manual';
  static const skuParam = 'p_sku';
  static const additionalImagesParam = 'p_additional_images';
}

abstract final class SellerAdminRpc {
  static const upsertSellerByAdmin = 'upsert_seller_by_admin';
  static const promoCodeParam = 'p_promo_code';
  static const nameParam = 'p_name';
  static const isActiveParam = 'p_is_active';
}

/// RPC витрины и приёмки черновиков (Supabase Pro, схема products SSOT).
abstract final class CatalogFacetedRpc {
  static const getAdvancedFacetedProducts = 'get_advanced_faceted_products';
  static const searchDraftProducts = 'search_draft_products';
  static const metalTagsParam = 'metal_tags';
  static const categoryTagsParam = 'category_tags';
  static const advancedTagsParam = 'advanced_tags';
  static const minPriceParam = 'min_price';
  static const maxPriceParam = 'max_price';
  static const goldGramPriceParam = 'gold_gram_price';
  static const silverGramPriceParam = 'silver_gram_price';
  static const exactWeightParam = 'exact_weight';
  static const skuQueryParam = 'sku_query';
  static const searchQueryParam = 'search_query';
  static const searchSoldProducts = 'search_sold_products';
  static const soldSearchSkuParam = 'p_sku';
  static const soldSearchWeightParam = 'p_weight';
  static const soldSearchDaysParam = 'p_days_limit';
}

/// RPC кассы продавца (Android APK) и перемещений между магазинами.
abstract final class SellerPosRpc {
  static const processPosQrSale = 'process_pos_qr_sale';
  static const initiateProductTransfer = 'initiate_product_transfer';
  static const completeProductTransfer = 'complete_product_transfer';
  static const targetQrParam = 'target_qr';
  static const sellerCodeParam = 's_code';
  static const receiverCodeParam = 'r_code';
  static const toLocationParam = 'to_loc';
  static const discountPercentParam = 'discount_percent';
  static const deliveryFeeParam = 'delivery_fee_krw';
  static const saleTotalParam = 'sale_total_krw';
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

/// Отказ в чтении защищённой коллекции (например, инбокс обращений).
class SecurityException implements Exception {
  SecurityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Контракт доступа к данным витрины, обращений и заказов.
///
/// Production: [CloudDatabaseService] — Supabase Pro (единственный SSOT каталога/заказов).
abstract class DatabaseService {
  /// Единственная фабрика для приложения (облачный режим).
  static DatabaseService create() {
    return CloudDatabaseService(
      supabaseUrl: SupabaseConfig.projectUrl,
      anonKey: SupabaseConfig.anonKey,
    );
  }
  /// Публичная витрина: чтение доступно гостю без авторизации.
  Future<List<ProductItem>> getProducts();

  /// Постраничная витрина с серверной (или локальной) faceted-фильтрацией.
  Future<List<ProductItem>> getProductsAdvancedQuery({
    required int offset,
    int limit = 40,
    String? searchQuery,
    String? skuIlikeQuery,
    List<String>? categories,
    List<String>? metals,
    List<String>? sizes,
    List<String>? inserts,
    List<String>? finenessTokens,
    int? minDiscountPercent,
    bool orderIdDescending = false,
    List<String> categoryIlikePatterns = const [],
    List<String> metalIlikePatterns = const [],
    List<String> insertIlikePatterns = const [],
    int? minSalePriceKrw,
    int? maxSalePriceKrw,
    double? minWeightGrams,
    double? maxWeightGrams,
  });

  /// Постраничный список для админки (все статусы, без витринного RLS-фильтра active).
  Future<List<ProductItem>> getProductsAdminPagedQuery({
    required int offset,
    int limit = 40,
  });

  /// Точечная загрузка карточек по id (избранное, deeplink).
  Future<List<ProductItem>> getProductsByIds(
    List<String> ids, {
    bool activeOnly = true,
  });

  /// Чтение обращений. Только [UserRole.admin] на облаке (RLS SELECT).
  Future<List<FeedbackItem>> getFeedback(UserRole actorRole);

  /// Отправка обращения клиентом/гостем — без авторизации (insert-only).
  Future<void> insertFeedback(FeedbackItem feedback);

  /// Картотека продавцов (промокоды). Только [UserRole.admin].
  Future<List<SellerItem>> getSellers(UserRole actorRole);

  /// Создание/обновление продавца (`upsert_seller_by_admin`, SECURITY DEFINER).
  Future<void> upsertSellerByAdmin({
    required String promoCode,
    required String name,
    required bool isActive,
  });

  /// Заказы пользователя. На облаке: `WHERE user_id = :userId`.
  Future<List<OrderItem>> getOrders(String userId);

  /// Все заказы для админ-панели (`created_at` DESC).
  Future<List<OrderItem>> getAllOrders(UserRole actorRole);

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

  /// Удаление аккаунта и персональных данных (RPC / локальная очистка).
  Future<void> deleteCustomerAccount();

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

  /// Полная выборка `products` для админ-рабочего стола (обход лимита PostgREST 1000).
  Future<List<Map<String, dynamic>>> fetchAllProductRowsForAdminCatalog();

  /// Витрина: RPC [CatalogFacetedRpc.getAdvancedFacetedProducts] (строки `products` as Map).
  Future<List<Map<String, dynamic>>> fetchFacetedProducts({
    List<String>? metalTags,
    List<String>? categoryTags,
    List<String>? advancedTags,
    double? minPrice,
    double? maxPrice,
    double goldGramPrice = 95000.0,
    double silverGramPrice = 3500.0,
    double? exactWeight,
    String? skuQuery,
  });

  /// Приёмка черновиков: RPC [CatalogFacetedRpc.searchDraftProducts] (admin JWT).
  Future<List<Map<String, dynamic>>> searchDraftProducts(String query);

  /// Сленг витрины из `public.jewelry_thesaurus.slang_word`.
  Future<List<String>> fetchJewelryThesaurusSlang();

  /// Активация одного черновика: `stock_quantity` 0 → 1 (admin / RLS).
  Future<bool> activateDraftProductBySku(String sku);

  /// Массовая активация всех черновиков (`stock_quantity = 0` → `1`).
  Future<int> activateAllDraftProducts();

  /// Удаление черновика приёмки (RPC `delete_draft_product_by_sku`).
  Future<bool> deleteDraftProductBySku(String sku);

  /// Поштучное добавление: витрина (`stock_quantity = 1`) или черновик (`0`).
  Future<bool> insertManualProduct({
    required String sku,
    required String name,
    required String metalType,
    required double weightGrams,
    required int price,
    double? sizeValue,
    String gemInserts,
    String notes,
    String? qrCodePayload,
    List<String> additionalImages,
    bool isDraft = false,
    String? manufacturer,
  });

  /// Ручное редактирование карточки на витрине (admin / RLS).
  Future<bool> updateManualProduct({
    required String productId,
    required String sku,
    required String name,
    required String metalType,
    required double weightGrams,
    required int price,
    double? sizeValue,
    String gemInserts,
    String notes,
    String? manufacturer,
    int? stockQuantity,
  });

  /// Обновление поля `notes` по SKU.
  Future<bool> updateProductNotesBySku(String sku, String notes);

  /// Загрузка фото в Storage `product-images` и append в `additional_images` (макс. 4).
  /// Возвращает public URL или null при ошибке / лимите.
  Future<String?> uploadProductAdditionalImage({
    required String sku,
    required Uint8List bytes,
    required String contentType,
  });

  /// Админка: точечная догрузка `additional_images` / `image_url` по SKU.
  Future<Map<String, dynamic>?> fetchProductMediaFieldsBySku(String sku);

  /// Строка `products` для печати бирки после ручного сохранения (в т.ч. `id`).
  Future<Map<String, dynamic>?> fetchProductRowForLabelBySku(String sku);

  /// Админка: замена галереи `additional_images` (+ синхрон `image_url`) по `products.id`.
  Future<bool> updateProductGalleryByProductId({
    required String productId,
    required List<String> additionalImages,
  });

  /// Списание с витрины (`stock_quantity` → `0`).
  Future<bool> writeOffProductBySku(String sku);

  /// Ручная продажа админом: `status = sold`, `stock_quantity = 0` (триггер → sales_history).
  Future<bool> markProductSoldByProductId(String productId);

  /// Мульти-позиционная POS-продажа (только RPC, `SECURITY DEFINER`).
  Future<AdminPosArchiveResult> archiveAdminPosSale({
    required List<Map<String, dynamic>> lines,
    required String sellerName,
    required String paymentMethod,
  });

  /// POS: карточка товара по `qr_code_payload`.
  Future<Map<String, dynamic>?> fetchProductByQrPayload(String qrPayload);

  /// POS: продажа по QR + премия продавца.
  Future<Map<String, dynamic>> processPosQrSale({
    required String qrPayload,
    required String sellerCode,
    required int discountPercent,
    required int deliveryFeeKrw,
    required int saleTotalKrw,
  });

  Future<Map<String, dynamic>> initiateProductTransfer({
    required String qrPayload,
    required String sellerCode,
    required String toLocation,
  });

  Future<Map<String, dynamic>> completeProductTransfer({
    required String qrPayload,
    required String receiverCode,
  });

  /// Смена: `staff_shifts.status` = «На работе» (Realtime для админки).
  Future<String?> startStaffShift(String staffCode);

  /// Смена: статус «Ушла».
  Future<bool> endStaffShift(String shiftId);

  /// Kill-switch: код в `public.sellers.promo_code` и `is_active = true`.
  Future<bool> isSellerStaffActive(String staffCode);

  /// Входящие трансферы в магазин (`product_transfers`, статус «в пути»).
  Future<List<Map<String, dynamic>>> fetchInboundProductTransfers(String toStore);

  /// Архив продаж: RPC [CatalogFacetedRpc.searchSoldProducts] (фильтры на сервере).
  Future<List<Map<String, dynamic>>> searchSoldProducts({
    String? sku,
    double? weight,
    int? daysLimit,
  });

  /// Возврат на витрину: RPC `process_product_return_manual` (сторно + active).
  Future<Map<String, dynamic>> processProductReturn(String sku);
}

/// Облачное хранилище: Supabase (read/write по RLS и RPC).
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

  static List<String> _rpcTagArray(List<String>? tags) {
    if (tags == null || tags.isEmpty) return const [];
    return tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> _mapRpcRows(dynamic response) {
    if (response is! List) return const [];
    final rows = <Map<String, dynamic>>[];
    for (final item in response) {
      if (item is Map) {
        rows.add(Map<String, dynamic>.from(item));
      }
    }
    return rows;
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
  static Map<String, dynamic> productRowToClientJson(Map<String, dynamic> row) =>
      _productRowToClientJson(row);

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
      'images': row['images'] as List<dynamic>?,
      'weightGrams': (row['weight_grams'] as num?)?.toDouble(),
      'catalogStatus': (row['status'] as String?)?.trim() ?? 'active',
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

  List<ProductItem> _mapProductRows(List<dynamic> rows) {
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
          'CloudDatabaseService: skip row ${row['id']}: $error',
        );
        debugPrint('$stackTrace');
      }
    }
    return products;
  }

  PostgrestFilterBuilder<PostgrestList> _applyAdvancedCatalogFilters(
    PostgrestFilterBuilder<PostgrestList> query, {
    String? searchQuery,
    String? skuIlikeQuery,
    List<String>? categories,
    List<String>? metals,
    List<String>? sizes,
    List<String>? inserts,
    List<String>? finenessTokens,
    int? minDiscountPercent,
    List<String> categoryIlikePatterns = const [],
    List<String> metalIlikePatterns = const [],
    List<String> insertIlikePatterns = const [],
    int? minSalePriceKrw,
    int? maxSalePriceKrw,
    double? minWeightGrams,
    double? maxWeightGrams,
  }) {
    var filtered = query.eq('status', 'active').gt('stock_quantity', 0);

    if (minDiscountPercent != null && minDiscountPercent > 0) {
      filtered = filtered.gt('discount_percent', minDiscountPercent - 1);
    }

    if (insertIlikePatterns.isNotEmpty) {
      final orParts = <String>[];
      for (final pattern in insertIlikePatterns) {
        final escaped = pattern.replaceAll(',', r'\,');
        orParts.add('insert.ilike.$escaped');
      }
      filtered = filtered.or(orParts.join(','));
    } else {
      final insertList =
          inserts?.map((i) => i.trim()).where((i) => i.isNotEmpty).toList();
      if (insertList != null && insertList.isNotEmpty) {
        final orParts = <String>[];
        for (final token in insertList) {
          final escaped = token.replaceAll(',', r'\,');
          orParts.add('insert.ilike.%$escaped%');
        }
        filtered = filtered.or(orParts.join(','));
      }
    }

    final priceMin = minSalePriceKrw;
    if (priceMin != null &&
        priceMin > CatalogDesktopFilterBounds.priceMinKrw) {
      filtered = filtered.gte('sale_price', priceMin);
    }
    final priceMax = maxSalePriceKrw;
    if (priceMax != null &&
        priceMax < CatalogDesktopFilterBounds.priceMaxKrw) {
      filtered = filtered.lte('sale_price', priceMax);
    }

    final wMin = minWeightGrams;
    if (wMin != null &&
        wMin > CatalogDesktopFilterBounds.weightMinGrams) {
      filtered = filtered.gte('weight_grams', wMin);
    }
    final wMax = maxWeightGrams;
    if (wMax != null &&
        wMax < CatalogDesktopFilterBounds.weightMaxGrams) {
      filtered = filtered.lte('weight_grams', wMax);
    }

    final skuQ = skuIlikeQuery?.trim();
    if (skuQ != null && skuQ.isNotEmpty) {
      final escaped = skuQ.replaceAll(',', r'\,');
      filtered = filtered.ilike('sku', '%$escaped%');
    } else {
      final q = searchQuery?.trim();
      if (q != null && q.isNotEmpty) {
        final escaped = q.replaceAll(',', r'\,');
        final pattern = '%$escaped%';
        filtered = filtered.or(
          'sku.ilike.$pattern,'
          'category.ilike.$pattern,'
          'metal.ilike.$pattern,'
          'insert.ilike.$pattern,'
          'name->>ru.ilike.$pattern,'
          'name->>ko.ilike.$pattern,'
          'name->>en.ilike.$pattern',
        );
      }
    }

    final finenessList = finenessTokens
        ?.map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (finenessList != null && finenessList.isNotEmpty) {
      final parts = <String>[];
      for (final token in finenessList) {
        final escaped = token.replaceAll(',', r'\,');
        parts.add('metal.ilike.%$escaped%');
        parts.add('sku.ilike.%$escaped%');
      }
      filtered = filtered.or(parts.join(','));
    }

    final sizeList =
        sizes?.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (sizeList != null && sizeList.isNotEmpty) {
      final numericSizes = sizeList
          .map((s) => double.tryParse(s.replaceAll(',', '.')))
          .whereType<double>()
          .toList();
      if (numericSizes.length == 1) {
        filtered = filtered.contains('available_sizes', [numericSizes.first]);
      } else if (numericSizes.isNotEmpty) {
        final orParts = numericSizes
            .map((n) => 'available_sizes.cs.[$n]')
            .join(',');
        filtered = filtered.or(orParts);
      }
    }

    if (categoryIlikePatterns.isNotEmpty) {
      final orParts = categoryIlikePatterns
          .map((p) {
            final escaped = p.replaceAll(',', r'\,');
            return 'category.ilike.$escaped';
          })
          .join(',');
      filtered = filtered.or(orParts);
    }

    if (metalIlikePatterns.isNotEmpty) {
      final orParts = <String>[];
      for (final p in metalIlikePatterns) {
        final escaped = p.replaceAll(',', r'\,');
        orParts.add('metal.ilike.$escaped');
        orParts.add('metal_type.ilike.$escaped');
      }
      filtered = filtered.or(orParts.join(','));
    }

    return filtered;
  }

  @override
  Future<List<ProductItem>> getProductsAdvancedQuery({
    required int offset,
    int limit = 40,
    String? searchQuery,
    String? skuIlikeQuery,
    List<String>? categories,
    List<String>? metals,
    List<String>? sizes,
    List<String>? inserts,
    List<String>? finenessTokens,
    int? minDiscountPercent,
    bool orderIdDescending = false,
    List<String> categoryIlikePatterns = const [],
    List<String> metalIlikePatterns = const [],
    List<String> insertIlikePatterns = const [],
    int? minSalePriceKrw,
    int? maxSalePriceKrw,
    double? minWeightGrams,
    double? maxWeightGrams,
  }) async {
    try {
      final from = offset;
      final to = offset + limit - 1;
      var query = _supabaseClient.from('products').select();
      query = _applyAdvancedCatalogFilters(
        query,
        searchQuery: searchQuery,
        skuIlikeQuery: skuIlikeQuery,
        categories: categories,
        metals: metals,
        sizes: sizes,
        inserts: inserts,
        finenessTokens: finenessTokens,
        minDiscountPercent: minDiscountPercent,
        categoryIlikePatterns: categoryIlikePatterns,
        metalIlikePatterns: metalIlikePatterns,
        insertIlikePatterns: insertIlikePatterns,
        minSalePriceKrw: minSalePriceKrw,
        maxSalePriceKrw: maxSalePriceKrw,
        minWeightGrams: minWeightGrams,
        maxWeightGrams: maxWeightGrams,
      );
      final rows = await query
          .order('id', ascending: !orderIdDescending)
          .range(from, to);
      return _mapProductRows(rows);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getProductsAdvancedQuery failed: $error');
      debugPrint('$stackTrace');
      return [];
    }
  }

  @override
  Future<List<ProductItem>> getProductsAdminPagedQuery({
    required int offset,
    int limit = 40,
  }) async {
    try {
      final from = offset;
      final to = offset + limit - 1;
      final rows = await _supabaseClient
          .from('products')
          .select()
          .order('id', ascending: true)
          .range(from, to);
      return _mapProductRows(rows);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getProductsAdminPagedQuery failed: $error');
      debugPrint('$stackTrace');
      return [];
    }
  }

  @override
  Future<List<ProductItem>> getProductsByIds(
    List<String> ids, {
    bool activeOnly = true,
  }) async {
    final unique =
        ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return [];

    try {
      const chunkSize = 200;
      final results = <ProductItem>[];
      for (var i = 0; i < unique.length; i += chunkSize) {
        final chunk = unique.sublist(
          i,
          i + chunkSize > unique.length ? unique.length : i + chunkSize,
        );
        var query = _supabaseClient.from('products').select().inFilter('id', chunk);
        if (activeOnly) {
          query = query.eq('status', 'active');
        }
        final rows = await query;
        results.addAll(_mapProductRows(rows));
      }
      results.sort((a, b) => a.id.compareTo(b.id));
      return results;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.getProductsByIds failed: $error');
      debugPrint('$stackTrace');
      return [];
    }
  }

  @override
  Future<List<ProductItem>> getProducts() async {
    try {
      final rows = await _supabaseClient
          .from('products')
          .select()
          .range(0, 4999);
      final products = _mapProductRows(rows);
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
  Future<void> upsertSellerByAdmin({
    required String promoCode,
    required String name,
    required bool isActive,
  }) async {
    final code = SellerItem.normalizePromoCode(promoCode);
    final trimmedName = name.trim();
    if (code.isEmpty || trimmedName.isEmpty) {
      throw StateError('Укажите имя и код сотрудника');
    }
    try {
      final result = await _supabaseClient.rpc(
        SellerAdminRpc.upsertSellerByAdmin,
        params: {
          SellerAdminRpc.promoCodeParam: code,
          SellerAdminRpc.nameParam: trimmedName,
          SellerAdminRpc.isActiveParam: isActive,
        },
      );
      final ok = result == true ||
          (result is Map && (result['ok'] == true || result['success'] == true));
      if (!ok) {
        throw StateError('Сервер не подтвердил сохранение');
      }
      try {
        await getSellers(UserRole.admin);
      } catch (_) {}
    } on PostgrestException catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.upsertSellerByAdmin failed: $error');
      debugPrint('$stackTrace');
      final detail = error.message.trim();
      throw StateError(detail.isEmpty ? 'Ошибка сохранения на сервере' : detail);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.upsertSellerByAdmin failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
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

  @override
  Future<void> deleteCustomerAccount() async {
    if (_supabaseClient.auth.currentUser == null) {
      throw StateError('deleteCustomerAccount: нет активной сессии');
    }
    try {
      await _supabaseClient.rpc('delete_my_account');
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.deleteCustomerAccount failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      await signOutSupabaseAuth();
    }
    await saveCartSnapshot({});
    await saveFavoriteIds([]);
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

  static const _postgrestPageSize = 1000;

  static const _adminCatalogProductColumns =
      'id, sku, stock_quantity, weight_grams, size_value, metal_type, '
      'gem_inserts, notes, additional_images, image_url, name, price, '
      'sale_price, manufacturer, status, metal, insert';

  @override
  Future<List<Map<String, dynamic>>> fetchAllProductRowsForAdminCatalog() async {
    final all = <Map<String, dynamic>>[];
    var from = 0;
    try {
      for (;;) {
        final to = from + _postgrestPageSize - 1;
        final rows = await _supabaseClient
            .from('products')
            .select(_adminCatalogProductColumns)
            .order('updated_at', ascending: false)
            .range(from, to);
        if (rows.isEmpty) break;
        for (final row in rows) {
          all.add(Map<String, dynamic>.from(row));
        }
        if (rows.length < _postgrestPageSize) break;
        from += _postgrestPageSize;
      }
      return all;
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.fetchAllProductRowsForAdminCatalog failed: $error',
      );
      debugPrint('$stackTrace');
      return all;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFacetedProducts({
    List<String>? metalTags,
    List<String>? categoryTags,
    List<String>? advancedTags,
    double? minPrice,
    double? maxPrice,
    double goldGramPrice = 95000.0,
    double silverGramPrice = 3500.0,
    double? exactWeight,
    String? skuQuery,
  }) async {
    try {
      final skuTrimmed = skuQuery?.trim();
      final response = await _supabaseClient.rpc(
        CatalogFacetedRpc.getAdvancedFacetedProducts,
        params: {
          CatalogFacetedRpc.metalTagsParam: _rpcTagArray(metalTags),
          CatalogFacetedRpc.categoryTagsParam: _rpcTagArray(categoryTags),
          CatalogFacetedRpc.advancedTagsParam: _rpcTagArray(advancedTags),
          CatalogFacetedRpc.minPriceParam: minPrice,
          CatalogFacetedRpc.maxPriceParam: maxPrice,
          CatalogFacetedRpc.goldGramPriceParam: goldGramPrice,
          CatalogFacetedRpc.silverGramPriceParam: silverGramPrice,
          CatalogFacetedRpc.exactWeightParam: exactWeight,
          CatalogFacetedRpc.skuQueryParam:
              (skuTrimmed == null || skuTrimmed.isEmpty) ? null : skuTrimmed,
        },
      );
      return _mapRpcRows(response);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.fetchFacetedProducts failed: $error');
      debugPrint('$stackTrace');
      return const [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchDraftProducts(String query) async {
    try {
      final response = await _supabaseClient.rpc(
        CatalogFacetedRpc.searchDraftProducts,
        params: {CatalogFacetedRpc.searchQueryParam: query},
      );
      return _mapRpcRows(response);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.searchDraftProducts failed: $error');
      debugPrint('$stackTrace');
      return const [];
    }
  }

  @override
  Future<List<String>> fetchJewelryThesaurusSlang() async {
    try {
      final rows = await _supabaseClient
          .from('jewelry_thesaurus')
          .select('slang_word')
          .order('slang_word');
      final words = <String>[];
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final word = map['slang_word']?.toString().trim() ?? '';
        if (word.isNotEmpty) words.add(word);
      }
      return words;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.fetchJewelryThesaurusSlang failed: $error');
      debugPrint('$stackTrace');
      return const [];
    }
  }

  @override
  Future<bool> activateDraftProductBySku(String sku) async {
    final normalized = sku.trim();
    if (normalized.isEmpty) return false;
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.activateDraftBySku,
        params: {
          AdminCatalogRpc.skuParam: normalized,
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
        },
      );
      return result == true;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.activateDraftProductBySku failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<int> activateAllDraftProducts() async {
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.activateAllDrafts,
        params: {AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail},
      );
      if (result is num) return result.toInt();
      return int.tryParse(result?.toString() ?? '') ?? 0;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.activateAllDraftProducts failed: $error');
      debugPrint('$stackTrace');
      return 0;
    }
  }

  @override
  Future<bool> deleteDraftProductBySku(String sku) async {
    final normalized = sku.trim();
    if (normalized.isEmpty) return false;
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.deleteDraftBySku,
        params: {
          AdminCatalogRpc.skuParam: normalized,
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
        },
      );
      return result == true;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.deleteDraftProductBySku failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// Локализованное имя для колонки `products.name` (jsonb object).
  static Map<String, dynamic> _manualProductNameJson(String displayName) {
    final text = displayName.trim();
    if (text.isEmpty) {
      return <String, dynamic>{'ru': ''};
    }
    return <String, dynamic>{'ru': text, 'ko': text};
  }

  static void _logPostgrestInsertFailure(Object error, StackTrace stackTrace) {
    debugPrint('CloudDatabaseService.insertManualProduct failed: $error');
    if (error is PostgrestException) {
      debugPrint(
        'Supabase Error Details: ${error.message}, '
        'Hint: ${error.details}, Code: ${error.code}',
      );
    }
    debugPrint('$stackTrace');
  }

  @override
  Future<bool> insertManualProduct({
    required String sku,
    required String name,
    required String metalType,
    required double weightGrams,
    required int price,
    double? sizeValue,
    String gemInserts = '',
    String notes = '',
    String? qrCodePayload,
    List<String> additionalImages = const [],
    bool isDraft = false,
    String? manufacturer,
  }) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return false;
    final priceKrw = price.clamp(0, 999999999);
    final displayName = name.trim();
    final metalLabel = metalType.trim();
    final gem = gemInserts.trim();
    try {
      // Never send `id` — Postgres generates UUID. Do not map SKU into uuid columns
      // (e.g. mis-typed `qr_code_payload`); POS falls back to `sku` when QR is null.
      final payload = <String, dynamic>{
        'sku': normalizedSku,
        'name': _manualProductNameJson(displayName),
        'description': <String, dynamic>{},
        'metal': metalLabel,
        'metal_type': metalLabel,
        'category': displayName.isEmpty ? 'manual' : displayName,
        'insert': gem,
        'weight_grams': weightGrams,
        'gem_inserts': gem,
        'notes': notes.trim(),
        'manufacturer': manufacturer?.trim() ?? '',
        'price': priceKrw,
        'sale_price': priceKrw,
        'old_price': priceKrw,
        'status': isDraft ? 'hidden' : 'active',
        'additional_images': additionalImages,
      };
      payload['stock_quantity'] = isDraft ? 0 : 1;
      if (sizeValue != null) {
        payload['size_value'] = sizeValue;
      }
      final qr = qrCodePayload?.trim();
      if (qr != null && qr.isNotEmpty) {
        payload['qr_code_payload'] = qr;
      }
      await _supabaseClient.from('products').insert(payload);
      return true;
    } catch (error, stackTrace) {
      _logPostgrestInsertFailure(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<bool> updateManualProduct({
    required String productId,
    required String sku,
    required String name,
    required String metalType,
    required double weightGrams,
    required int price,
    double? sizeValue,
    String gemInserts = '',
    String notes = '',
    String? manufacturer,
    int? stockQuantity,
  }) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return false;
    final priceKrw = price.clamp(0, 999999999);

    final displayName = name.trim();
    final metalLabel = metalType.trim();
    final gem = gemInserts.trim();
    final patch = <String, dynamic>{
      'name': _manualProductNameJson(displayName),
      'metal': metalLabel,
      'metal_type': metalLabel,
      'category': displayName.isEmpty ? 'manual' : displayName,
      'insert': gem,
      'weight_grams': weightGrams,
      'gem_inserts': gem,
      'notes': notes.trim(),
      'manufacturer': manufacturer?.trim() ?? '',
      'price': priceKrw,
      'sale_price': priceKrw,
      'old_price': priceKrw,
    };
    if (sizeValue != null) {
      patch['size_value'] = sizeValue;
    }
    if (stockQuantity != null) {
      patch['stock_quantity'] = stockQuantity.clamp(0, 999999);
    }

    try {
      final id = productId.trim();
      if (id.isNotEmpty) {
        final rows = await _supabaseClient
            .from('products')
            .update(patch)
            .eq('id', id)
            .select('sku');
        if (rows.isNotEmpty) return true;
      }

      final rows = await _supabaseClient
          .from('products')
          .update(patch)
          .eq('sku', normalizedSku)
          .select('sku');
      return rows.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.updateManualProduct failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> updateProductNotesBySku(String sku, String notes) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return false;
    try {
      final rows = await _supabaseClient
          .from('products')
          .update({'notes': notes.trim()})
          .eq('sku', normalizedSku)
          .select('sku');
      return rows.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.updateProductNotesBySku failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  static const _productImagesBucket = 'product-images';
  static const _productImagesFolder = 'products';
  static const _gallerySlotSuffixes = ['', '_1', '_2', '_3'];
  static const _productImageMaxSidePx = 1600;
  static const _productImageWebpContentType = 'image/webp';

  static String _safeStorageSku(String sku) {
    return sku.replaceAll(RegExp(r'[^\w.-]+'), '_');
  }

  static String _extensionForContentType(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('webp')) return 'webp';
    if (lower.contains('png')) return 'png';
    return 'jpg';
  }

  Future<Map<String, dynamic>?> _adminProductGalleryContextBySku(String sku) async {
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.adminGetProductGalleryContextBySku,
        params: {
          AdminCatalogRpc.skuParam: sku,
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
        },
      );
      if (result is! Map) return null;
      final map = Map<String, dynamic>.from(result);
      if (map['ok'] != true) return null;
      return map;
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService._adminProductGalleryContextBySku failed: $error',
      );
      debugPrint('$stackTrace');
      return null;
    }
  }

  Future<bool> _adminSetProductAdditionalImages(
    String productId,
    List<String> additionalImages,
  ) async {
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.adminSetProductAdditionalImages,
        params: {
          AdminCatalogRpc.productIdParam: productId,
          AdminCatalogRpc.additionalImagesParam: additionalImages,
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
        },
      );
      return result == true;
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService._adminSetProductAdditionalImages failed: $error',
      );
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// JPEG/PNG с picker → WebP (как [sync.js] / sharp для bucket `product-images`).
  static Uint8List? _productImageBytesAsWebp(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;

      final oriented = img.bakeOrientation(decoded);
      final w = oriented.width;
      final h = oriented.height;
      img.Image toEncode = oriented;
      if (w > _productImageMaxSidePx || h > _productImageMaxSidePx) {
        final scale = _productImageMaxSidePx / (w > h ? w : h);
        toEncode = img.copyResize(
          oriented,
          width: (w * scale).round(),
          height: (h * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      return Uint8List.fromList(img.encodeWebP(toEncode));
    } catch (e) {
      print('!!! WEB CONVERTER FAILED, FALLBACK TO ORIGINAL !!!: $e');
      return null;
    }
  }

  @override
  Future<String?> uploadProductAdditionalImage({
    required String sku,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty || bytes.isEmpty) {
      print(
        '!!! UPLOAD FAILED AT: empty sku or bytes '
        '(sku="$normalizedSku", bytes=${bytes.length})',
      );
      return null;
    }

    try {
      final existing = await _adminProductGalleryContextBySku(normalizedSku);
      if (existing == null) {
        print(
          '!!! UPLOAD FAILED AT: rows empty (no product for sku=$normalizedSku, RLS/hidden?)',
        );
        return null;
      }

      final productId = existing['id']?.toString().trim() ?? '';
      if (productId.isEmpty) {
        print('!!! UPLOAD FAILED AT: productId is null or empty');
        return null;
      }

      final currentRaw = existing['additional_images'];
      final current = currentRaw is List
          ? currentRaw.map((e) => e.toString()).where((u) => u.isNotEmpty).toList()
          : <String>[];
      if (current.length >= ProductItem.maxGalleryImages) {
        print(
          '!!! UPLOAD FAILED AT: gallery limit reached '
          '(${current.length}/${ProductItem.maxGalleryImages})',
        );
        return null;
      }

      final uploadContentType =
          contentType.trim().isNotEmpty ? contentType.trim() : 'image/jpeg';
      var uploadBytes = bytes;
      var uploadMime = uploadContentType;
      var fileExt = _extensionForContentType(uploadContentType);

      try {
        final webpBytes = _productImageBytesAsWebp(bytes);
        if (webpBytes != null && webpBytes.isNotEmpty) {
          uploadBytes = webpBytes;
          uploadMime = _productImageWebpContentType;
          fileExt = 'webp';
        }
      } catch (e) {
        print('!!! WEB CONVERTER FAILED, FALLBACK TO ORIGINAL !!!: $e');
      }

      final slot = current.length;
      final safeSku = _safeStorageSku(normalizedSku);
      final suffix = _gallerySlotSuffixes[slot];
      final objectPath = '$_productImagesFolder/$safeSku$suffix.$fileExt';

      await _supabaseClient.storage.from(_productImagesBucket).uploadBinary(
            objectPath,
            uploadBytes,
            fileOptions: FileOptions(
              contentType: uploadMime,
              upsert: true,
            ),
          );

      final publicUrl =
          _supabaseClient.storage.from(_productImagesBucket).getPublicUrl(objectPath);
      if (publicUrl.trim().isEmpty) {
        print('!!! UPLOAD FAILED AT: publicUrl empty (objectPath=$objectPath)');
        return null;
      }

      final versionedUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      final nextImages = [...current, versionedUrl];

      final saved = await _adminSetProductAdditionalImages(productId, nextImages);
      if (!saved) {
        print(
          '!!! UPLOAD FAILED AT: admin_set_product_additional_images '
          '(productId=$productId)',
        );
        return null;
      }
      return versionedUrl;
    } catch (e, stackTrace) {
      print('!!! UPLOAD ERROR !!!: $e');
      if (e is StorageException) {
        print('!!! STORAGE ERROR MESSAGE !!!: ${e.message}');
        print('!!! STORAGE ERROR STATUS !!!: ${e.statusCode}');
      }
      print('STACKTRACE: $stackTrace');
      debugPrint('CloudDatabaseService.uploadProductAdditionalImage failed: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchProductRowForLabelBySku(String sku) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return null;
    try {
      final row = await _supabaseClient
          .from('products')
          .select(_adminCatalogProductColumns)
          .eq('sku', normalizedSku)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.fetchProductRowForLabelBySku failed: $error',
      );
      debugPrint('$stackTrace');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchProductMediaFieldsBySku(String sku) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return null;
    try {
      final ctx = await _adminProductGalleryContextBySku(normalizedSku);
      if (ctx == null) return null;
      return {
        'additional_images': ctx['additional_images'],
        'image_url': ctx['image_url'],
      };
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.fetchProductMediaFieldsBySku failed: $error',
      );
      debugPrint('$stackTrace');
      return null;
    }
  }

  @override
  Future<bool> updateProductGalleryByProductId({
    required String productId,
    required List<String> additionalImages,
  }) async {
    final id = productId.trim();
    if (id.isEmpty) return false;
    final nextImages = additionalImages
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .take(ProductItem.maxGalleryImages)
        .toList();
    try {
      return await _adminSetProductAdditionalImages(id, nextImages);
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.updateProductGalleryByProductId failed: $error',
      );
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> writeOffProductBySku(String sku) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return false;
    try {
      final rows = await _supabaseClient
          .from('products')
          .update({'stock_quantity': 0})
          .eq('sku', normalizedSku)
          .select('sku');
      return rows.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.writeOffProductBySku failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> markProductSoldByProductId(String productId) async {
    final id = productId.trim();
    if (id.isEmpty) return false;
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.markProductSoldManual,
        params: {
          AdminCatalogRpc.productIdParam: id,
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
        },
      );
      if (result is bool) return result;
      if (result is Map) {
        final ok = result['ok'];
        if (ok is bool) return ok;
      }
      return result == true;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.markProductSoldByProductId failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<AdminPosArchiveResult> archiveAdminPosSale({
    required List<Map<String, dynamic>> lines,
    required String sellerName,
    required String paymentMethod,
  }) async {
    if (lines.isEmpty) {
      return AdminPosArchiveResult.failure(
        const AdminPosSaleException(
          AdminPosSaleFailure.validation,
          message: 'Корзина пуста',
        ),
      );
    }
    final seller = sellerName.trim();
    final payment = paymentMethod.trim();
    if (seller.isEmpty || payment.isEmpty) {
      return AdminPosArchiveResult.failure(
        const AdminPosSaleException(
          AdminPosSaleFailure.validation,
          message: 'Укажите продавца и способ оплаты',
        ),
      );
    }

    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.archiveAdminPosSale,
        params: {
          AdminCatalogRpc.posSaleLinesParam: lines,
          AdminCatalogRpc.posSellerNameParam: seller,
          AdminCatalogRpc.posPaymentMethodParam: payment,
        },
      );
      if (result == null || result == true) {
        return AdminPosArchiveResult.success();
      }
      final map = _rpcJsonMap(result);
      final ok = map['ok'] == true || map['success'] == true;
      if (!ok && map['raw'] == true) {
        return AdminPosArchiveResult.success();
      }
      if (!ok) {
        final message = map['error']?.toString() ?? map['message']?.toString();
        final failure = AdminPosSaleException.classify(
          message ?? 'rpc_failed',
          rpcMessage: message,
        );
        return AdminPosArchiveResult.failure(
          AdminPosSaleException(failure, message: message),
        );
      }
      final orderId = map['order_id']?.toString();
      return AdminPosArchiveResult.success(orderId: orderId);
    } on PostgrestException catch (error) {
      debugPrint('CloudDatabaseService.archiveAdminPosSale: $error');
      final failure = AdminPosSaleException.classify(error, rpcMessage: error.message);
      return AdminPosArchiveResult.failure(
        AdminPosSaleException(failure, message: error.message),
      );
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.archiveAdminPosSale failed: $error');
      debugPrint('$stackTrace');
      final failure = AdminPosSaleException.classify(error);
      return AdminPosArchiveResult.failure(AdminPosSaleException(failure));
    }
  }

  static Map<String, dynamic> _rpcJsonMap(dynamic result) {
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'ok': result == true, 'raw': result};
  }

  @override
  Future<Map<String, dynamic>?> fetchProductByQrPayload(String qrPayload) async {
    final qr = qrPayload.trim();
    if (qr.isEmpty) return null;
    try {
      final row = await _supabaseClient
          .from('products')
          .select(
            'id, sku, metal_type, weight_grams, size_value, gem_inserts, '
            'notes, sale_price, qr_code_payload, store_location, '
            'product_status, stock_quantity, is_customer_order',
          )
          .eq('qr_code_payload', qr)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.fetchProductByQrPayload failed: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> processPosQrSale({
    required String qrPayload,
    required String sellerCode,
    required int discountPercent,
    required int deliveryFeeKrw,
    required int saleTotalKrw,
  }) async {
    try {
      final result = await _supabaseClient.rpc(
        SellerPosRpc.processPosQrSale,
        params: {
          SellerPosRpc.targetQrParam: qrPayload.trim(),
          SellerPosRpc.sellerCodeParam: sellerCode.trim(),
          SellerPosRpc.discountPercentParam: discountPercent,
          SellerPosRpc.deliveryFeeParam: deliveryFeeKrw,
          SellerPosRpc.saleTotalParam: saleTotalKrw,
        },
      );
      return _rpcJsonMap(result);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.processPosQrSale failed: $error');
      debugPrint('$stackTrace');
      return {'ok': false, 'error': error.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> initiateProductTransfer({
    required String qrPayload,
    required String sellerCode,
    required String toLocation,
  }) async {
    try {
      final result = await _supabaseClient.rpc(
        SellerPosRpc.initiateProductTransfer,
        params: {
          SellerPosRpc.targetQrParam: qrPayload.trim(),
          SellerPosRpc.sellerCodeParam: sellerCode.trim(),
          SellerPosRpc.toLocationParam: toLocation.trim().toUpperCase(),
        },
      );
      return _rpcJsonMap(result);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.initiateProductTransfer failed: $error');
      debugPrint('$stackTrace');
      return {'ok': false, 'error': error.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> completeProductTransfer({
    required String qrPayload,
    required String receiverCode,
  }) async {
    try {
      final result = await _supabaseClient.rpc(
        SellerPosRpc.completeProductTransfer,
        params: {
          SellerPosRpc.targetQrParam: qrPayload.trim(),
          SellerPosRpc.receiverCodeParam: receiverCode.trim(),
        },
      );
      return _rpcJsonMap(result);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.completeProductTransfer failed: $error');
      debugPrint('$stackTrace');
      return {'ok': false, 'error': error.toString()};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchSoldProducts({
    String? sku,
    double? weight,
    int? daysLimit,
  }) async {
    final trimmedSku = sku?.trim();
    final skuParam =
        (trimmedSku == null || trimmedSku.isEmpty) ? null : trimmedSku;

    try {
      final response = await _supabaseClient.rpc(
        CatalogFacetedRpc.searchSoldProducts,
        params: {
          CatalogFacetedRpc.soldSearchSkuParam: skuParam,
          CatalogFacetedRpc.soldSearchWeightParam: weight,
          CatalogFacetedRpc.soldSearchDaysParam: daysLimit,
        },
      );
      return _mapRpcRows(response);
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.searchSoldProducts failed: $error');
      debugPrint('$stackTrace');
      return const [];
    }
  }

  @override
  Future<Map<String, dynamic>> processProductReturn(String sku) async {
    final normalized = sku.trim();
    if (normalized.isEmpty) {
      throw StateError('SKU пустой');
    }
    try {
      final result = await _supabaseClient.rpc(
        AdminCatalogRpc.processProductReturnManual,
        params: {
          AdminCatalogRpc.skuParam: normalized,
          AdminOrdersRpc.adminEmailParam: AdminOrdersRpc.adminEmail,
        },
      );
      final map = _rpcJsonMap(result);
      final ok = map['ok'] == true;
      if (!ok) {
        final err = map['error']?.toString() ?? 'unknown';
        throw StateError(_returnErrorMessage(err, normalized));
      }
      return map;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.processProductReturn failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  static String _returnErrorMessage(String code, String sku) {
    return switch (code) {
      'empty_sku' => 'SKU пустой',
      'forbidden' => 'Нет прав на возврат',
      'product_not_found' => 'Товар $sku не найден',
      'product_not_sold' => 'Товар $sku не в статусе продан',
      'sale_not_found' => 'Запись продажи для $sku не найдена',
      'already_returned' => 'Возврат для $sku уже оформлен',
      _ => 'Возврат не выполнен: $code',
    };
  }

  @override
  Future<bool> isSellerStaffActive(String staffCode) async {
    final code = staffCode.trim().toUpperCase();
    if (code.isEmpty) return false;
    try {
      final row = await _supabaseClient
          .from('sellers')
          .select('promo_code, is_active')
          .eq('promo_code', code)
          .maybeSingle();
      if (row == null) return false;
      return row['is_active'] as bool? ?? false;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.isSellerStaffActive failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchInboundProductTransfers(
    String toStore,
  ) async {
    final store = toStore.trim().toUpperCase();
    if (store.isEmpty) return const [];
    try {
      final rows = await _supabaseClient
          .from('product_transfers')
          .select(
            'id, sku, qr_code_payload, from_store, to_store, status, '
            'sender_code, weight_grams, metal_type',
          )
          .eq('to_store', store)
          .inFilter('status', ['in_transit', 'pending', 'sent', 'В пути']);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (error, stackTrace) {
      debugPrint(
        'CloudDatabaseService.fetchInboundProductTransfers failed: $error',
      );
      debugPrint('$stackTrace');
      return const [];
    }
  }

  @override
  Future<String?> startStaffShift(String staffCode) async {
    final code = staffCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    try {
      final row = await _supabaseClient
          .from('staff_shifts')
          .insert({
            'staff_code': code,
            'status': 'На работе',
          })
          .select('id')
          .single();
      return row['id']?.toString();
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.startStaffShift failed: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  @override
  Future<bool> endStaffShift(String shiftId) async {
    final id = shiftId.trim();
    if (id.isEmpty) return false;
    try {
      final rows = await _supabaseClient
          .from('staff_shifts')
          .update({'status': 'Ушла'})
          .eq('id', id)
          .select('id');
      return rows.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('CloudDatabaseService.endStaffShift failed: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }
}
