// lib/providers/employee_provider.dart

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/services/employee_service.dart';
import '../data/models/employee_model.dart';

class EmployeeProvider extends ChangeNotifier {
  final EmployeeService _service = EmployeeService();

  // ── State ─────────────────────────────────────────────────────────────────────

  List<EmployeeModel> _employees = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  String _filterDepartment = 'All';

  // Pagination state
  /// The last Firestore document yielded — used as cursor for "load more"
  DocumentSnapshot? _lastDocument;
  /// Whether additional pages are available from Firestore
  bool _hasMore = true;
  /// True while a background "load more" call is in flight
  bool _isLoadingMore = false;

  /// Number of employees to fetch per paginated batch
  static const int _pageSize = 20;

  // Real-time stream subscription — kept alive for Firestore push updates
  StreamSubscription<List<EmployeeModel>>? _sub;

  // ── Public getters ────────────────────────────────────────────────────────────

  /// Filtered employee list (search + department filter applied)
  List<EmployeeModel> get employees => _filtered;
  List<EmployeeModel> get allEmployees => _employees;
  bool get isLoading => _isLoading;
  /// True while a background "load more" page is in flight
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterDepartment => _filterDepartment;
  /// False when all pages have been fetched — hides the spinner at list end
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

  // ── Real-time stream — open once and keep alive ───────────────────────────────

  /// Starts a persistent Firestore real-time stream for the employee list.
  /// Safe to call multiple times — second call is a no-op if already listening.
  void listenToEmployees() {
    if (_sub != null) return; // already listening — never restart

    _isLoading = true;
    notifyListeners();

    _sub = _service.getEmployeesStream().listen(
      (list) {
        _employees = list;
        _isLoading = false;
        _error = null;
        // Every Consumer<EmployeeProvider> rebuilds instantly due to
        // Firestore push notifications — no polling needed
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

  /// Loads the next page of employees from Firestore using cursor-based pagination.
  ///
  /// - Skips if already loading more or no additional pages exist.
  /// - Appends new employees to the existing list.
  /// - Updates [_lastDocument] so the next call continues from the right cursor.
  /// - Sets [_hasMore] to false when the last page is reached.
  Future<void> loadMoreEmployees() async {
    // Guard: avoid duplicate in-flight requests or loading past the last page
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

      // Avoid duplicates — merge by ID
      final existingIds = _employees.map((e) => e.id).toSet();
      final fresh = newEmployees.where((e) => !existingIds.contains(e.id)).toList();
      _employees = [..._employees, ...fresh];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ── Refresh ───────────────────────────────────────────────────────────────────

  /// Resets pagination state and re-starts the real-time stream from scratch.
  ///
  /// Called by the [RefreshIndicator] in the employee list screen.
  /// Cancels the existing Firestore subscription and re-subscribes, which
  /// triggers an immediate snapshot push — so the UI updates without delay.
  Future<void> refresh() async {
    // Cancel the existing subscription so we get a fresh snapshot on re-listen
    _sub?.cancel();
    _sub = null;

    // Reset pagination cursors
    _lastDocument = null;
    _hasMore = true;

    // Re-open the real-time stream — listenToEmployees is idempotent when _sub is null
    listenToEmployees();

    // Wait briefly so RefreshIndicator shows before the UI settles
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
