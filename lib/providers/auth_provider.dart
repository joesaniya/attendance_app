// lib/providers/auth_provider.dart

import 'package:flutter/foundation.dart';
import '../data/services/auth_service.dart';
import '../data/models/user_model.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  String? _errorMessage;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;

  bool get isSuperAdmin => _currentUser?.role == 'super_admin';
  bool get isManager => _currentUser?.role == 'manager';
  bool get isAdminOrManager => isSuperAdmin || isManager;

  Future<void> initialize() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      await _authService.initializeDefaultAdmin();
      final user = await _authService.getCurrentUserModel();
      if (user != null) {
        _currentUser = user;
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signIn(email, password);
      if (user != null) {
        _currentUser = user;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.error;
        _errorMessage = 'No account record found for this email.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = _parseFirebaseError(e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  String _parseFirebaseError(String error) {
    // Thrown by AuthService when Firebase Auth passes but no Firestore record
    if (error.contains('no-firestore-record')) {
      return 'No Records Found. This account has not been registered in the system.';
    }
    // Firebase Auth: email not registered at all
    if (error.contains('user-not-found') ||
        error.contains('ERROR_USER_NOT_FOUND')) {
      return 'No Records Found. No account exists with this email address.';
    }
    // Firebase Auth: password mismatch
    if (error.contains('wrong-password') ||
        error.contains('invalid-password') ||
        error.contains('INVALID_PASSWORD')) {
      return 'Incorrect Password. Please check your password and try again.';
    }
    // Newer Firebase SDK combines user-not-found + wrong-password into this
    if (error.contains('invalid-credential') ||
        error.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Incorrect Credentials. Email or password is wrong.';
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
