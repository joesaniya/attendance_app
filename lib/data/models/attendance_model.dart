// lib/data/models/attendance_model.dart

class BreakRecord {
  final DateTime breakOut;
  final DateTime? breakIn;

  BreakRecord({required this.breakOut, this.breakIn});

  double get durationHours {
    if (breakIn == null) return 0;
    return breakIn!.difference(breakOut).inMinutes / 60.0;
  }

  factory BreakRecord.fromMap(Map<String, dynamic> map) {
    return BreakRecord(
      breakOut: _parseDateTime(map['breakOut']) ?? DateTime.now(),
      breakIn: _parseDateTime(map['breakIn']),
    );
  }

  Map<String, dynamic> toMap() => {
        'breakOut': breakOut.toIso8601String(),
        'breakIn': breakIn?.toIso8601String(),
      };

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}

class LunchRecord {
  final DateTime lunchOut;
  final DateTime? lunchIn;

  LunchRecord({required this.lunchOut, this.lunchIn});

  double get durationHours {
    if (lunchIn == null) return 0;
    return lunchIn!.difference(lunchOut).inMinutes / 60.0;
  }

  factory LunchRecord.fromMap(Map<String, dynamic> map) {
    return LunchRecord(
      lunchOut: _parseDateTime(map['lunchOut']) ?? DateTime.now(),
      lunchIn: _parseDateTime(map['lunchIn']),
    );
  }

  Map<String, dynamic> toMap() => {
        'lunchOut': lunchOut.toIso8601String(),
        'lunchIn': lunchIn?.toIso8601String(),
      };

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}

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
  final List<BreakRecord> breaks;
  final List<LunchRecord> lunches;

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
    this.breaks = const [],
    this.lunches = const [],
  });

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map, String docId) {
    List<BreakRecord> breaks = [];
    if (map['breaks'] != null) {
      final rawBreaks = map['breaks'] as List<dynamic>;
      breaks = rawBreaks
          .map((b) => BreakRecord.fromMap(b as Map<String, dynamic>))
          .toList();
    }

    List<LunchRecord> lunches = [];
    if (map['lunches'] != null) {
      final rawLunches = map['lunches'] as List<dynamic>;
      lunches = rawLunches
          .map((l) => LunchRecord.fromMap(l as Map<String, dynamic>))
          .toList();
    }

    return AttendanceModel(
      id: docId,
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      employeePhotoUrl: map['employeePhotoUrl'],
      department: map['department'] ?? '',
      date: _parseDateTime(map['date']) ?? DateTime.now(),
      loginTime: _parseDateTime(map['loginTime']),
      logoutTime: _parseDateTime(map['logoutTime']),
      status: map['status'] ?? 'absent',
      workHours: (map['workHours'] as num?)?.toDouble(),
      notes: map['notes'],
      breaks: breaks,
      lunches: lunches,
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
      'breaks': breaks.map((b) => b.toMap()).toList(),
      'lunches': lunches.map((l) => l.toMap()).toList(),
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
    List<BreakRecord>? breaks,
    List<LunchRecord>? lunches,
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
      breaks: breaks ?? this.breaks,
      lunches: lunches ?? this.lunches,
    );
  }

  bool get isLoggedIn => loginTime != null && logoutTime == null;
  bool get isCompleted => loginTime != null && logoutTime != null;

  /// True if currently on a break (last break has no breakIn)
  bool get isOnBreak => breaks.isNotEmpty && breaks.last.breakIn == null;

  /// True if currently on lunch (last lunch has no lunchIn)
  bool get isOnLunch => lunches.isNotEmpty && lunches.last.lunchIn == null;

  /// Total break duration in hours (only completed breaks)
  double get totalBreakHours {
    return breaks.fold(0.0, (sum, b) => sum + b.durationHours);
  }

  /// Total lunch duration in hours (only completed lunches)
  double get totalLunchHours {
    return lunches.fold(0.0, (sum, l) => sum + l.durationHours);
  }

  String get formattedWorkHours {
    if (workHours == null) return '--';
    final hours = workHours!.floor();
    final minutes = ((workHours! - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }

  String get formattedBreakHours {
    final h = totalBreakHours;
    final hours = h.floor();
    final minutes = ((h - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }

  String get formattedLunchHours {
    final h = totalLunchHours;
    final hours = h.floor();
    final minutes = ((h - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }
}