import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_role.dart';
import '../screens/dashboards/member_dashboard.dart';
import '../screens/dashboards/group_dashboard.dart';
import '../screens/dashboards/business_dashboard.dart';
import '../screens/dashboards/admin_dashboard.dart';
import '../screens/dashboard_screen.dart';

class NavigationService {
  static Future<Widget> getDashboardForUser(String userId) async {
    try {
      print('🔍 Getting dashboard for user: $userId');

      // First check if this is an admin account
      DocumentSnapshot adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(userId)
          .get();

      if (adminDoc.exists) {
        Map<String, dynamic> adminData = adminDoc.data() as Map<String, dynamic>;
        bool isActive = adminData['isActive'] ?? true;
        
        if (isActive) {
          print('👑 Admin account found, loading Admin Dashboard');
          return const AdminDashboardScreen();
        } else {
          print('⚠️ Admin account is deactivated');
          throw Exception('Admin account is deactivated');
        }
      }

      // Check if this is an organization account
      DocumentSnapshot orgDoc = await FirebaseFirestore.instance
          .collection('group_organizations')
          .doc(userId)
          .get();

      if (orgDoc.exists) {
        // This is a group organization account
        Map<String, dynamic> orgData = orgDoc.data() as Map<String, dynamic>;
        String? roleString = orgData['role'] as String?;

        print('🏢 Organization account found with role: $roleString');

        if (roleString == 'group' || roleString == UserRole.group.name) {
          print('🚀 Loading Group Dashboard for organization');
          return const GroupDashboard();
        }
      }

      // If not an organization, check regular user collection
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        String? roleString = userData['role'] as String?;

        print('👤 Individual user role found: $roleString');

        if (roleString != null) {
          UserRole role = UserRole.fromString(roleString);

          switch (role) {
            case UserRole.member:
              print('🚀 Loading Member Dashboard');
              return const MemberDashboard();
            case UserRole.group:
              print('🚀 Loading Group Dashboard');
              return const GroupDashboard();
            case UserRole.business:
              print('🚀 Loading Business Dashboard');
              return const BusinessDashboard();
          }
        }
      }

      print('⚠️ No role found, using default dashboard');
    } catch (e) {
      print('❌ Error getting user role: $e');
    }

    // Fallback to default dashboard
    print('🚀 Loading Default Dashboard');
    return const DashboardScreen();
  }

  static UserRole getRoleFromString(String? roleString) {
    if (roleString == null) return UserRole.member;
    return UserRole.fromString(roleString);
  }

  static Future<Map<String, dynamic>> getUserRoleInfo(String userId) async {
    try {
      // First check if this is an organization account
      DocumentSnapshot orgDoc = await FirebaseFirestore.instance
          .collection('group_organizations')
          .doc(userId)
          .get();

      if (orgDoc.exists) {
        Map<String, dynamic> orgData = orgDoc.data() as Map<String, dynamic>;
        String? roleString = orgData['role'] as String?;
        UserRole role = getRoleFromString(roleString);

        return {
          'role': role,
          'roleString': roleString ?? 'group',
          'displayName': role.displayName,
          'description': role.description,
          'userData': orgData,
          'isOrganization': true,
          'organizationName':
              orgData['organizationName'] ?? 'Unknown Organization',
        };
      }

      // Check regular user collection
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        String? roleString = userData['role'] as String?;
        UserRole role = getRoleFromString(roleString);

        return {
          'role': role,
          'roleString': roleString ?? 'member',
          'displayName': role.displayName,
          'description': role.description,
          'userData': userData,
          'isOrganization': false,
        };
      }
    } catch (e) {
      print('❌ Error getting user role info: $e');
    }

    return {
      'role': UserRole.member,
      'roleString': 'member',
      'displayName': 'Member',
      'description': 'Individual user with access to basic features',
      'userData': {},
      'isOrganization': false,
    };
  }
}
