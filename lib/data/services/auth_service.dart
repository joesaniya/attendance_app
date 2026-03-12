// lib/data/services/auth_service.dart
// FIXED: PigeonUserDetails cast error on Android

import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signIn(String email, String password) async {
    try {
      print('[AuthService] Signing in: $email');

      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      print('[AuthService] Firebase Auth success: ${credential.user?.uid}');

      if (credential.user != null) {
        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(credential.user!.uid)
            .get();

        if (doc.exists) {
          print('[AuthService] Firestore user found: ${doc.data()}');
          return UserModel.fromMap(doc.data()!, doc.id);
        } else {
          // Auth succeeded but there is no matching record in the users
          // collection — reject the login with a clear error.
          print('[AuthService] No Firestore record found for ${credential.user!.uid}');
          await _auth.signOut(); // sign them back out immediately
          throw FirebaseAuthException(
            code: 'no-firestore-record',
            message: 'No account record found for this email.',
          );
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      print('[AuthService] FirebaseAuthException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('[AuthService] General error: $e');
      rethrow;
    }
  }

  Future<UserModel?> getCurrentUserModel() async {
    try {
      if (_auth.currentUser == null) return null;

      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(_auth.currentUser!.uid)
          .get();

      if (doc.exists) {
        return UserModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      print('[AuthService] getCurrentUserModel error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
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
      print('[AuthService] createAdminUser error: $e');
      rethrow;
    }
  }

  // Initialize default super admin
  Future<void> initializeDefaultAdmin() async {
    try {
      print('[AuthService] Checking for existing Super Admin...');

      // Step 1: Try to sign in with default credentials
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: AppConstants.defaultAdminEmail,
          password: AppConstants.defaultAdminPassword,
        );

        print('[AuthService] Super Admin Auth exists: ${credential.user?.uid}');

        // Step 2: Make sure Firestore record exists
        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(credential.user!.uid)
            .get();

        if (!doc.exists) {
          print('[AuthService] Creating missing Firestore record...');
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
          print('[AuthService] Firestore record created.');
        } else {
          print('[AuthService] Firestore record already exists.');
        }

        // Sign out after initialization check
        await _auth.signOut();
        print('[AuthService] Init complete.');
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' ||
            e.code == 'invalid-credential' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          // Admin doesn't exist yet — create it
          print('[AuthService] Super Admin not found, creating...');
        } else {
          print('[AuthService] Init sign-in error: ${e.code}');
          // Don't rethrow — let app continue
          return;
        }
      }

      // Step 3: Create new Super Admin account
      final credential = await _auth.createUserWithEmailAndPassword(
        email: AppConstants.defaultAdminEmail,
        password: AppConstants.defaultAdminPassword,
      );

      print(
        '[AuthService] Super Admin created in Auth: ${credential.user?.uid}',
      );

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
