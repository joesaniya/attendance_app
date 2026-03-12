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

  // Stream subscription kept alive for real-time updates
  StreamSubscription<List<EmployeeModel>>? _employeesSubscription;

  List<EmployeeModel> get employees => _filteredEmployees;
  List<EmployeeModel> get allEmployees => _employees;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterDepartment => _filterDepartment;

  List<String> get departments {
    final depts = _employees.map((e) => e.department).toSet().toList();
    depts.sort();
    return ['All', ...depts];
  }

  List<EmployeeModel> get _filteredEmployees {
    return _employees.where((emp) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          emp.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.department.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.position.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesDept =
          _filterDepartment == 'All' || emp.department == _filterDepartment;
      return matchesSearch && matchesDept;
    }).toList();
  }

  /// Call once from dashboard — stays alive and pushes all updates in real time
  void listenToEmployees() {
    _employeesSubscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _employeesSubscription = _service.getEmployeesStream().listen(
      (employees) {
        _employees = employees;
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

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilterDepartment(String department) {
    _filterDepartment = department;
    notifyListeners();
  }

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
      final employee = await _service.createEmployee(
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
      _isLoading = false;
      notifyListeners();
      return employee;
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
      _isLoading = false;
      notifyListeners();
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
    return await _service.getAllEmployees();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _employeesSubscription?.cancel();
    super.dispose();
  }
}
