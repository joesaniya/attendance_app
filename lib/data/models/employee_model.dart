// lib/data/models/employee_model.dart

class EmployeeModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String department;
  final String position;
  final String address;
  final String? photoUrl;
  final String? faceDescriptor; // Base64 encoded face data
  final DateTime joinDate;
  final DateTime createdAt;
  final String createdBy;
  final String createdByRole;
  final String createdByName;
  final bool isActive;
  final String? employeeCode;

  EmployeeModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    required this.position,
    required this.address,
    this.photoUrl,
    this.faceDescriptor,
    required this.joinDate,
    required this.createdAt,
    required this.createdBy,
    required this.createdByRole,
    required this.createdByName,
    this.isActive = true,
    this.employeeCode,
  });

  factory EmployeeModel.fromMap(Map<String, dynamic> map, String docId) {
    return EmployeeModel(
      id: docId,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      department: map['department'] ?? '',
      position: map['position'] ?? '',
      address: map['address'] ?? '',
      photoUrl: map['photoUrl'],
      faceDescriptor: map['faceDescriptor'],
      joinDate: (map['joinDate'] as dynamic)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      createdBy: map['createdBy'] ?? '',
      createdByRole: map['createdByRole'] ?? '',
      createdByName: map['createdByName'] ?? '',
      isActive: map['isActive'] ?? true,
      employeeCode: map['employeeCode'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'department': department,
      'position': position,
      'address': address,
      'photoUrl': photoUrl,
      'faceDescriptor': faceDescriptor,
      'joinDate': joinDate,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'createdByRole': createdByRole,
      'createdByName': createdByName,
      'isActive': isActive,
      'employeeCode': employeeCode,
    };
  }

  EmployeeModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? department,
    String? position,
    String? address,
    String? photoUrl,
    String? faceDescriptor,
    DateTime? joinDate,
    DateTime? createdAt,
    String? createdBy,
    String? createdByRole,
    String? createdByName,
    bool? isActive,
    String? employeeCode,
  }) {
    return EmployeeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      department: department ?? this.department,
      position: position ?? this.position,
      address: address ?? this.address,
      photoUrl: photoUrl ?? this.photoUrl,
      faceDescriptor: faceDescriptor ?? this.faceDescriptor,
      joinDate: joinDate ?? this.joinDate,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByRole: createdByRole ?? this.createdByRole,
      createdByName: createdByName ?? this.createdByName,
      isActive: isActive ?? this.isActive,
      employeeCode: employeeCode ?? this.employeeCode,
    );
  }
}
