// lib/core/router/app_router.dart

import 'package:flutter/material.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/dashboard/admin_dashboard_screen.dart';
import '../../screens/employees/employee_form_screen.dart';
import '../../screens/employees/employee_detail_screen.dart';
import '../../screens/attendance/employee_attendance_screen.dart';
import '../../screens/admin/create_manager_screen.dart';
import '../../data/models/employee_model.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case '/dashboard':
        return MaterialPageRoute(
            builder: (_) => const AdminDashboardScreen());

      case '/add_employee':
        return MaterialPageRoute(
            builder: (_) => const EmployeeFormScreen());

      case '/employee_detail':
        final employee = settings.arguments as EmployeeModel;
        return MaterialPageRoute(
          builder: (_) => EmployeeDetailScreen(employee: employee),
        );

      case '/employee_attendance':
        return MaterialPageRoute(
            builder: (_) => const EmployeeAttendanceScreen());

      case '/create_manager':
        return MaterialPageRoute(
            builder: (_) => const CreateManagerScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Route ${settings.name} not found'),
            ),
          ),
        );
    }
  }
}
