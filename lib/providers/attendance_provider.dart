// lib/providers/attendance_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/services/attendance_service.dart';
import '../data/models/attendance_model.dart';
import '../data/models/employee_model.dart';

class AttendanceProvider extends ChangeNotifier {
  final AttendanceService _service = AttendanceService();

  List<AttendanceModel> _todayAttendance = [];
  List<AttendanceModel> _filteredAttendance = [];
  AttendanceModel? _currentEmployeeAttendance;
  bool _isLoading = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  bool _isFaceDetecting = false;
  bool _attendanceMarked = false;

  // Stream subscriptions — kept alive for real-time updates
  StreamSubscription<List<AttendanceModel>>? _attendanceSubscription;
  StreamSubscription<AttendanceModel?>? _employeeAttendanceSubscription;

  List<AttendanceModel> get todayAttendance => _todayAttendance;
  List<AttendanceModel> get filteredAttendance => _filteredAttendance;
  AttendanceModel? get currentEmployeeAttendance => _currentEmployeeAttendance;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;
  bool get isFaceDetecting => _isFaceDetecting;
  bool get attendanceMarked => _attendanceMarked;
  bool get isEmployeeLoggedIn => _currentEmployeeAttendance?.isLoggedIn ?? false;

  int get presentCount =>
      _filteredAttendance.where((a) => a.status == 'present').length;
  int get absentCount =>
      _filteredAttendance.where((a) => a.status == 'absent').length;
  int get incompleteCount =>
      _filteredAttendance.where((a) => a.status == 'incomplete').length;

