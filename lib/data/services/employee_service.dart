// lib/data/services/employee_service.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/employee_model.dart';
import '../../core/constants/app_constants.dart';

class EmployeeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  Stream<List<EmployeeModel>> getEmployeesStream() {
    return _firestore
        .collection(AppConstants.employeesCollection)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => EmployeeModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<List<EmployeeModel>> getAllEmployees() async {
    final snap = await _firestore
        .collection(AppConstants.employeesCollection)
        .where('isActive', isEqualTo: true)
        .get();
    return snap.docs
        .map((doc) => EmployeeModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<EmployeeModel?> getEmployeeById(String id) async {
    final doc = await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(id)
        .get();
    if (doc.exists) {
      return EmployeeModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  Future<String?> uploadEmployeePhoto(File photoFile, String employeeId) async {
    try {
      final ref = _storage.ref().child(
          '${AppConstants.employeePhotosPath}/$employeeId/profile.jpg');
      await ref.putFile(photoFile);
      return await ref.getDownloadURL();
    } catch (e) {
      rethrow;
    }
  }

  Future<EmployeeModel> createEmployee({
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
  }) async {
    try {
      final employeeId = _uuid.v4();
      final employeeCode = 'EMP${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      String? photoUrl;
      if (photoFile != null) {
        photoUrl = await uploadEmployeePhoto(photoFile, employeeId);
      }

      final employee = EmployeeModel(
        id: employeeId,
        name: name,
        email: email,
        phone: phone,
        department: department,
        position: position,
        address: address,
        photoUrl: photoUrl,
        joinDate: DateTime.now(),
        createdAt: DateTime.now(),
        createdBy: createdBy,
        createdByRole: createdByRole,
        createdByName: createdByName,
        employeeCode: employeeCode,
      );

      await _firestore
          .collection(AppConstants.employeesCollection)
          .doc(employeeId)
          .set(employee.toMap());

      return employee;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateEmployee({
    required String employeeId,
    required Map<String, dynamic> data,
    File? newPhotoFile,
  }) async {
    try {
      if (newPhotoFile != null) {
        final photoUrl = await uploadEmployeePhoto(newPhotoFile, employeeId);
        data['photoUrl'] = photoUrl;
      }
      await _firestore
          .collection(AppConstants.employeesCollection)
          .doc(employeeId)
          .update(data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteEmployee(String employeeId) async {
    try {
      // Soft delete
      await _firestore
          .collection(AppConstants.employeesCollection)
          .doc(employeeId)
          .update({'isActive': false});
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateFaceDescriptor(
      String employeeId, String faceDescriptor) async {
    await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(employeeId)
        .update({'faceDescriptor': faceDescriptor});
  }
}
