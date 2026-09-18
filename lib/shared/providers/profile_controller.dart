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
      final session = await _database.loadProfileSession();
      if (session != null) {
        isAuthenticated = session['isAuthenticated'] as bool? ?? false;
        user = UserProfile.fromJson(
          Map<String, dynamic>.from(session['user'] as Map? ?? const {}),
        );
        if (!isAuthenticated || user.role == UserRole.admin) {
          // Админ-роль не восстанавливаем с диска: только runtime-сессия.
          isAuthenticated = false;
          user = UserProfile.demoGuest;
        }
      }

      final stored = await _database.getOrders(user.id);
      _orders
        ..clear()
        ..addAll(stored);

      if (_orders.isEmpty) {
        for (final order in demoProfileOrders) {
          await _database.createOrder(order);
          _orders.add(order);
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void signInCustomer() {
    isAuthenticated = true;
    user = UserProfile.demoCustomer;
    notifyListeners();
    unawaited(_persistSession());
  }

  void signInAdmin() {
    isAuthenticated = true;
    user = UserProfile.demoAdmin;
    notifyListeners();
    // First Claim: админ живёт только в текущей сессии, не пишем на диск.
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

  void logout() {
    isAuthenticated = false;
    user = UserProfile.demoGuest;
    notifyListeners();
    unawaited(_persistSession());
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
