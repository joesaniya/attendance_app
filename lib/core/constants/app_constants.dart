// lib/core/constants/app_constants.dart

class AppConstants {
  static const String appName = 'AttendX';
  static const String appVersion = '1.0.0';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String employeesCollection = 'employees';
  static const String attendanceCollection = 'attendance';

  // User Roles
  static const String roleSuperAdmin = 'super_admin';
  static const String roleManager = 'manager';
  static const String roleEmployee = 'employee';

  // Attendance Status
  static const String statusPresent = 'present';
  static const String statusAbsent = 'absent';
  static const String statusIncomplete = 'incomplete';

  // Storage Paths
  static const String employeePhotosPath = 'employee_photos';

  // Default credentials (for demo)
  static const String defaultAdminEmail = 'admin@attendx.com';
  static const String defaultAdminPassword = 'Admin@123';
  static const String defaultManagerEmail = 'manager@attendx.com';
  static const String defaultManagerPassword = 'Manager@123';
}
