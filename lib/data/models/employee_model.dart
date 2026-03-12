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
  final String? faceDescriptor;
  final DateTime joinDate;
  final DateTime createdAt;
  final String createdBy;
  final String createdByRole;
  final String createdByName;
  final bool? isActive; // null = field never existed → treat as active
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
    this.isActive,
    this.employeeCode,
  });

  /// Tolerant parser — every field has a safe fallback.
  /// Works with pre-existing Firebase records that may be missing fields.
  factory EmployeeModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime safeDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      try {
        return (v as dynamic).toDate() as DateTime;
      } catch (_) {
        return DateTime.now();
      }
    }

    bool? safeBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      if (v is int) return v == 1;
      return null;
    }

    return EmployeeModel(
      id: docId,
      name: (map['name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      department: (map['department'] as String?) ?? '',
      position: (map['position'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      photoUrl: map['photoUrl'] as String?,
      faceDescriptor: map['faceDescriptor'] as String?,
      joinDate: safeDate(map['joinDate']),
      createdAt: safeDate(map['createdAt']),
      createdBy: (map['createdBy'] as String?) ?? '',
      createdByRole: (map['createdByRole'] as String?) ?? '',
      createdByName: (map['createdByName'] as String?) ?? '',
      isActive: safeBool(map['isActive']), // properly mapped for SQLite/Firebase
      employeeCode: map['employeeCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
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
    'isActive': isActive ?? true,
    'employeeCode': employeeCode,
  };

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
  }) => EmployeeModel(
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
