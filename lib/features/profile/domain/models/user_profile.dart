/// Роль пользователя в приложении.
enum UserRole {
  guest,
  customer,
  admin,
}

/// Профиль авторизованного пользователя.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.bonusBalance,
    required this.role,
    required this.loyaltyCardNumber,
  });

  final String id;
  final String name;
  final String email;
  final int bonusBalance;
  final UserRole role;
  final String loyaltyCardNumber;

  bool get isAdmin => role == UserRole.admin;

  static const demoGuest = UserProfile(
    id: '',
    name: '',
    email: '',
    bonusBalance: 0,
    role: UserRole.guest,
    loyaltyCardNumber: '',
  );

  static const demoCustomer = UserProfile(
    id: 'user-001',
    name: 'Анна Иванова',
    email: 'anna.ivanova@example.com',
    bonusBalance: 4250,
    role: UserRole.customer,
    loyaltyCardNumber: 'SL-8842-9011',
  );

  static const demoAdmin = UserProfile(
    id: 'admin-001',
    name: 'Владелец Sunlight',
    email: 'owner@sunlight.jewelry',
    bonusBalance: 12800,
    role: UserRole.admin,
    loyaltyCardNumber: 'SL-0001-7777',
  );
}
