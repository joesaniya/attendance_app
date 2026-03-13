// lib/providers/employee_provider.dart
//
// Added: isNameDuplicate() — checks whether a given name already exists
// in the local employee list (case-insensitive).

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/services/employee_service.dart';
import '../data/models/employee_model.dart';

class EmployeeProvider extends ChangeNotifier {
  final EmployeeService _service = EmployeeService();

  List<EmployeeModel> _employees = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  String _filterDepartment = 'All';

  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  static const int _pageSize = 20;

  StreamSubscription<List<EmployeeModel>>? _sub;

  List<EmployeeModel> get employees => _filtered;
  List<EmployeeModel> get allEmployees => _employees;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterDepartment => _filterDepartment;
  bool get hasMore => _hasMore;

  List<String> get departments {
    final d =
        _employees
            .map((e) => e.department)
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...d];
  }

  List<EmployeeModel> get _filtered {
    return _employees.where((emp) {
      final q = _searchQuery.toLowerCase();
      final matchSearch =
          q.isEmpty ||
          emp.name.toLowerCase().contains(q) ||
          emp.email.toLowerCase().contains(q) ||
          emp.department.toLowerCase().contains(q) ||
          emp.position.toLowerCase().contains(q) ||
          (emp.employeeCode?.toLowerCase().contains(q) ?? false);
      final matchDept =
          _filterDepartment == 'All' || emp.department == _filterDepartment;
      return matchSearch && matchDept;
    }).toList();
  }

  // ── Duplicate name check ──────────────────────────────────────────────────────
  /// Returns true if [name] already exists in the loaded employee list
  /// (case-insensitive, trimmed).
  Future<bool> isNameDuplicate(String name) async {
    final normalised = name.trim().toLowerCase();
    return _employees.any((e) => e.name.trim().toLowerCase() == normalised);
  }

  // ── Real-time stream ──────────────────────────────────────────────────────────

  void listenToEmployees() {
    if (_sub != null) return;

    _isLoading = true;
    notifyListeners();

    _sub = _service.getEmployeesStream().listen(
      (list) {
        _employees = list;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  // ── Pagination ────────────────────────────────────────────────────────────────

  Future<void> loadMoreEmployees() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _service.getEmployeesPaginated(
        pageSize: _pageSize,
        startAfterDoc: _lastDocument,
      );

      final newEmployees = result['employees'] as List<EmployeeModel>;
      _lastDocument = result['lastDoc'] as DocumentSnapshot?;
      _hasMore = result['hasMore'] as bool;

      final existingIds = _employees.map((e) => e.id).toSet();
      final fresh = newEmployees
          .where((e) => !existingIds.contains(e.id))
          .toList();
      _employees = [..._employees, ...fresh];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ── Refresh ───────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    _sub?.cancel();
    _sub = null;
    _lastDocument = null;
    _hasMore = true;
    listenToEmployees();
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ── Filters ───────────────────────────────────────────────────────────────────

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setFilterDepartment(String dept) {
    _filterDepartment = dept;
    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────────

  Future<EmployeeModel?> createEmployee({
    required String name,
    required String email,
    required String phone,
    required String department,
    required String position,
    required String address,
    File? photoFile,
    required String createdBy,
    required String createdByRole,
    required String createdByName,
    String? faceDescriptor,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final emp = await _service.createEmployee(
        name: name,
        email: email,
        phone: phone,
        department: department,
        position: position,
        address: address,
        photoFile: photoFile,
        createdBy: createdBy,
        createdByRole: createdByRole,
        createdByName: createdByName,
        faceDescriptor: faceDescriptor,
      );
      return emp;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateEmployee({
    required String employeeId,
    required Map<String, dynamic> data,
    File? newPhotoFile,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _service.updateEmployee(
        employeeId: employeeId,
        data: data,
        newPhotoFile: newPhotoFile,
      );
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteEmployee(String employeeId) async {
    try {
      await _service.deleteEmployee(employeeId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<EmployeeModel>> getAllEmployeesForAttendance() async {
    return _service.getAllEmployees();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
