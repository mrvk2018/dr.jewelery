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
      final cloudUser = await _database.refreshCustomerProfileFromCloud();
      if (cloudUser != null) {
        isAuthenticated = true;
        user = cloudUser;
        await _persistSession();
      } else {
        final session = await _database.loadProfileSession();
        if (session != null) {
          isAuthenticated = session['isAuthenticated'] as bool? ?? false;
          user = UserProfile.fromJson(
            Map<String, dynamic>.from(session['user'] as Map? ?? const {}),
          );
          if (!isAuthenticated || user.role == UserRole.admin) {
            isAuthenticated = false;
            user = UserProfile.demoGuest;
          } else if (user.role == UserRole.customer) {
            final refreshed = await _database.refreshCustomerProfileFromCloud();
            if (refreshed != null) {
              user = refreshed;
            }
          }
        }
      }

      final stored = await _database.getOrders(user.id);
      _orders
        ..clear()
        ..addAll(stored);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  Future<void> claimAdminAndSignIn(String password) async {
    await _database.claimAdminDevice(password);
    signInAdmin();
  }

  Future<bool> unlockAdmin(String password) async {
    final ok = await _database.verifyAdminPassword(password);
    if (!ok) return false;
    signInAdmin();
    return true;
  }

  Future<void> logout() async {
    await _database.signOutSupabaseAuth();
    isAuthenticated = false;
    user = UserProfile.demoGuest;
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