  /// Call once — listens to attendance for selected date in real time
  void listenToAttendanceByDate(DateTime date) {
    _selectedDate = date;

    // Cancel previous subscription before creating new one
    _attendanceSubscription?.cancel();

    _attendanceSubscription = _service.getAttendanceByDate(date).listen(
      (records) {
        _todayAttendance = records;
        _filteredAttendance = records;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  /// Switch to a different date — cancels old stream, starts new one
  void setSelectedDate(DateTime date) {
    if (_selectedDate.year == date.year &&
        _selectedDate.month == date.month &&
        _selectedDate.day == date.day) return; // same date, no-op
    listenToAttendanceByDate(date);
  }

  /// Listen to a specific employee's attendance for today in real time
  void listenToEmployeeAttendance(String employeeId) {
    _employeeAttendanceSubscription?.cancel();

    _employeeAttendanceSubscription =
        _service.getTodayAttendanceStream(employeeId).listen(
      (attendance) {
        _currentEmployeeAttendance = attendance;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> loadEmployeeAttendance(String employeeId) async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentEmployeeAttendance =
          await _service.getTodayAttendance(employeeId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> markLogin(EmployeeModel employee, {String? localPhotoPath}) async {
    _isLoading = true;
    _error = null;
    _attendanceMarked = false;
    notifyListeners();

    try {
      final existing = await _service.getTodayAttendance(employee.id);
      if (existing != null && existing.isLoggedIn) {
        _isLoading = false;
        _error = 'Already logged in today';
        notifyListeners();
        return false;
      }

      final attendance = await _service.markLogin(employee, localPhotoPath: localPhotoPath);
      _currentEmployeeAttendance = attendance;
      _isLoading = false;
      _attendanceMarked = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markLogout(String employeeId, {String? localPhotoPath}) async {
    _isLoading = true;
    _error = null;
    _attendanceMarked = false;
    notifyListeners();

    try {
      final attendance = await _service.markLogout(employeeId, localPhotoPath: localPhotoPath);
      _currentEmployeeAttendance = attendance;
      _isLoading = false;
      _attendanceMarked = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<AttendanceModel>> getEmployeeAttendanceHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _service.getEmployeeAttendance(
      employeeId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Map<String, int>> getMonthlyStats(int year, int month) async {
    return await _service.getMonthlyStats(year, month);
  }

  void setFaceDetecting(bool value) {
    _isFaceDetecting = value;
    notifyListeners();
  }

  void resetAttendanceMarked() {
    _attendanceMarked = false;
    notifyListeners();
  }

  void filterByDepartment(String department) {
    if (department == 'All') {
      _filteredAttendance = _todayAttendance;
    } else {
      _filteredAttendance =
          _todayAttendance.where((a) => a.department == department).toList();
    }
    notifyListeners();
  }

  // ── Refresh ──────────────────────────────────────────────────────────────────

  /// Re-opens the real-time Firestore attendance stream for [_selectedDate].
  /// Called by the pull-to-refresh gesture on the Attendance tab.
  Future<void> refresh() async {
    _attendanceSubscription?.cancel();
    _attendanceSubscription = null;
    listenToAttendanceByDate(_selectedDate);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    _employeeAttendanceSubscription?.cancel();
    super.dispose();
  }
}
/*

import 'package:flutter/foundation.dart';
import '../data/services/attendance_service.dart';
import '../data/models/attendance_model.dart';
import '../data/models/employee_model.dart';

class AttendanceProvider extends ChangeNotifier {
  final AttendanceService _service = AttendanceService();

  List<AttendanceModel> _todayAttendance = [];
  List<AttendanceModel> _filteredAttendance = [];
  AttendanceModel? _currentEmployeeAttendance;
  bool _isLoading = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  bool _isFaceDetecting = false;
  bool _attendanceMarked = false;

  List<AttendanceModel> get todayAttendance => _todayAttendance;
  List<AttendanceModel> get filteredAttendance => _filteredAttendance;
  AttendanceModel? get currentEmployeeAttendance => _currentEmployeeAttendance;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;
  bool get isFaceDetecting => _isFaceDetecting;
  bool get attendanceMarked => _attendanceMarked;

  bool get isEmployeeLoggedIn =>
      _currentEmployeeAttendance?.isLoggedIn ?? false;

  void listenToAttendanceByDate(DateTime date) {
    _selectedDate = date;
    _service.getAttendanceByDate(date).listen(
      (records) {
        if (date.year == _selectedDate.year &&
            date.month == _selectedDate.month &&
            date.day == _selectedDate.day) {
          _todayAttendance = records;
          _filteredAttendance = records;
          notifyListeners();
        }
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    listenToAttendanceByDate(date);
    notifyListeners();
  }

  Future<void> loadEmployeeAttendance(String employeeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _currentEmployeeAttendance =
          await _service.getTodayAttendance(employeeId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> markLogin(EmployeeModel employee) async {
    _isLoading = true;
    _error = null;
    _attendanceMarked = false;
    notifyListeners();

    try {
      // Check if already logged in
      final existing = await _service.getTodayAttendance(employee.id);
      if (existing != null && existing.isLoggedIn) {
        _isLoading = false;
        _error = 'Already logged in today';
        notifyListeners();
        return false;
      }

      final attendance = await _service.markLogin(employee);
      _currentEmployeeAttendance = attendance;
      _isLoading = false;
      _attendanceMarked = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markLogout(String employeeId) async {
    _isLoading = true;
    _error = null;
    _attendanceMarked = false;
    notifyListeners();

    try {
      final attendance = await _service.markLogout(employeeId);
      _currentEmployeeAttendance = attendance;
      _isLoading = false;
      _attendanceMarked = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<AttendanceModel>> getEmployeeAttendanceHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _service.getEmployeeAttendance(
      employeeId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Map<String, int>> getMonthlyStats(int year, int month) async {
    return await _service.getMonthlyStats(year, month);
  }

  void setFaceDetecting(bool value) {
    _isFaceDetecting = value;
    notifyListeners();
  }

  void resetAttendanceMarked() {
    _attendanceMarked = false;
    notifyListeners();
  }

  void filterByDepartment(String department) {
    if (department == 'All') {
      _filteredAttendance = _todayAttendance;
    } else {
      _filteredAttendance = _todayAttendance
          .where((a) => a.department == department)
          .toList();
    }
    notifyListeners();
  }

  int get presentCount =>
      _filteredAttendance.where((a) => a.status == 'present').length;

  int get absentCount =>
      _filteredAttendance.where((a) => a.status == 'absent').length;

  int get incompleteCount =>
      _filteredAttendance.where((a) => a.status == 'incomplete').length;

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
*/