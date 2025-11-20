import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/admin.dart';

class AdminAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current admin user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in admin with email and password
  Future<Admin?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      // Sign in with Firebase Auth
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      if (user == null) {
        throw Exception('Sign in failed - no user returned');
      }

      // Check if user exists in admins collection
      final adminDoc = await _firestore.collection('admins').doc(user.uid).get();

      if (!adminDoc.exists) {
        // Not an admin, sign out
        await _auth.signOut();
        throw Exception('Access denied - not an admin account');
      }

      final admin = Admin.fromMap(adminDoc.data()!, user.uid);

      // Check if admin account is active
      if (!admin.isActive) {
        await _auth.signOut();
        throw Exception('Admin account is deactivated');
      }

      // Update last login time
      await _firestore.collection('admins').doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      return admin;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No admin account found with this email');
        case 'wrong-password':
          throw Exception('Incorrect password');
        case 'invalid-email':
          throw Exception('Invalid email address');
        case 'user-disabled':
          throw Exception('This admin account has been disabled');
        case 'too-many-requests':
          throw Exception('Too many failed attempts. Please try again later');
        default:
          throw Exception('Sign in failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('Admin sign in error: $e');
      rethrow;
    }
  }

  // Get current admin profile
  Future<Admin?> getCurrentAdmin() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final adminDoc = await _firestore.collection('admins').doc(user.uid).get();

      if (!adminDoc.exists) {
        return null;
      }

      return Admin.fromMap(adminDoc.data()!, user.uid);
    } catch (e) {
      debugPrint('Error getting current admin: $e');
      return null;
    }
  }

  // Create new admin (only for super admins)
  Future<void> createAdmin({
    required String email,
    required String password,
    required String displayName,
    required AdminRole role,
    String? city,
    String? region,
    List<String> permissions = const [],
  }) async {
    try {
      // Check if current user is super admin
      final currentAdmin = await getCurrentAdmin();
      if (currentAdmin == null ||
          currentAdmin.role != AdminRole.superAdmin) {
        throw Exception('Only super admins can create admin accounts');
      }

      // Create Firebase Auth account
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      if (user == null) {
        throw Exception('Failed to create admin account');
      }

      // Create admin document in Firestore
      final admin = Admin(
        id: user.uid,
        email: email,
        displayName: displayName,
        role: role,
        city: city,
        region: region,
        isActive: true,
        createdAt: DateTime.now(),
        permissions: permissions,
      );

      await _firestore.collection('admins').doc(user.uid).set(admin.toMap());

      // Update display name in Firebase Auth
      await user.updateDisplayName(displayName);

      debugPrint('Admin account created successfully: $email');
    } catch (e) {
      debugPrint('Error creating admin: $e');
      rethrow;
    }
  }

  // Update admin profile
  Future<void> updateAdmin(String adminId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('admins').doc(adminId).update(updates);
    } catch (e) {
      debugPrint('Error updating admin: $e');
      throw Exception('Failed to update admin profile');
    }
  }

  // Deactivate admin account
  Future<void> deactivateAdmin(String adminId) async {
    try {
      final currentAdmin = await getCurrentAdmin();
      if (currentAdmin == null ||
          currentAdmin.role != AdminRole.superAdmin) {
        throw Exception('Only super admins can deactivate accounts');
      }

      await _firestore.collection('admins').doc(adminId).update({
        'isActive': false,
      });
    } catch (e) {
      debugPrint('Error deactivating admin: $e');
      rethrow;
    }
  }

  // Reactivate admin account
  Future<void> reactivateAdmin(String adminId) async {
    try {
      final currentAdmin = await getCurrentAdmin();
      if (currentAdmin == null ||
          currentAdmin.role != AdminRole.superAdmin) {
        throw Exception('Only super admins can reactivate accounts');
      }

      await _firestore.collection('admins').doc(adminId).update({
        'isActive': true,
      });
    } catch (e) {
      debugPrint('Error reactivating admin: $e');
      rethrow;
    }
  }

  // Get all admins (for super admin)
  Future<List<Admin>> getAllAdmins() async {
    try {
      final currentAdmin = await getCurrentAdmin();
      if (currentAdmin == null ||
          currentAdmin.role != AdminRole.superAdmin) {
        throw Exception('Only super admins can view all admins');
      }

      final snapshot = await _firestore.collection('admins').get();

      return snapshot.docs
          .map((doc) => Admin.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error getting all admins: $e');
      throw Exception('Failed to fetch admin list');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
      throw Exception('Failed to sign out');
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      debugPrint('Password reset error: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No admin account found with this email');
        case 'invalid-email':
          throw Exception('Invalid email address');
        default:
          throw Exception('Failed to send reset email: ${e.message}');
      }
    } catch (e) {
      debugPrint('Password reset error: $e');
      rethrow;
    }
  }

  // Change password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      // Reauthenticate user
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      debugPrint('Change password error: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'wrong-password':
          throw Exception('Current password is incorrect');
        case 'weak-password':
          throw Exception('New password is too weak');
        case 'requires-recent-login':
          throw Exception('Please sign in again to change password');
        default:
          throw Exception('Failed to change password: ${e.message}');
      }
    } catch (e) {
      debugPrint('Change password error: $e');
      rethrow;
    }
  }
}
