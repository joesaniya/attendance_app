// lib/screens/dashboard/admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/employee_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../data/models/attendance_model.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EmployeeProvider>().listenToEmployees();
      context.read<AttendanceProvider>().listenToAttendanceByDate(DateTime.now());
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Row(
        children: [
          // Sidebar (for larger screens)
          if (MediaQuery.of(context).size.width > 768) _buildSidebar(auth),

          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar
                _buildTopBar(auth),

                // Page Content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _DashboardHome(),
                      _EmployeeListPage(),
                      _AttendancePage(),
                      _SettingsPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // Bottom Navigation (mobile)
      bottomNavigationBar: MediaQuery.of(context).size.width <= 768
          ? _buildBottomNav()
          : null,
    );
  }

  Widget _buildSidebar(AuthProvider auth) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F0F1A), Color(0xFF16213E)],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 48),
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'AttendX',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: RoleBadge(role: auth.currentUser?.role ?? ''),
          ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // Nav Items
          ..._navItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isSelected = _selectedIndex == i;

            return GestureDetector(
              onTap: () {
                setState(() => _selectedIndex = i);
                _pageController.jumpToPage(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? item['activeIcon'] : item['icon'],
                      color: isSelected
                          ? AppTheme.primaryLight
                          : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item['label'],
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const Spacer(),

          // User info
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
            child: Row(
              children: [
                AppAvatar(
                  imageUrl: auth.currentUser?.photoUrl,
                  name: auth.currentUser?.name ?? '',
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.currentUser?.name ?? 'Admin',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        auth.currentUser?.email ?? '',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => context.read<AuthProvider>().signOut(),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTopBar(AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 12),
      color: AppTheme.backgroundLight,
      child: Row(
        children: [
          if (MediaQuery.of(context).size.width <= 768) ...[
            // Mobile menu icon + logo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'AttendX',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ] else ...[
            Text(
              _navItems[_selectedIndex]['label'],
              style: AppTextStyles.heading2,
            ),
          ],
          const Spacer(),
          // Date
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              DateFormat('EEE, MMM d').format(DateTime.now()),
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Avatar
          AppAvatar(
            imageUrl: auth.currentUser?.photoUrl,
            name: auth.currentUser?.name ?? 'Admin',
            size: 38,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _navItems.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final isSelected = _selectedIndex == i;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedIndex = i);
                  _pageController.jumpToPage(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? item['activeIcon'] : item['icon'],
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textMuted,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['label'],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static final List<Map<String, dynamic>> _navItems = [
    {
      'label': 'Dashboard',
      'icon': Icons.dashboard_outlined,
      'activeIcon': Icons.dashboard_rounded,
    },
    {
      'label': 'Employees',
      'icon': Icons.people_outline_rounded,
      'activeIcon': Icons.people_rounded,
    },
    {
      'label': 'Attendance',
      'icon': Icons.calendar_today_outlined,
      'activeIcon': Icons.calendar_today_rounded,
    },
    {
      'label': 'Settings',
      'icon': Icons.settings_outlined,
      'activeIcon': Icons.settings_rounded,
    },
  ];
}

// ─── Dashboard Home Tab ───────────────────────────────────────────────────────
class _DashboardHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceProvider>();
    final employees = context.watch<EmployeeProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome
          const Text(
            "Today's Overview",
            style: AppTextStyles.heading2,
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 24),

          // Stats Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              StatCard(
                label: 'Total Workers',
                value: employees.allEmployees.length.toString(),
                icon: Icons.people_rounded,
                color: AppTheme.primaryColor,
              ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
              StatCard(
                label: 'Present Today',
                value: attendance.presentCount.toString(),
                icon: Icons.check_circle_rounded,
                color: AppTheme.successColor,
                subtitle: 'Today',
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
              StatCard(
                label: 'Absent Today',
                value: attendance.absentCount.toString(),
                icon: Icons.cancel_rounded,
                color: AppTheme.errorColor,
                subtitle: 'Today',
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
              StatCard(
                label: 'Incomplete',
                value: attendance.incompleteCount.toString(),
                icon: Icons.pending_rounded,
                color: AppTheme.warningColor,
                subtitle: 'Today',
              ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            ],
          ),
          const SizedBox(height: 28),

          // Recent Attendance
          SectionHeader(
            title: "Today's Attendance",
            actionLabel: 'View All',
            onAction: () {},
          ).animate().fadeIn(delay: 500.ms),
          const SizedBox(height: 16),

          if (attendance.todayAttendance.isEmpty)
            EmptyState(
              icon: Icons.calendar_today_rounded,
              title: 'No Records Yet',
              subtitle:
                  'Attendance records will appear here as employees check in.',
            )
          else
            ...attendance.todayAttendance.take(8).map((record) =>
                _AttendanceListItem(record: record)
                    .animate()
                    .fadeIn(duration: 400.ms)),
        ],
      ),
    );
  }
}

class _AttendanceListItem extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceListItem({required this.record});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AppAvatar(
            imageUrl: record.employeePhotoUrl,
            name: record.employeeName,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.employeeName,
                    style: AppTextStyles.bodyBold),
                const SizedBox(height: 2),
                Text(record.department,
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(status: record.isLoggedIn ? 'logged_in' : record.status),
              const SizedBox(height: 4),
              if (record.loginTime != null)
                Text(
                  DateFormat('hh:mm a').format(record.loginTime!),
                  style: AppTextStyles.caption,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Employee List Page ───────────────────────────────────────────────────────
class _EmployeeListPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search & Add
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: TextField(
                    onChanged:
                        context.read<EmployeeProvider>().setSearchQuery,
                    decoration: const InputDecoration(
                      hintText: 'Search workers...',
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 18, color: AppTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      hintStyle: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () =>
                    Navigator.pushNamed(context, '/add_employee'),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Worker List
        Expanded(
          child: Consumer<EmployeeProvider>(
            builder: (context, provider, _) {
              // ── Loading state ──
              if (provider.isLoading && provider.allEmployees.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Loading workers...',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // ── Error state ──
              if (provider.error != null && provider.allEmployees.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 56,
                          color: AppTheme.errorColor.withOpacity(0.6),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not load workers',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          provider.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: () {
                            provider.clearError();
                            provider.listenToEmployees();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // ── Empty state ──
              if (provider.employees.isEmpty) {
                return EmptyState(
                  icon: Icons.agriculture_rounded,
                  title: 'No Workers Found',
                  subtitle: 'Add farm workers to get started.',
                  actionLabel: 'Add Worker',
                  onAction: () =>
                      Navigator.pushNamed(context, '/add_employee'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: provider.employees.length,
                itemBuilder: (context, index) {
                  final emp = provider.employees[index];
                  return GestureDetector(
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/employee_detail',
                      arguments: emp,
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            AppAvatar(
                                imageUrl: emp.photoUrl,
                                name: emp.name,
                                size: 50),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(emp.name,
                                      style: AppTextStyles.bodyBold),
                                  const SizedBox(height: 2),
                                  Text(
                                    emp.position.isNotEmpty
                                        ? emp.position
                                        : 'Farm Worker',
                                    style: AppTextStyles.caption,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      // Work area badge
                                      if (emp.department.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E7D32)
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.park_outlined,
                                                size: 10,
                                                color: Color(0xFF2E7D32),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                emp.department,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF2E7D32),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      if (emp.employeeCode != null)
                                        Text(
                                          emp.employeeCode!,
                                          style: AppTextStyles.caption,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Attendance Page ──────────────────────────────────────────────────────────
class _AttendancePage extends StatefulWidget {
  @override
  State<_AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<_AttendancePage> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Date Filter
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  DateFormat('MMMM d, yyyy').format(_selectedDate),
                  style: AppTextStyles.bodyBold,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _selectedDate = date);
                      context
                          .read<AttendanceProvider>()
                          .setSelectedDate(date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Change Date',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Consumer<AttendanceProvider>(
            builder: (context, att, _) => Row(
              children: [
                Expanded(
                  child: _MiniStatCard(
                    label: 'Present',
                    value: att.presentCount.toString(),
                    color: AppTheme.successColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStatCard(
                    label: 'Absent',
                    value: att.absentCount.toString(),
                    color: AppTheme.errorColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStatCard(
                    label: 'Incomplete',
                    value: att.incompleteCount.toString(),
                    color: AppTheme.warningColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // List
        Expanded(
          child: Consumer<AttendanceProvider>(
            builder: (context, att, _) {
              if (att.filteredAttendance.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_busy_rounded,
                  title: 'No Records',
                  subtitle: 'No attendance records for this date.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: att.filteredAttendance.length,
                itemBuilder: (context, index) {
                  final record = att.filteredAttendance[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          AppAvatar(
                            imageUrl: record.employeePhotoUrl,
                            name: record.employeeName,
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record.employeeName,
                                    style: AppTextStyles.bodyBold),
                                Text(record.department,
                                    style: AppTextStyles.caption),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (record.loginTime != null) ...[
                                      const Icon(Icons.login_rounded,
                                          size: 12,
                                          color: AppTheme.successColor),
                                      const SizedBox(width: 3),
                                      Text(
                                        DateFormat('hh:mm a')
                                            .format(record.loginTime!),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.successColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    if (record.logoutTime != null) ...[
                                      const SizedBox(width: 12),
                                      const Icon(Icons.logout_rounded,
                                          size: 12,
                                          color: AppTheme.errorColor),
                                      const SizedBox(width: 3),
                                      Text(
                                        DateFormat('hh:mm a')
                                            .format(record.logoutTime!),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.errorColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    if (record.workHours != null) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        record.formattedWorkHours,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(
                              status: record.isLoggedIn
                                  ? 'logged_in'
                                  : record.status),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Settings Page ─────────────────────────────────────────────────────────────
class _SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Card
          GlassCard(
            child: Row(
              children: [
                AppAvatar(
                  imageUrl: auth.currentUser?.photoUrl,
                  name: auth.currentUser?.name ?? '',
                  size: 64,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.currentUser?.name ?? 'Admin',
                        style: AppTextStyles.heading3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        auth.currentUser?.email ?? '',
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(height: 8),
                      RoleBadge(role: auth.currentUser?.role ?? ''),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Options
          if (auth.isSuperAdmin) ...[
            _SettingsItem(
              icon: Icons.person_add_rounded,
              label: 'Create Manager Account',
              onTap: () =>
                  Navigator.pushNamed(context, '/create_manager'),
            ),
            const SizedBox(height: 8),
          ],
          _SettingsItem(
            icon: Icons.people_rounded,
            label: 'Manage Employees',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.bar_chart_rounded,
            label: 'Attendance Reports',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.logout_rounded,
            label: 'Sign Out',
            color: AppTheme.errorColor,
            onTap: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: color.withOpacity(0.5), size: 20),
          ],
        ),
      ),
    );
  }
}
