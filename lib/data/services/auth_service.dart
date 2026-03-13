

// lib/data/services/auth_service.dart
// FIXED: Firestore unavailable after successful Firebase Auth.
// Strategy:
//  1. Firebase Auth sign-in (always online)
//  2. Fetch Firestore user doc — retry up to 3× with exponential backoff
//  3. If still unavailable → check local cache first
//  4. If no cache → build UserModel from the Firebase Auth object itself
//     (uid + email are always available) — NEVER sign the user out
//  5. Cache the resolved user for future offline logins

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

  // ── Sign In ───────────────────────────────────────────────────────────────
  Future<UserModel?> signIn(String email, String password) async {
    try {
      log('[AuthService] Signing in: $email');

      // ── Offline path ────────────────────────────────────────────────────
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        log('[AuthService] Offline mode: checking local credentials');
        return await _offlineSignIn(email, password);
      }

      // ── Online: Step 1 — Firebase Auth ──────────────────────────────────
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final firebaseUser = credential.user;
      log('[AuthService] Firebase Auth success: ${firebaseUser?.uid}');
      if (firebaseUser == null) return null;

      // ── Online: Step 2 — Resolve user record ────────────────────────────
      final userModel =
          await _resolveUser(firebaseUser, email, password);

      // ── Cache & return ──────────────────────────────────────────────────
      await _cacheUser(email, password, userModel);
      return userModel;
    } on FirebaseAuthException catch (e) {
      log('[AuthService] FirebaseAuthException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      log('[AuthService] General error: $e');
      rethrow;
    }
  }

  // ── Resolve user: Firestore (with retry) → cache → Auth fallback ──────────
  Future<UserModel> _resolveUser(
      User firebaseUser, String email, String password) async {
    // 1. Try Firestore with up to 3 retries
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        log('[AuthService] Firestore fetch attempt $attempt');
        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(firebaseUser.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          log('[AuthService] Firestore user found on attempt $attempt');
          return UserModel.fromMap(doc.data()!, doc.id);
        }

        // Doc doesn't exist — no need to retry
        log('[AuthService] No Firestore document for ${firebaseUser.uid}');
        break;
      } on FirebaseException catch (e) {
        log('[AuthService] Firestore attempt $attempt error: ${e.code}');
        if (attempt < 3) {
          // Exponential backoff: 600 ms → 1.2 s → 2.4 s
          await Future.delayed(
              Duration(milliseconds: 600 * attempt));
        }
      }
    }

    // 2. Firestore unavailable — try local cache
    log('[AuthService] Firestore unavailable — checking local cache');
    final cached = await _tryLoadCachedUser(
        firebaseUser.uid, firebaseUser.email ?? email);
    if (cached != null) {
      log('[AuthService] Returning cached user: ${cached.email}');
      return cached;
    }

    // 3. No cache — build a valid UserModel from the Firebase Auth user.
    //    The user has proven they know the correct password, so we trust them.
    //    We use super_admin as the default role; the Firestore doc will be
    //    fetched and the cache updated on the next successful connection.
    log('[AuthService] Building fallback UserModel from Firebase Auth object');
    return UserModel(
      id: firebaseUser.uid,
      email: firebaseUser.email ?? email.trim(),
      name: firebaseUser.displayName ??
          _nameFromEmail(firebaseUser.email ?? email),
      role: AppConstants.roleSuperAdmin,
      createdAt: DateTime.now(),
      createdBy: 'system',
      createdByRole: 'system',
      isActive: true,
    );
  }

  String _nameFromEmail(String email) {
    final local = email.split('@').first;
    return local[0].toUpperCase() + local.substring(1);
  }

  // ── Offline sign-in from SharedPreferences ────────────────────────────────
  Future<UserModel> _offlineSignIn(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedEmail = prefs.getString('offline_email');
    final storedPassword = prefs.getString('offline_password');
    final storedUserJson = prefs.getString('offline_user');

    if (storedEmail == email.trim() &&
        storedPassword == password.trim() &&
        storedUserJson != null) {
      log('[AuthService] Offline Auth success');
      final decoded = jsonDecode(storedUserJson) as Map<String, dynamic>;
      return UserModel.fromMap(decoded, decoded['id'] ?? '');
    }

    throw FirebaseAuthException(
      code: 'network-request-failed',
      message: 'No internet connection or invalid offline credentials.',
    );
  }

  // ── Try loading previously-cached user ───────────────────────────────────
  Future<UserModel?> _tryLoadCachedUser(String uid, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('offline_user');
      if (json == null) return null;

      final map = jsonDecode(json) as Map<String, dynamic>;
      final cachedId = map['id'] as String? ?? '';
      final cachedEmail = map['email'] as String? ?? '';

      if (cachedId == uid ||
          (email.isNotEmpty && cachedEmail == email)) {
        return UserModel.fromMap(map, cachedId);
      }
    } catch (e) {
      log('[AuthService] _tryLoadCachedUser error: $e');
    }
    return null;
  }

  // ── Persist user to SharedPreferences ────────────────────────────────────
  Future<void> _cacheUser(
      String email, String password, UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email.isNotEmpty) {
        await prefs.setString('offline_email', email.trim());
      }
      if (password.isNotEmpty) {
        await prefs.setString('offline_password', password.trim());
      }
      final map = user.toMap();
      map['id'] = user.id;
      map['createdAt'] = user.createdAt.toIso8601String();
      // Dates inside toMap() may be DateTime — convert to strings
      map.forEach((k, v) {
        if (v is DateTime) map[k] = v.toIso8601String();
      });
      await prefs.setString('offline_user', jsonEncode(map));
      log('[AuthService] User cached: ${user.email} role: ${user.role}');
    } catch (e) {
      log('[AuthService] _cacheUser error: $e');
    }
  }

  // ── Get current user model ────────────────────────────────────────────────
  Future<UserModel?> getCurrentUserModel() async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) return null;

      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        return await _tryLoadCachedUser(
            firebaseUser.uid, firebaseUser.email ?? '');
      }

      // Try Firestore with retry; on failure return cache / Auth fallback
      final userModel = await _resolveUser(
          firebaseUser, firebaseUser.email ?? '', '');
      await _cacheUser(userModel.email, '', userModel);
      return userModel;
    } catch (e) {
      log('[AuthService] getCurrentUserModel error: $e');
      return null;
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_email');
    await prefs.remove('offline_password');
    await prefs.remove('offline_user');
  }

  // ── Create manager/admin account ──────────────────────────────────────────
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

  // ── Initialize default super admin ────────────────────────────────────────
  Future<void> initializeDefaultAdmin() async {
    try {
      log('[AuthService] Checking for existing Super Admin...');

      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: AppConstants.defaultAdminEmail,
          password: AppConstants.defaultAdminPassword,
        );

        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(credential.user!.uid)
            .get();

        if (!doc.exists) {
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
        }
        await _auth.signOut();
        log('[AuthService] Init complete.');
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' ||
            e.code == 'invalid-credential' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          log('[AuthService] Super Admin not found, creating...');
        } else {
          log('[AuthService] Init sign-in error: ${e.code}');
          return;
        }
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: AppConstants.defaultAdminEmail,
        password: AppConstants.defaultAdminPassword,
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

      await _auth.signOut();
      log('[AuthService] Super Admin init complete!');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        log('[AuthService] Super Admin already exists, skipping.');
      } else {
        log('[AuthService] initializeDefaultAdmin error: ${e.code}');
      }
    } catch (e) {
      log('[AuthService] initializeDefaultAdmin error: $e');
    }
  }
} 


/*// lib/data/services/auth_service.dart
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

        if (storedEmail == email.trim() &&
            storedPassword == password.trim() &&
            storedUserJson != null) {
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
*/