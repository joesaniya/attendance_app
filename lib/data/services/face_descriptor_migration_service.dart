// lib/data/services/face_descriptor_migration_service.dart
//
// ONE-TIME MIGRATION — rebuilds pixel-level face descriptors for every employee
// that still has an old geometry-only descriptor stored in Firestore.
//
// HOW IT WORKS:
//   1. Loads every active employee from Firestore.
//   2. Checks whether their faceDescriptor is legacy (no LBP data).
//   3. For legacy employees: downloads their profile photo, runs ML Kit face
//      detection on it, builds a full LBP + intensity + geometry descriptor,
//      and writes it back to Firestore.
//   4. Reports results per-employee so the admin UI can show progress.
//
// No employee needs to physically re-register — everything is automatic as long
// as a profile photo exists. If a photo is missing or no face is detectable,
// that employee is flagged for manual re-registration.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/employee_model.dart';
import 'face_detection_service.dart';
import '../../core/constants/app_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────
enum MigrationStatus { success, skippedAlreadyNew, skippedNoPhoto, failed }

class EmployeeMigrationResult {
  final EmployeeModel employee;
  final MigrationStatus status;
  final String? errorMessage;

  const EmployeeMigrationResult({
    required this.employee,
    required this.status,
    this.errorMessage,
  });
}

class MigrationSummary {
  final int total;
  final int succeeded;
  final int skippedAlreadyNew;
  final int skippedNoPhoto;
  final int failed;
  final List<EmployeeMigrationResult> results;

  const MigrationSummary({
    required this.total,
    required this.succeeded,
    required this.skippedAlreadyNew,
    required this.skippedNoPhoto,
    required this.failed,
    required this.results,
  });

  bool get allDone => failed == 0 && skippedNoPhoto == 0;
  int get needsManualReg => skippedNoPhoto + failed;
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────
class FaceDescriptorMigrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FaceDetectionService _faceService = FaceDetectionService();

  /// Returns true if any active employee still has a legacy descriptor.
  Future<bool> hasPendingMigrations() async {
    try {
      _faceService.initialize();
      final snap = await _firestore
          .collection(AppConstants.employeesCollection)
          .get();

      for (final doc in snap.docs) {
        final emp = EmployeeModel.fromMap(doc.data(), doc.id);
        if (emp.isActive == false) continue;
        if (emp.faceDescriptor == null || emp.faceDescriptor!.isEmpty) continue;
        if (_isLegacy(emp.faceDescriptor!)) return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Migration] hasPendingMigrations error: $e');
      return false;
    }
  }

  /// Run the full migration for all employees.
  /// [onProgress] is called after each employee is processed.
  Future<MigrationSummary> runMigration({
    void Function(int processed, int total, EmployeeMigrationResult latest)?
    onProgress,
  }) async {
    _faceService.initialize();

    final snap = await _firestore
        .collection(AppConstants.employeesCollection)
        .get();

    final employees = snap.docs
        .map((d) => EmployeeModel.fromMap(d.data(), d.id))
        .where((e) => e.isActive != false)
        .toList();

    final results = <EmployeeMigrationResult>[];
    int processed = 0;

    for (final emp in employees) {
      final result = await _migrateOne(emp);
      results.add(result);
      processed++;
      onProgress?.call(processed, employees.length, result);
    }

    return MigrationSummary(
      total: employees.length,
      succeeded: results
          .where((r) => r.status == MigrationStatus.success)
          .length,
      skippedAlreadyNew: results
          .where((r) => r.status == MigrationStatus.skippedAlreadyNew)
          .length,
      skippedNoPhoto: results
          .where((r) => r.status == MigrationStatus.skippedNoPhoto)
          .length,
      failed: results.where((r) => r.status == MigrationStatus.failed).length,
      results: results,
    );
  }

  Future<EmployeeMigrationResult> _migrateOne(EmployeeModel emp) async {
    // Already has pixel-level descriptor — skip
    if (emp.faceDescriptor != null &&
        emp.faceDescriptor!.isNotEmpty &&
        !_isLegacy(emp.faceDescriptor!)) {
      return EmployeeMigrationResult(
        employee: emp,
        status: MigrationStatus.skippedAlreadyNew,
      );
    }

    // No profile photo — cannot auto-migrate
    if (emp.photoUrl == null || emp.photoUrl!.isEmpty) {
      return EmployeeMigrationResult(
        employee: emp,
        status: MigrationStatus.skippedNoPhoto,
        errorMessage:
            'No profile photo found. Manual re-registration required.',
      );
    }

    try {
      final newDescriptor = await _faceService.buildFaceDescriptorFromPhotoUrl(
        emp.photoUrl!,
      );

      if (newDescriptor == null) {
        return EmployeeMigrationResult(
          employee: emp,
          status: MigrationStatus.failed,
          errorMessage:
              'No face detected in stored photo. Manual re-registration required.',
        );
      }

      // Write new descriptor back to Firestore
      await _firestore
          .collection(AppConstants.employeesCollection)
          .doc(emp.id)
          .update({'faceDescriptor': newDescriptor});

      debugPrint('[Migration] ✓ ${emp.name}');
      return EmployeeMigrationResult(
        employee: emp,
        status: MigrationStatus.success,
      );
    } catch (e) {
      debugPrint('[Migration] ✗ ${emp.name}: $e');
      return EmployeeMigrationResult(
        employee: emp,
        status: MigrationStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Simple heuristic: legacy descriptors have an 'lbp' key that is either
  /// absent or all zeros (geometry-only format from the old service).
  bool _isLegacy(String descriptorJson) {
    try {
      final m = jsonDecode(descriptorJson) as Map<String, dynamic>;
      final lbp = m['lbp'] as List?;
      if (lbp == null || lbp.isEmpty) return true;
      return !lbp.any((v) => (v as num).toDouble() != 0.0);
    } catch (_) {
      return true;
    }
  }
}
