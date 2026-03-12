// lib/data/models/user_model.dart

class UserModel {
  final String id;
  final String email;
  final String name;
  final String role;
  final String? photoUrl;
  final DateTime createdAt;
  final String? createdBy;
  final String? createdByRole;
  final bool isActive;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.photoUrl,
    required this.createdAt,
    this.createdBy,
    this.createdByRole,
    this.isActive = true,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      id: docId,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'employee',
      photoUrl: map['photoUrl'],
      createdAt: map['createdAt'] is String 
          ? DateTime.parse(map['createdAt']) 
          : (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      createdBy: map['createdBy'],
      createdByRole: map['createdByRole'],
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'photoUrl': photoUrl,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'createdByRole': createdByRole,
      'isActive': isActive,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    String? photoUrl,
    DateTime? createdAt,
    String? createdBy,
    String? createdByRole,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByRole: createdByRole ?? this.createdByRole,
      isActive: isActive ?? this.isActive,
    );
  }
}
