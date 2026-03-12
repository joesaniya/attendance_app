// lib/data/services/employee_service.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/employee_model.dart';
import '../../core/constants/app_constants.dart';

class EmployeeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage   _storage   = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  /// Fetches ALL documents in the collection with NO where-clause filters.
  /// We filter client-side so pre-existing records that lack isActive / createdAt
  /// fields are never silently excluded by Firestore.
  Stream<List<EmployeeModel>> getEmployeesStream() {
    return _firestore
        .collection(AppConstants.employeesCollection)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => EmployeeModel.fromMap(doc.data(), doc.id))
              .where((emp) =>
                  emp.isActive == null ||   // field absent → treat as active
                  emp.isActive == true)     // field present and true
              .toList();
          // Newest first — safe client-side sort
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<List<EmployeeModel>> getAllEmployees() async {
    final snap = await _firestore
        .collection(AppConstants.employeesCollection)
        .get();
    return snap.docs
        .map((doc) => EmployeeModel.fromMap(doc.data(), doc.id))
        .where((emp) => emp.isActive == null || emp.isActive == true)
        .toList();
  }

  Future<EmployeeModel?> getEmployeeById(String id) async {
    final doc = await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    return EmployeeModel.fromMap(doc.data()!, doc.id);
  }

  Future<String?> uploadEmployeePhoto(File photoFile, String employeeId) async {
    final ref = _storage
        .ref()
        .child('${AppConstants.employeePhotosPath}/$employeeId/profile.jpg');
    await ref.putFile(photoFile);
    return ref.getDownloadURL();
  }

  Future<EmployeeModel> createEmployee({
    required String name,
    required String email,
    required String phone,
    required String department,
    required String position,
    required String address,
    File?   photoFile,
    required String createdBy,
    required String createdByRole,
    required String createdByName,
    String? faceDescriptor,
  }) async {
    final employeeId   = _uuid.v4();
    final employeeCode =
        'EMP${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    String? photoUrl;
    if (photoFile != null) {
      photoUrl = await uploadEmployeePhoto(photoFile, employeeId);
    }

    final employee = EmployeeModel(
      id:            employeeId,
      name:          name,
      email:         email,
      phone:         phone,
      department:    department,
      position:      position,
      address:       address,
      photoUrl:      photoUrl,
      faceDescriptor: faceDescriptor,
      joinDate:      DateTime.now(),
      createdAt:     DateTime.now(),
      createdBy:     createdBy,
      createdByRole: createdByRole,
      createdByName: createdByName,
      isActive:      true,
      employeeCode:  employeeCode,
    );

    await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(employeeId)
        .set(employee.toMap());

    return employee;
  }

  Future<void> updateEmployee({
    required String employeeId,
    required Map<String, dynamic> data,
    File? newPhotoFile,
  }) async {
    if (newPhotoFile != null) {
      data['photoUrl'] = await uploadEmployeePhoto(newPhotoFile, employeeId);
    }
    await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(employeeId)
        .update(data);
  }

  Future<void> deleteEmployee(String employeeId) async {
    // Soft-delete: set isActive = false so the stream excludes it
    await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(employeeId)
        .update({'isActive': false});
  }

  Future<void> updateFaceDescriptor(String employeeId, String descriptor) async {
    await _firestore
        .collection(AppConstants.employeesCollection)
        .doc(employeeId)
        .update({'faceDescriptor': descriptor});
  }
}