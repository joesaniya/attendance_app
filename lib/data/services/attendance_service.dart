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

  Future<AttendanceModel> markLogin(EmployeeModel employee,
      {String? localPhotoPath}) async {
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
      breaks: [],
      lunches: [],
    );

    final isOnline = await _networkService.isConnected();
    if (!isOnline) {
      final localMap = _toLocalMap(attendance, id, dateOnly, now, synced: 0);
      if (localPhotoPath != null) localMap['localPhotoPath'] = localPhotoPath;
      await _localDbService.saveAttendance(localMap);
      return attendance;
    }

    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .set(attendance.toMap());

    final localMap = _toLocalMap(attendance, id, dateOnly, now, synced: 1);
    await _localDbService.saveAttendance(localMap);

    return attendance;
  }

  Future<AttendanceModel> markLogout(String employeeId,
      {String? localPhotoPath}) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);

    final existing = await getTodayAttendance(employeeId);
    if (existing == null) {
      throw Exception('No login record found for today');
    }

    // Close any open break/lunch before logging out
    List<BreakRecord> finalBreaks = List.from(existing.breaks);
    List<LunchRecord> finalLunches = List.from(existing.lunches);

    if (existing.isOnBreak) {
      final last = finalBreaks.removeLast();
      finalBreaks.add(BreakRecord(breakOut: last.breakOut, breakIn: now));
    }
    if (existing.isOnLunch) {
      final last = finalLunches.removeLast();
      finalLunches.add(LunchRecord(lunchOut: last.lunchOut, lunchIn: now));
    }

    final tempRecord = existing.copyWith(
      breaks: finalBreaks,
      lunches: finalLunches,
    );

    final totalBreak = tempRecord.totalBreakHours;
    final totalLunch = tempRecord.totalLunchHours;
    final grossHours = existing.loginTime != null
        ? now.difference(existing.loginTime!).inMinutes / 60.0
        : 0.0;
    final netWorkHours = (grossHours - totalBreak - totalLunch)
        .clamp(0.0, double.infinity);

    final updated = existing.copyWith(
      logoutTime: now,
      status: AppConstants.statusPresent,
      workHours: netWorkHours,
      breaks: finalBreaks,
      lunches: finalLunches,
    );

    final isOnline = await _networkService.isConnected();
    if (!isOnline) {
      final localMap = _toLocalMap(
          updated, id, updated.date, existing.loginTime ?? now,
          synced: 0);
      localMap['logoutTime'] = now.toIso8601String();
      if (localPhotoPath != null) localMap['localPhotoPath'] = localPhotoPath;
      await _localDbService.saveAttendance(localMap);
      return updated;
    }

    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(id)
        .update({
      'logoutTime': now,
      'status': AppConstants.statusPresent,
      'workHours': netWorkHours,
      'breaks': finalBreaks.map((b) => b.toMap()).toList(),
      'lunches': finalLunches.map((l) => l.toMap()).toList(),
    });

    final localMap = _toLocalMap(
        updated, id, updated.date, existing.loginTime ?? now,
        synced: 1);
    localMap['logoutTime'] = now.toIso8601String();
    await _localDbService.saveAttendance(localMap);

    return updated;
  }

  // ── Break management ──────────────────────────────────────────────────────────

  Future<AttendanceModel> startBreak(String employeeId) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);
    final existing = await getTodayAttendance(employeeId);
    if (existing == null) throw Exception('No login record found for today');
    if (existing.isOnBreak) throw Exception('Already on a break');
    if (existing.isOnLunch) throw Exception('Currently on lunch — end lunch first');

    final newBreaks = [...existing.breaks, BreakRecord(breakOut: now)];
    await _updateBreaksLunches(id, newBreaks, existing.lunches);
    return existing.copyWith(breaks: newBreaks);
  }

  Future<AttendanceModel> endBreak(String employeeId) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);
    final existing = await getTodayAttendance(employeeId);
    if (existing == null) throw Exception('No login record found for today');
    if (!existing.isOnBreak) throw Exception('Not currently on a break');

    final updatedBreaks = List<BreakRecord>.from(existing.breaks);
    final last = updatedBreaks.removeLast();
    updatedBreaks.add(BreakRecord(breakOut: last.breakOut, breakIn: now));

    await _updateBreaksLunches(id, updatedBreaks, existing.lunches);
    return existing.copyWith(breaks: updatedBreaks);
  }

  Future<AttendanceModel> startLunch(String employeeId) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);
    final existing = await getTodayAttendance(employeeId);
    if (existing == null) throw Exception('No login record found for today');
    if (existing.isOnLunch) throw Exception('Already on lunch');
    if (existing.isOnBreak) throw Exception('Currently on break — end break first');

    final newLunches = [...existing.lunches, LunchRecord(lunchOut: now)];
    await _updateBreaksLunches(id, existing.breaks, newLunches);
    return existing.copyWith(lunches: newLunches);
  }

  Future<AttendanceModel> endLunch(String employeeId) async {
    final now = DateTime.now();
    final id = _getAttendanceId(employeeId, now);
    final existing = await getTodayAttendance(employeeId);
    if (existing == null) throw Exception('No login record found for today');
    if (!existing.isOnLunch) throw Exception('Not currently on lunch');

    final updatedLunches = List<LunchRecord>.from(existing.lunches);
    final last = updatedLunches.removeLast();
    updatedLunches.add(LunchRecord(lunchOut: last.lunchOut, lunchIn: now));

    await _updateBreaksLunches(id, existing.breaks, updatedLunches);
    return existing.copyWith(lunches: updatedLunches);
  }

  Future<void> _updateBreaksLunches(
    String docId,
    List<BreakRecord> breaks,
    List<LunchRecord> lunches,
  ) async {
    await _firestore
        .collection(AppConstants.attendanceCollection)
        .doc(docId)
        .update({
      'breaks': breaks.map((b) => b.toMap()).toList(),
      'lunches': lunches.map((l) => l.toMap()).toList(),
    });
  }

  // ── Queries ───────────────────────────────────────────────────────────────────

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
    final snap = await _firestore
        .collection(AppConstants.attendanceCollection)
        .where('employeeId', isEqualTo: employeeId)
        .get();

    var records = snap.docs
        .map((doc) => AttendanceModel.fromMap(doc.data(), doc.id))
        .toList();

    if (startDate != null) {
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      records = records
          .where((r) =>
              r.date.isAfter(start.subtract(const Duration(seconds: 1))))
          .toList();
    }
    if (endDate != null) {
      final end =
          DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      records = records.where((r) => r.date.isBefore(end)).toList();
    }

    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
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
      'present':
          records.where((r) => r.status == AppConstants.statusPresent).length,
      'absent':
          records.where((r) => r.status == AppConstants.statusAbsent).length,
      'incomplete': records
          .where((r) => r.status == AppConstants.statusIncomplete)
          .length,
      'total': records.length,
    };
  }

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
          'breaks': [],
          'lunches': [],
        });
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  Map<String, dynamic> _toLocalMap(
    AttendanceModel a,
    String id,
    DateTime date,
    DateTime loginTime, {
    required int synced,
  }) {
    return {
      'id': id,
      'employeeId': a.employeeId,
      'employeeName': a.employeeName,
      'employeePhotoUrl': a.employeePhotoUrl,
      'department': a.department,
      'date': date.toIso8601String(),
      'loginTime': loginTime.toIso8601String(),
      'logoutTime': a.logoutTime?.toIso8601String(),
      'status': a.status,
      'workHours': a.workHours,
      'notes': a.notes,
      'isSynced': synced,
    };
  }
}