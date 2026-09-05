import 'package:flutter/material.dart';

import '../../../../core/services/admin_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../admin/presentation/pages/admin_panel_screen.dart';
import '../../domain/models/order_item.dart';
import '../../domain/models/user_profile.dart';
import '../widgets/profile_auth_views.dart';

/// Экран профиля с гостевым и авторизованным режимами.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isAuthenticated = false;
  UserProfile _user = UserProfile.demoGuest;
  final List<OrderItem> _orders = List<OrderItem>.from(demoProfileOrders);

  void _signInWithGoogle() {
    setState(() {
      isAuthenticated = true;
      _user = UserProfile.demoAdmin;
    });
  }

  void _signInWithApple() {
    setState(() {
      isAuthenticated = true;
      _user = UserProfile.demoCustomer;
    });
  }

  void _logout() {
    setState(() {
      isAuthenticated = false;
      _user = UserProfile.demoGuest;
    });
  }

  Future<void> _openAdminPanel() async {
    if (!_user.isAdmin) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Запрос биометрии...',
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );

    final isVerified = await authenticateAdmin();
    if (!mounted || !isVerified) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminPanelScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: false,
        titleTextStyle: AppTypography.heading(fontSize: 24),
      ),
      body: SafeArea(
        child: isAuthenticated
            ? ProfileAuthenticatedView(
                user: _user,
                orders: _orders,
                onLogout: _logout,
                onOpenAdminPanel: _openAdminPanel,
              )
            : ProfileGuestView(
                onGoogleSignIn: _signInWithGoogle,
                onAppleSignIn: _signInWithApple,
              ),
      ),
    );
  }
}
