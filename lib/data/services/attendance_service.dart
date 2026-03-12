// lib/data/services/attendance_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/attendance_model.dart';
import '../models/employee_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/network_service.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalDbService _localDbService = LocalDbService();
  final NetworkService _networkService = NetworkService();

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getAttendanceId(String employeeId, DateTime date) {
    return '${employeeId}_${_getDateKey(date)}';
  }

  /// Real-time stream for a single employee's today attendance
  Stream<AttendanceModel?> getTodayAttendanceStream(String employeeId) {
    final today = DateTime.now();
    final id = _getAttendanceId(employeeId, today);
    return _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .snapshots()
        .map((snap) {
          if (snap.exists && snap.data() != null) {
            return AttendanceModel.fromMap(snap.data()!, snap.id);
          }
          return null;
        });
  }

  Future<AttendanceModel?> getTodayAttendance(String employeeId) async {
    final today = DateTime.now();
    final id = _getAttendanceId(employeeId, today);

    final isOnline = await _networkService.isConnected();
    if (!isOnline) {
       final localRec = await _localDbService.getTodayAttendance(id);
       if (localRec != null) {
         return AttendanceModel.fromMap(localRec, id);
       }
       return null;
    }

    final doc = await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .get();

    if (doc.exists) {
      return AttendanceModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  Future<AttendanceModel> markLogin(EmployeeModel employee, {String? localPhotoPath}) async {
    final now = DateTime.now();
    final dateOnly = DateTime(now.year, now.month, now.day);
    final id = _getAttendanceId(employee.id, now);

    final attendance = AttendanceModel(
      id: id,
      employeeId: employee.id,
      employeeName: employee.name,
      employeePhotoUrl: employee.photoUrl,
      department: employee.department,
      date: dateOnly,
      loginTime: now,
      status: AppConstants.statusPresent,
    );

    final isOnline = await _networkService.isConnected();
    if (!isOnline) {
      final localMap = attendance.toMap();
      localMap['id'] = id;
      localMap['date'] = dateOnly.toIso8601String();
      localMap['loginTime'] = now.toIso8601String();
      localMap['isSynced'] = 0;
      if (localPhotoPath != null) {
        localMap['localPhotoPath'] = localPhotoPath;
      }
      await _localDbService.saveAttendance(localMap);
      return attendance;
    }

    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .set(attendance.toMap());

    // Cache locally
    final localMap = attendance.toMap();
    localMap['id'] = id;
    localMap['date'] = dateOnly.toIso8601String();
    localMap['loginTime'] = now.toIso8601String();
    localMap['isSynced'] = 1;
    await _localDbService.saveAttendance(localMap);

    return attendance;
  }

  Future<AttendanceModel> markLogout(String employeeId, {String? localPhotoPath}) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);

    final existingAppModel = await getTodayAttendance(employeeId);
    if (existingAppModel == null) {
      throw Exception('No login record found for today');
    }

    final existing = existingAppModel;
    final workHours = existing.loginTime != null
        ? now.difference(existing.loginTime!).inMinutes / 60.0
        : 0.0;

    final updated = existing.copyWith(
      logoutTime: now,
      status: AppConstants.statusPresent,
      workHours: workHours,
    );

    final isOnline = await _networkService.isConnected();
    if (!isOnline) {
      final localMap = updated.toMap();
      localMap['id'] = id;
      localMap['date'] = updated.date.toIso8601String();
      if (updated.loginTime != null) {
         localMap['loginTime'] = updated.loginTime!.toIso8601String();
      }
      localMap['logoutTime'] = now.toIso8601String();
      localMap['isSynced'] = 0;
      if (localPhotoPath != null) {
        localMap['localPhotoPath'] = localPhotoPath;
      }
      await _localDbService.saveAttendance(localMap);
      return updated;
    }

    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .update({
          'logoutTime': now,
          'status': AppConstants.statusPresent,
          'workHours': workHours,
        });

    final localMap = updated.toMap();
    localMap['id'] = id;
    localMap['date'] = updated.date.toIso8601String();
    if (updated.loginTime != null) {
       localMap['loginTime'] = updated.loginTime!.toIso8601String();
    }
    localMap['logoutTime'] = now.toIso8601String();
    localMap['isSynced'] = 1;
    await _localDbService.saveAttendance(localMap);

    return updated;
  }

  Stream<List<AttendanceModel>> getAttendanceByDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final nextDay = dateOnly.add(const Duration(days: 1));

    return _firestore
        .collection(AppConstants.attendanceCollection)
        .where('date', isGreaterThanOrEqualTo: dateOnly)
        .where('date', isLessThan: nextDay)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<AttendanceModel>> getEmployeeAttendance(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Query only by employeeId to avoid composite index requirement.
    // Filter by date in-memory after fetching.
    final snap = await _firestore
        .collection(AppConstants.attendanceCollection)
        .where('employeeId', isEqualTo: employeeId)
        .get();

    var records = snap.docs
        .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
        .toList();

    // Filter by date range in memory
    if (startDate != null) {
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      records = records
          .where(
            (r) => r.date.isAfter(start.subtract(const Duration(seconds: 1))),
          )
          .toList();
    }
    if (endDate != null) {
      final end = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );
      records = records.where((r) => r.date.isBefore(end)).toList();
    }

    // Sort by date descending
    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  Stream<List<AttendanceModel>> getRecentAttendance({int limit = 50}) {
    return _firestore
        .collection(AppConstants.attendanceCollection)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<Map<String, int>> getMonthlyStats(int year, int month) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    final snap = await _firestore
        .collection(AppConstants.attendanceCollection)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThan: endDate)
        .get();

    final records = snap.docs
        .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
        .toList();

    return {
      'present': records
          .where((r) => r.status == AppConstants.statusPresent)
          .length,
      'absent': records
          .where((r) => r.status == AppConstants.statusAbsent)
          .length,
      'incomplete': records
          .where((r) => r.status == AppConstants.statusIncomplete)
          .length,
      'total': records.length,
    };
  }

  // Mark absent for employees who didn't log in
  Future<void> markAbsentEmployees(List<EmployeeModel> employees) async {
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);

    for (final employee in employees) {
      final id = _getAttendanceId(employee.id, today);
      final doc = await _firestore
          .collection(AppConstants.attendanceCollection)
          .doc(id)
          .get();

      if (!doc.exists) {
        await _firestore
            .collection(AppConstants.attendanceCollection)
            .doc(id)
            .set({
              'employeeId': employee.id,
              'employeeName': employee.name,
              'employeePhotoUrl': employee.photoUrl,
              'department': employee.department,
              'date': dateOnly,
              'loginTime': null,
              'logoutTime': null,
              'status': AppConstants.statusAbsent,
              'workHours': null,
            });
      }
    }
  }
}

