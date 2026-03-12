// lib/data/services/auth_service.dart
// FIXED: PigeonUserDetails cast error on Android

import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/network_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NetworkService _networkService = NetworkService();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signIn(String email, String password) async {
    try {
      log('[AuthService] Signing in: $email');

      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        log('[AuthService] Offline mode: checking local credentials');
        final prefs = await SharedPreferences.getInstance();
        final storedEmail = prefs.getString('offline_email');
        final storedPassword = prefs.getString('offline_password');
        final storedUserJson = prefs.getString('offline_user');

        if (storedEmail == email.trim() && storedPassword == password.trim() && storedUserJson != null) {
          log('[AuthService] Offline Auth success');
          final decoded = jsonDecode(storedUserJson);
          return UserModel.fromMap(decoded, decoded['id'] ?? '');
        } else {
          throw FirebaseAuthException(
            code: 'network-request-failed',
            message: 'No internet connection or invalid offline credentials.',
          );
        }
      }

      // Sign in first, then validate that a corresponding Firestore user record exists.
      // This avoids Firestore permission errors when the user is not yet authenticated.
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      log('[AuthService] Firebase Auth success: ${credential.user?.uid}');

      if (credential.user != null) {
        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(credential.user!.uid)
            .get();

        if (doc.exists) {
          log('[AuthService] Firestore user found: ${doc.data()}');
          final userModel = UserModel.fromMap(doc.data()!, doc.id);

          // Cache for offline login
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('offline_email', email.trim());
          await prefs.setString('offline_password', password.trim());
          
          final userMap = userModel.toMap();
          userMap['createdAt'] = userModel.createdAt.toIso8601String();
          await prefs.setString('offline_user', jsonEncode(userMap));

          return userModel;
        } else {
          // Auth succeeded but there is no matching record in the users
          // collection — reject the login with a clear error.
          log(
            '[AuthService] No Firestore record found for ${credential.user!.uid}',
          );
          await _auth.signOut(); // sign them back out immediately
          throw FirebaseAuthException(
            code: 'no-firestore-record',
            message: 'No Records Found.',
          );
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      log('[AuthService] FirebaseAuthException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      log('[AuthService] General error: $e');
      rethrow;
    }
  }

  Future<UserModel?> getCurrentUserModel() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        final prefs = await SharedPreferences.getInstance();
        final storedUserJson = prefs.getString('offline_user');
        if (storedUserJson != null) {
          final decoded = jsonDecode(storedUserJson);
          return UserModel.fromMap(decoded, decoded['id'] ?? '');
        }
        return null;
      }

      if (_auth.currentUser == null) return null;

      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(_auth.currentUser!.uid)
          .get();

      if (doc.exists) {
        final userModel = UserModel.fromMap(doc.data()!, doc.id);
        
        final prefs = await SharedPreferences.getInstance();
        final userMap = userModel.toMap();
        userMap['createdAt'] = userModel.createdAt.toIso8601String();
        await prefs.setString('offline_user', jsonEncode(userMap));
        
        return userModel;
      }
      return null;
    } catch (e) {
      log('[AuthService] getCurrentUserModel error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_email');
    await prefs.remove('offline_password');
    await prefs.remove('offline_user');
  }

  Future<UserModel> createAdminUser({
    required String email,
    required String password,
    required String name,
    required String role,
    required String createdBy,
    required String createdByRole,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = UserModel(
        id: credential.user!.uid,
        email: email,
        name: name,
        role: role,
        createdAt: DateTime.now(),
        createdBy: createdBy,
        createdByRole: createdByRole,
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(credential.user!.uid)
          .set(user.toMap());

      return user;
    } catch (e) {
      log('[AuthService] createAdminUser error: $e');
      rethrow;
    }
  }

  // Initialize default super admin
  Future<void> initializeDefaultAdmin() async {
    try {
      log('[AuthService] Checking for existing Super Admin...');

      // Step 1: Try to sign in with default credentials
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: AppConstants.defaultAdminEmail,
          password: AppConstants.defaultAdminPassword,
        );

        log('[AuthService] Super Admin Auth exists: ${credential.user?.uid}');

        // Step 2: Make sure Firestore record exists
        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(credential.user!.uid)
            .get();

        if (!doc.exists) {
          log('[AuthService] Creating missing Firestore record...');
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(credential.user!.uid)
              .set({
                'email': AppConstants.defaultAdminEmail,
                'name': 'Super Admin',
                'role': AppConstants.roleSuperAdmin,
                'photoUrl': null,
                'createdAt': FieldValue.serverTimestamp(),
                'createdBy': 'system',
                'createdByRole': 'system',
                'isActive': true,
              });
          log('[AuthService] Firestore record created.');
        } else {
          log('[AuthService] Firestore record already exists.');
        }

        // Sign out after initialization check
        await _auth.signOut();
        log('[AuthService] Init complete.');
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' ||
            e.code == 'invalid-credential' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          // Admin doesn't exist yet — create it
          log('[AuthService] Super Admin not found, creating...');
        } else {
          log('[AuthService] Init sign-in error: ${e.code}');
          // Don't rethrow — let app continue
          return;
        }
      }

      // Step 3: Create new Super Admin account
      final credential = await _auth.createUserWithEmailAndPassword(
        email: AppConstants.defaultAdminEmail,
        password: AppConstants.defaultAdminPassword,
      );

      log('[AuthService] Super Admin created in Auth: ${credential.user?.uid}');

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(credential.user!.uid)
          .set({
            'email': AppConstants.defaultAdminEmail,
            'name': 'Super Admin',
            'role': AppConstants.roleSuperAdmin,
            'photoUrl': null,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': 'system',
            'createdByRole': 'system',
            'isActive': true,
          });

      log('[AuthService] Super Admin Firestore record saved.');

      // Sign out after creation
      await _auth.signOut();
      log('[AuthService] Super Admin init complete!');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        log(
          '[AuthService] Super Admin already exists (email-already-in-use), skipping.',
        );
      } else {
        log(
          '[AuthService] initializeDefaultAdmin FirebaseAuthException: ${e.code} - ${e.message}',
        );
      }
    } catch (e) {
      log('[AuthService] initializeDefaultAdmin error: $e');
    }
  }
}
