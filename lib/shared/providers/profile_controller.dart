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

  List<OrderItem> get orders => List.unmodifiable(_orders);

  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _ensureSupabaseCustomerSession();
      final stored = await _database.getOrders(user.id);
      _orders
        ..clear()
        ..addAll(stored);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Восстанавливает Supabase-сессию или создаёт silent anonymous JWT.
  Future<void> _ensureSupabaseCustomerSession() async {
    var cloudUser = await _database.refreshCustomerProfileFromCloud();
    cloudUser ??= await _database.signInCustomerWithSupabase();
    isAuthenticated = true;
    user = cloudUser;
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