/*
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/attendance_model.dart';
import '../models/employee_model.dart';
import '../../core/constants/app_constants.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getAttendanceId(String employeeId, DateTime date) {
    return '${employeeId}_${_getDateKey(date)}';
  }

  Future<AttendanceModel?> getTodayAttendance(String employeeId) async {
    final today = DateTime.now();
    final id = _getAttendanceId(employeeId, today);

    final doc = await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .get();

    if (doc.exists) {
      return AttendanceModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  Future<AttendanceModel> markLogin(EmployeeModel employee) async {
    final now = DateTime.now();
    final dateOnly = DateTime(now.year, now.month, now.day);
    final id = _getAttendanceId(employee.id, now);

    final attendance = AttendanceModel(
      id: id,
      employeeId: employee.id,
      employeeName: employee.name,
      employeePhotoUrl: employee.photoUrl,
      department: employee.department,
      date: dateOnly,
      loginTime: now,
      status: AppConstants.statusPresent,
    );

    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .set(attendance.toMap());

    return attendance;
  }

  Future<AttendanceModel> markLogout(String employeeId) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);

    final doc = await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .get();

    if (!doc.exists) {
      throw Exception('No login record found for today');
    }

    final existing = AttendanceModel.fromMap(doc.data()!, doc.id);
    final workHours = existing.loginTime != null
        ? now.difference(existing.loginTime!).inMinutes / 60.0
        : 0.0;

    final updated = existing.copyWith(
      logoutTime: now,
      status: AppConstants.statusPresent,
      workHours: workHours,
    );

    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .update({
      'logoutTime': now,
      'status': AppConstants.statusPresent,
      'workHours': workHours,
    });

    return updated;
  }

  Stream<List<AttendanceModel>> getAttendanceByDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final nextDay = dateOnly.add(const Duration(days: 1));

    return _firestore
        .collection(AppConstants.attendanceCollection)
        .where('date', isGreaterThanOrEqualTo: dateOnly)
        .where('date', isLessThan: nextDay)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<List<AttendanceModel>> getEmployeeAttendance(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query query = _firestore
        .collection(AppConstants.attendanceCollection)
        .where('employeeId', isEqualTo: employeeId);

    if (startDate != null) {
      query = query.where('date',
          isGreaterThanOrEqualTo: DateTime(
              startDate.year, startDate.month, startDate.day));
    }
    if (endDate != null) {
      query = query.where('date',
          isLessThanOrEqualTo:
              DateTime(endDate.year, endDate.month, endDate.day));
    }

    final snap = await query.get();
    return snap.docs
        .map((doc) => AttendanceModel.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Stream<List<AttendanceModel>> getRecentAttendance({int limit = 50}) {
    return _firestore
        .collection(AppConstants.attendanceCollection)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<Map<String, int>> getMonthlyStats(int year, int month) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    final snap = await _firestore
        .collection(AppConstants.attendanceCollection)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThan: endDate)
        .get();

    final records = snap.docs
        .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
        .toList();

    return {
      'present': records.where((r) => r.status == AppConstants.statusPresent).length,
      'absent': records.where((r) => r.status == AppConstants.statusAbsent).length,
      'incomplete': records.where((r) => r.status == AppConstants.statusIncomplete).length,
      'total': records.length,
    };
  }

  // Mark absent for employees who didn't log in
  Future<void> markAbsentEmployees(List<EmployeeModel> employees) async {
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);

    for (final employee in employees) {
      final id = _getAttendanceId(employee.id, today);
      final doc = await _firestore
          .collection(AppConstants.attendanceCollection)
          .doc(id)
          .get();

      if (!doc.exists) {
        await _firestore
            .collection(AppConstants.attendanceCollection)
            .doc(id)
            .set({
          'employeeId': employee.id,
          'employeeName': employee.name,
          'employeePhotoUrl': employee.photoUrl,
          'department': employee.department,
          'date': dateOnly,
          'loginTime': null,
          'logoutTime': null,
          'status': AppConstants.statusAbsent,
          'workHours': null,
        });
      }
    }
  }
}
*/
