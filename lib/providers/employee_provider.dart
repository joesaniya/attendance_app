// lib/providers/employee_provider.dart

import 'dart:async';
import 'dart:io';
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

  StreamSubscription<List<EmployeeModel>>? _sub;

  // ── Public getters ────────────────────────────────────────────────────────────
  List<EmployeeModel> get employees => _filtered;
  List<EmployeeModel> get allEmployees => _employees;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterDepartment => _filterDepartment;

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

  // ── Stream — open once and keep alive forever ─────────────────────────────────
  void listenToEmployees() {
    if (_sub != null) return; // already listening — never restart

    _isLoading = true;
    notifyListeners();

    _sub = _service.getEmployeesStream().listen(
      (list) {
        _employees = list;
        _isLoading = false;
        _error = null;
        notifyListeners(); // every Consumer<EmployeeProvider> rebuilds instantly
      },
      onError: (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
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

  // ── CRUD — stream reflects every Firestore write automatically ────────────────

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
      // stream callback will fire and clear isLoading + notifyListeners
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
