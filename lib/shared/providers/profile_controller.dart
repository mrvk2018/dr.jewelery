import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../../features/profile/domain/models/order_item.dart';
import '../../features/profile/domain/models/user_profile.dart';

/// Сессия профиля и история заказов с локальной персистентностью.
class ProfileController extends ChangeNotifier {
  ProfileController(this._database);

  final DatabaseService _database;
  bool isAuthenticated = false;
  UserProfile user = UserProfile.demoGuest;
  final List<OrderItem> _orders = [];
  bool _isLoading = false;
  bool isAnonymousAccount = false;
  bool isLinkingSocialAccount = false;

  List<OrderItem> get orders => List.unmodifiable(_orders);

  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _ensureSupabaseCustomerSession();
      await _syncAnonymousFlag();
      final stored = await _database.getOrders(user.id);
      _orders
        ..clear()
        ..addAll(stored);
    } catch (error, stackTrace) {
      debugPrint('ProfileController.load failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Восстанавливает Supabase-сессию или создаёт silent anonymous JWT.
  Future<void> _ensureSupabaseCustomerSession() async {
    try {
      final refreshed = await _database.refreshCustomerProfileFromCloud();
      if (refreshed != null) {
        isAuthenticated = true;
        user = refreshed;
        await _persistSession();
        return;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ProfileController: refreshCustomerProfile failed, reset auth: $error',
      );
      debugPrint('$stackTrace');
      await _database.signOutSupabaseAuth();
    }

    final cloudUser = await _database.signInCustomerWithSupabase();
    isAuthenticated = true;
    user = cloudUser;
    await _syncAnonymousFlag();
    await _persistSession();
  }

  Future<void> signInCustomer() async {
    try {
      user = await _database.signInCustomerWithSupabase();
      isAuthenticated = true;
      notifyListeners();
      await _persistSession();
    } catch (error, stackTrace) {
      debugPrint('ProfileController.signInCustomer failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<void> linkGoogleAccount() =>
      _linkSocialAccount(OAuthLinkProvider.google);

  Future<void> linkAppleAccount() =>
      _linkSocialAccount(OAuthLinkProvider.apple);

  Future<void> _linkSocialAccount(OAuthLinkProvider provider) async {
    if (isLinkingSocialAccount) return;
    isLinkingSocialAccount = true;
    notifyListeners();
    try {
      user = await _database.linkOAuthProvider(provider);
      isAuthenticated = true;
      await _syncAnonymousFlag();
      notifyListeners();
      await _persistSession();
    } catch (error, stackTrace) {
      debugPrint('ProfileController._linkSocialAccount failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      isLinkingSocialAccount = false;
      notifyListeners();
    }
  }

  Future<void> _syncAnonymousFlag() async {
    isAnonymousAccount = await _database.isCurrentAuthAnonymous();
  }

  /// Обновляет баланс и реферал из Supabase (после checkout / RPC).
  Future<void> refreshWalletFromCloud() async {
    final refreshed = await _database.refreshCustomerProfileFromCloud();
    if (refreshed == null) return;
    user = refreshed;
    notifyListeners();
    await _persistSession();
  }

  void signInAdmin() {
    isAuthenticated = true;
    user = UserProfile.demoAdmin;
    notifyListeners();
  }

  Future<bool> isAdminDeviceClaimed() => _database.isAdminDeviceClaimed();

  Future<void> completeAdminFirstClaim(String pin) async {
    await _database.claimAdminDevicePin(pin);
    signInAdmin();
  }

  Future<bool> unlockAdminWithPin(String pin) async {
    final ok = await _database.verifyAdminPin(pin);
    if (!ok) return false;
    signInAdmin();
    return true;
  }

  Future<bool> verifyAdminPinForPanel(String pin) =>
      _database.verifyAdminPin(pin);

  Future<void> logout() async {
    if (user.isAdmin) {
      final refreshed = await _database.refreshCustomerProfileFromCloud();
      if (refreshed != null) {
        user = refreshed;
      } else {
        await _ensureSupabaseCustomerSession();
      }
      isAuthenticated = true;
      notifyListeners();
      await _persistSession();
      return;
    }

    await _database.signOutSupabaseAuth();
    await _ensureSupabaseCustomerSession();
    notifyListeners();
  }

  /// Удаление аккаунта (Supabase RPC + новая anonymous-сессия).
  Future<void> deleteAccount() async {
    if (user.isAdmin) {
      throw StateError('deleteAccount: недоступно в режиме администратора');
    }

    await _database.deleteCustomerAccount();
    _orders.clear();
    await _ensureSupabaseCustomerSession();
    isAuthenticated = true;
    notifyListeners();
    await _persistSession();
  }

  void addOrder(OrderItem order) {
    _orders.insert(0, order);
    notifyListeners();
    unawaited(_database.createOrder(order));
  }

  Future<void> _persistSession() {
    return _database.saveProfileSession({
      'isAuthenticated': isAuthenticated,
      'user': user.toJson(),
    });
  }
}
