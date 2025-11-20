import 'package:cloud_firestore/cloud_firestore.dart';

enum AdminRole {
  superAdmin,
  cityAdmin,
  moderator,
}

extension AdminRoleExtension on AdminRole {
  String get displayName {
    switch (this) {
      case AdminRole.superAdmin:
        return 'Super Admin';
      case AdminRole.cityAdmin:
        return 'City Admin';
      case AdminRole.moderator:
        return 'Moderator';
    }
  }

  String get description {
    switch (this) {
      case AdminRole.superAdmin:
        return 'Full system access and management';
      case AdminRole.cityAdmin:
        return 'Manage city-level operations';
      case AdminRole.moderator:
        return 'Monitor and moderate content';
    }
  }
}

class Admin {
  final String id;
  final String email;
  final String displayName;
  final AdminRole role;
  final String? city;
  final String? region;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final List<String> permissions;

  Admin({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.city,
    this.region,
    this.isActive = true,
    required this.createdAt,
    this.lastLogin,
    this.permissions = const [],
  });

  factory Admin.fromMap(Map<String, dynamic> map, String id) {
    return Admin(
      id: id,
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      role: AdminRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => AdminRole.moderator,
      ),
      city: map['city'],
      region: map['region'],
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      lastLogin: map['lastLogin'] != null
          ? (map['lastLogin'] as Timestamp).toDate()
          : null,
      permissions: List<String>.from(map['permissions'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'city': city,
      'region': region,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'permissions': permissions,
    };
  }

  Admin copyWith({
    String? email,
    String? displayName,
    AdminRole? role,
    String? city,
    String? region,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLogin,
    List<String>? permissions,
  }) {
    return Admin(
      id: id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      city: city ?? this.city,
      region: region ?? this.region,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      permissions: permissions ?? this.permissions,
    );
  }
}
