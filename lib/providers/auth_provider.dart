// lib/providers/auth_provider.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/services/auth_service.dart';
import '../data/models/user_model.dart';
import 'dart:developer';

enum AuthStatus { initial, loading, authenticating, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  String? _errorMessage;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading || _status == AuthStatus.authenticating;

  bool get isSuperAdmin => _currentUser?.role == 'super_admin';
  bool get isManager => _currentUser?.role == 'manager';
  bool get isAdminOrManager => isSuperAdmin || isManager;

  Future<void> initialize() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser != null) {
        // ── Session is still active ──────────────────────────────────────────
        // User was previously logged in — skip initializeDefaultAdmin
        // (which would sign them out) and restore their session directly.
        log('[AuthProvider] Active session found: ${firebaseUser.uid}');
        final user = await _authService.getCurrentUserModel();
        if (user != null) {
          _currentUser = user;
          _status = AuthStatus.authenticated;
          log('[AuthProvider] Session restored for: ${user.email}');
        } else {
          // Auth session exists but no Firestore record — sign out cleanly
          log(
            '[AuthProvider] No Firestore record for active session, signing out.',
          );
          await _authService.signOut();
          // await _initDefaultAdmin();
          _status = AuthStatus.unauthenticated;
        }
      } else {
        // ── No active session ────────────────────────────────────────────────
        // First launch or after sign-out — init default admin if needed.
        log('[AuthProvider] No active session. Initializing default admin...');
        // await _initDefaultAdmin();
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      log('[AuthProvider] initialize error: $e');
      _status = AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  /// Initializes the default Super Admin account if it doesn't exist yet.
  /// Only called when there is no active session.
  Future<void> _initDefaultAdmin() async {
    try {
      await _authService.initializeDefaultAdmin();
    } catch (e) {
      log('[AuthProvider] _initDefaultAdmin error: $e');
      // Never crash — let the app continue to the login screen
    }
  }

  Future<bool> signIn(String email, String password) async {
    _status = AuthStatus.authenticating;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signIn(email, password);
      if (user != null) {
        _currentUser = user;
        _status = AuthStatus.authenticated;
        log('[AuthProvider] Signed in: ${user.email} role: ${user.role}');
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.error;
        _errorMessage = 'No Records Found.';
        notifyListeners();
        return false;
      }
    } on FirebaseAuthException catch (e) {
      _status = AuthStatus.error;
      _errorMessage = _parseFirebaseError(e.code);
      log('[AuthProvider] FirebaseAuthException: ${e.code}');
      notifyListeners();
      return false;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = _parseFirebaseError(e.toString());
      log('[AuthProvider] signIn error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    log('[AuthProvider] Signed out.');
    notifyListeners();
  }

  String _parseFirebaseError(String error) {
    if (error.contains('no-firestore-record') ||
        error.contains('user-not-found') ||
        error.contains('ERROR_USER_NOT_FOUND')) {
      return 'No Records Found.';
    }
    if (error.contains('wrong-password') ||
        error.contains('INVALID_PASSWORD')) {
      return 'Incorrect Password.';
    }
    if (error.contains('invalid-credential') ||
        error.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Incorrect Credentials.';
    }
    if (error.contains('invalid-email')) {
      return 'Invalid email address format.';
    }
    if (error.contains('user-disabled')) {
      return 'This account has been disabled. Contact your administrator.';
    }
    if (error.contains('too-many-requests')) {
      return 'Too many failed attempts. Please try again later.';
    }
    if (error.contains('network-request-failed')) {
      return 'No internet connection. Please check your network.';
    }
    return 'Login failed. Please check your credentials and try again.';
  }

  void clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }
}
