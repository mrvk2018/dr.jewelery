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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'bonusBalance': bonusBalance,
        'role': role.name,
        'loyaltyCardNumber': loyaltyCardNumber,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return UserProfile.demoGuest;
    final roleName = json['role'] as String? ?? UserRole.guest.name;
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      bonusBalance: json['bonusBalance'] as int? ?? 0,
      role: UserRole.values.firstWhere(
        (role) => role.name == roleName,
        orElse: () => UserRole.guest,
      ),
      loyaltyCardNumber: json['loyaltyCardNumber'] as String? ?? '',
    );
  }

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
    bonusBalance: 85000,
    role: UserRole.customer,
    loyaltyCardNumber: 'DJ-8842-9011',
  );

  static const demoAdmin = UserProfile(
    id: 'admin-001',
    name: 'Владелец Dr. Jewelry',
    email: 'owner@dr-jewelry.com',
    bonusBalance: 250000,
    role: UserRole.admin,
    loyaltyCardNumber: 'DJ-0001-7777',
  );
}
