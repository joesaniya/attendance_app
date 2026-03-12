// lib/data/models/attendance_model.dart

class AttendanceModel {
  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeePhotoUrl;
  final String department;
  final DateTime date;
  final DateTime? loginTime;
  final DateTime? logoutTime;
  final String status; // present, absent, incomplete
  final double? workHours;
  final String? notes;

  AttendanceModel({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.employeePhotoUrl,
    required this.department,
    required this.date,
    this.loginTime,
    this.logoutTime,
    required this.status,
    this.workHours,
    this.notes,
  });

  factory AttendanceModel.fromMap(Map<String, dynamic> map, String docId) {
    return AttendanceModel(
      id: docId,
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      employeePhotoUrl: map['employeePhotoUrl'],
      department: map['department'] ?? '',
      date: (map['date'] as dynamic)?.toDate() ?? DateTime.now(),
      loginTime: (map['loginTime'] as dynamic)?.toDate(),
      logoutTime: (map['logoutTime'] as dynamic)?.toDate(),
      status: map['status'] ?? 'absent',
      workHours: (map['workHours'] as num?)?.toDouble(),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeePhotoUrl': employeePhotoUrl,
      'department': department,
      'date': date,
      'loginTime': loginTime,
      'logoutTime': logoutTime,
      'status': status,
      'workHours': workHours,
      'notes': notes,
    };
  }

  AttendanceModel copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    String? employeePhotoUrl,
    String? department,
    DateTime? date,
    DateTime? loginTime,
    DateTime? logoutTime,
    String? status,
    double? workHours,
    String? notes,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      employeePhotoUrl: employeePhotoUrl ?? this.employeePhotoUrl,
      department: department ?? this.department,
      date: date ?? this.date,
      loginTime: loginTime ?? this.loginTime,
      logoutTime: logoutTime ?? this.logoutTime,
      status: status ?? this.status,
      workHours: workHours ?? this.workHours,
      notes: notes ?? this.notes,
    );
  }

  bool get isLoggedIn => loginTime != null && logoutTime == null;
  bool get isCompleted => loginTime != null && logoutTime != null;

  String get formattedWorkHours {
    if (workHours == null) return '--';
    final hours = workHours!.floor();
    final minutes = ((workHours! - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }
}
