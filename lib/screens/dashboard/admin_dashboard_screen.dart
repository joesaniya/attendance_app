// lib/screens/dashboard/admin_dashboard_screen.dart

import 'dart:developer';

import 'package:employee_attendance_app/data/services/attendance_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/employee_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../data/models/attendance_model.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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
      context.read<AttendanceProvider>().listenToAttendanceByDate(
        DateTime.now(),
      );
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
          colors: [AppTheme.primaryDark, AppTheme.cardDark],
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
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                        )
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
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        color: AppTheme.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
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
                    horizontal: 16,
                    vertical: 8,
                  ),
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
          Text(
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
                label: 'Total Employees',
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
            // actionLabel: 'View All',
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
            ...attendance.todayAttendance
                .take(8)
                .map(
                  (record) => _AttendanceListItem(
                    record: record,
                  ).animate().fadeIn(duration: 400.ms),
                ),
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
                Text(record.employeeName, style: AppTextStyles.bodyBold),
                const SizedBox(height: 2),
                Text(record.department, style: AppTextStyles.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(
                status: record.isLoggedIn ? 'logged_in' : record.status,
              ),
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
/// Stateful so we can manage the [ScrollController] for infinite scrolling.
/// Pull-to-refresh is wired to [EmployeeProvider.refresh()].
class _EmployeeListPage extends StatefulWidget {
  @override
  State<_EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<_EmployeeListPage> {
  /// Controls the list — used to detect when user reaches the bottom
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Listen for scroll events — trigger pagination near the bottom
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Called whenever the list scrolls.
  /// If we are within 200px of the bottom and more pages exist, load next batch.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final currentPos = _scrollController.position.pixels;
    // Trigger load-more when user is near the bottom
    if (currentPos >= maxExtent - 200) {
      context.read<EmployeeProvider>().loadMoreEmployees();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search & Add bar
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
                    onChanged: context.read<EmployeeProvider>().setSearchQuery,
                    decoration: const InputDecoration(
                      hintText: 'Search employees...',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      hintStyle: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/add_employee'),
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
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Employee List with pull-to-refresh + infinite scroll
        Expanded(
          child: Consumer<EmployeeProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.employees.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (provider.employees.isEmpty) {
                return EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No Employees Found',
                  subtitle: 'Add employees to get started.',
                  actionLabel: 'Add Employee',
                  onAction: () => Navigator.pushNamed(context, '/add_employee'),
                );
              }

              // RefreshIndicator enables pull-to-refresh
              return RefreshIndicator(
                color: AppTheme.accentColor,
                onRefresh: () => provider.refresh(),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  // +1 for the load-more spinner at the bottom
                  itemCount: provider.employees.length + 1,
                  itemBuilder: (context, index) {
                    // Last item — show spinner or "no more" indicator
                    if (index == provider.employees.length) {
                      if (provider.isLoadingMore) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      // All pages loaded
                      if (!provider.hasMore) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'All employees loaded',
                              style: AppTextStyles.caption,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }

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
                                size: 50,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      emp.name,
                                      style: AppTextStyles.bodyBold,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      emp.position,
                                      style: AppTextStyles.caption,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor
                                                .withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            emp.department,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          emp.employeeCode ?? '',
                                          style: AppTextStyles.caption,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppTheme.textMuted,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'by ${emp.createdByName}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
  bool _isGeneratingPdf = false;

  // ── PDF Download ──────────────────────────────────────────────────────────
  Future<void> _downloadPdf(BuildContext context) async {
    final att = context.read<AttendanceProvider>();
    final auth = context.read<AuthProvider>();

    if (att.filteredAttendance.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attendance records to export'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      // 1. Generate PDF bytes
      final pdfBytes = await AttendancePdfService.generateAttendanceReport(
        records: att.filteredAttendance,
        reportDate: _selectedDate,
        downloadedBy: auth.currentUser?.name ?? 'Admin',
      );

      // 2. Build filename with date stamp
      final d = _selectedDate;
      final fileName =
          'attendance_${d.year}'
          '-${d.month.toString().padLeft(2, '0')}'
          '-${d.day.toString().padLeft(2, '0')}.pdf';

      // 3. Save to device storage
      final savedPath = await _saveToDevice(pdfBytes, fileName);

      if (!mounted) return;

      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'PDF saved to Downloads!',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        savedPath,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save PDF: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  /// Saves PDF bytes directly to the device's Downloads folder.
  /// Returns the saved file path on success, null if permission denied.
  Future<String?> _saveToDevice(List<int> bytes, String fileName) async {
    if (Platform.isAndroid) {
      // ── Android ────────────────────────────────────────────────────────
      // Android 13+ (SDK 33): no WRITE_EXTERNAL_STORAGE needed for Downloads.
      // Android 10–12 (SDK 29–32): permission required.
      // Android 9 and below (SDK ≤ 28): permission required.
      bool needsPermission = false;
      try {
        final sdkResult = await Process.run('getprop', [
          'ro.build.version.sdk',
        ]);
        final sdk = int.tryParse(sdkResult.stdout.toString().trim()) ?? 33;
        needsPermission = sdk <= 32;
      } catch (_) {
        needsPermission = false; // assume modern Android
      }

      if (needsPermission) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Storage permission denied.\n'
                  'Go to Settings → App → Permissions → Storage and allow it.',
                ),
                backgroundColor: AppTheme.warningColor,
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return null;
        }
      }

      // Write to /storage/emulated/0/Download/ — visible in Files app
      final downloadsPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadsPath);
      if (!await dir.exists()) await dir.create(recursive: true);

      final file = File('$downloadsPath/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } else if (Platform.isIOS) {
      // ── iOS ────────────────────────────────────────────────────────────
      // Saves to app Documents directory.
      // Accessible via Files app → Browse → On My iPhone → <AppName>
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File('${docsDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } else {
      // ── Desktop / other ────────────────────────────────────────────────
      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
  }

  Future<void> _downloadPdf1(BuildContext context) async {
    log('generating PDF for ${_selectedDate.toIso8601String()}');
    final att = context.read<AttendanceProvider>();
    final auth = context.read<AuthProvider>();

    if (att.filteredAttendance.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attendance records to export'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      final pdfBytes = await AttendancePdfService.generateAttendanceReport(
        records: att.filteredAttendance,
        reportDate: _selectedDate,
        downloadedBy: auth.currentUser?.name ?? 'Admin',
      );

      // Uses the `printing` package — opens system share/print sheet on
      // Android & iOS; triggers browser download on web.
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename:
            'attendance_report_${_selectedDate.year}'
            '-${_selectedDate.month.toString().padLeft(2, '0')}'
            '-${_selectedDate.day.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        log('PDF generation error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Date Filter + Download Button ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: AppTheme.primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  _fmtHeaderDate(_selectedDate),
                  style: AppTextStyles.bodyBold,
                ),
                const Spacer(),

                // Change Date button
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
                      context.read<AttendanceProvider>().setSelectedDate(date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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

                const SizedBox(width: 10),

                // ── PDF Download button ────────────────────────────────
                GestureDetector(
                  onTap: _isGeneratingPdf ? null : () => _downloadPdf(context),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: _isGeneratingPdf
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF4F46E5)],
                            ),
                      color: _isGeneratingPdf ? AppTheme.borderColor : null,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _isGeneratingPdf
                          ? null
                          : [
                              BoxShadow(
                                color: AppTheme.primaryColor.withOpacity(0.30),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isGeneratingPdf)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.textMuted,
                            ),
                          )
                        else
                          const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          _isGeneratingPdf ? 'Generating…' : 'Export PDF',
                          style: TextStyle(
                            color: _isGeneratingPdf
                                ? AppTheme.textMuted
                                : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Stats Row ────────────────────────────────────────────────────
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

        // ── Attendance List ──────────────────────────────────────────────
        Expanded(
          child: Consumer<AttendanceProvider>(
            builder: (context, att, _) {
              if (att.filteredAttendance.isEmpty) {
                return RefreshIndicator(
                  color: AppTheme.accentColor,
                  onRefresh: () => att.refresh(),
                  child: ListView(
                    children: const [
                      EmptyState(
                        icon: Icons.event_busy_rounded,
                        title: 'No Records',
                        subtitle: 'No attendance records for this date.',
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: AppTheme.accentColor,
                onRefresh: () => att.refresh(),
                child: ListView.builder(
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
                                  Text(
                                    record.employeeName,
                                    style: AppTextStyles.bodyBold,
                                  ),
                                  Text(
                                    record.department,
                                    style: AppTextStyles.caption,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (record.loginTime != null) ...[
                                        const Icon(
                                          Icons.login_rounded,
                                          size: 12,
                                          color: AppTheme.successColor,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          DateFormat(
                                            'hh:mm a',
                                          ).format(record.loginTime!),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.successColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      if (record.logoutTime != null) ...[
                                        const SizedBox(width: 12),
                                        const Icon(
                                          Icons.logout_rounded,
                                          size: 12,
                                          color: AppTheme.errorColor,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          DateFormat(
                                            'hh:mm a',
                                          ).format(record.logoutTime!),
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
                                  : record.status,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _fmtHeaderDate(DateTime dt) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

/*class _AttendancePage extends StatefulWidget {
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
                const Icon(
                  Icons.calendar_today_rounded,
                  color: AppTheme.primaryColor,
                  size: 18,
                ),
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
                      context.read<AttendanceProvider>().setSelectedDate(date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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

        // Attendance List with pull-to-refresh
        Expanded(
          child: Consumer<AttendanceProvider>(
            builder: (context, att, _) {
              if (att.filteredAttendance.isEmpty) {
                return RefreshIndicator(
                  color: AppTheme.accentColor,
                  onRefresh: () => att.refresh(),
                  child: ListView(
                    children: const [
                      EmptyState(
                        icon: Icons.event_busy_rounded,
                        title: 'No Records',
                        subtitle: 'No attendance records for this date.',
                      ),
                    ],
                  ),
                );
              }

              // RefreshIndicator wraps the attendance list
              // Pulling down re-listens to the Firestore stream → instant update
              return RefreshIndicator(
                color: AppTheme.accentColor,
                onRefresh: () => att.refresh(),
                child: ListView.builder(
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
                                  Text(
                                    record.employeeName,
                                    style: AppTextStyles.bodyBold,
                                  ),
                                  Text(
                                    record.department,
                                    style: AppTextStyles.caption,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (record.loginTime != null) ...[
                                        const Icon(
                                          Icons.login_rounded,
                                          size: 12,
                                          color: AppTheme.successColor,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          DateFormat(
                                            'hh:mm a',
                                          ).format(record.loginTime!),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.successColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      if (record.logoutTime != null) ...[
                                        const SizedBox(width: 12),
                                        const Icon(
                                          Icons.logout_rounded,
                                          size: 12,
                                          color: AppTheme.errorColor,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          DateFormat(
                                            'hh:mm a',
                                          ).format(record.logoutTime!),
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
                                  : record.status,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
*/
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
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
    final user = auth.currentUser;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero Profile Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryDark.withOpacity(0.04),
                  Colors.white.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Minimalist Avatar
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: Hero(
                    tag: 'profile_avatar_settings',
                    child: AppAvatar(
                      imageUrl: user?.photoUrl,
                      name: user?.name ?? 'Admin',
                      size: 76,
                    ),
                  ),
                ).animate().scale(
                  delay: 100.ms,
                  duration: 400.ms,
                  curve: Curves.easeOutBack,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Admin',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.05),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.2,
                        ),
                      ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.05),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          (user?.role ?? 'Admin').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Settings Cards ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account & Security',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMuted.withOpacity(0.7),
                    letterSpacing: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ).animate().fadeIn(delay: 500.ms),
                const SizedBox(height: 16),

                if (auth.isSuperAdmin) ...[
                  _PremiumSettingsTile(
                    icon: Icons.person_add_rounded,
                    title: 'Create Manager Account',
                    subtitle: 'Provision a new administrative user',
                    onTap: () =>
                        Navigator.pushNamed(context, '/create_manager'),
                    iconColor: const Color(0xFF6366F1), // Elegant Indigo
                    iconBgColor: const Color(0xFFEEF2FF),
                  ).animate().slideY(begin: 0.1, delay: 550.ms).fadeIn(),
                  const SizedBox(height: 12),
                ],

                _PremiumSettingsTile(
                  icon: Icons.shield_rounded,
                  title: 'Privacy & Security',
                  subtitle: 'Passcodes and biometric setup',
                  onTap: () {},
                  iconColor: const Color(0xFF14B8A6), // Premium Teal
                  iconBgColor: const Color(0xFFF0FDFA),
                ).animate().slideY(begin: 0.1, delay: 600.ms).fadeIn(),
                const SizedBox(height: 12),

                _PremiumSettingsTile(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifications',
                  subtitle: 'Manage alert preferences',
                  onTap: () {},
                  iconColor: const Color(0xFFF59E0B), // Warm Amber
                  iconBgColor: const Color(0xFFFFFBEB),
                ).animate().slideY(begin: 0.1, delay: 650.ms).fadeIn(),

                const SizedBox(height: 32),

                Text(
                  'System',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMuted.withOpacity(0.7),
                    letterSpacing: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ).animate().fadeIn(delay: 700.ms),
                const SizedBox(height: 16),

                _PremiumSettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Sign Out',
                  subtitle: 'Securely completely log out',
                  onTap: () => _showLogoutDialog(context),
                  iconColor: AppTheme.errorColor,
                  iconBgColor: AppTheme.errorColor.withOpacity(0.1),
                  isDestructive: true,
                ).animate().slideY(begin: 0.1, delay: 750.ms).fadeIn(),

                const SizedBox(height: 48),

                // ── App Brand Footer ─────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.backgroundLight,
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ATTENDX',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4.0,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version 1.0.0 (Build 42)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 800.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent, // Prevents Material 3 tinting
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
        contentPadding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppTheme.errorColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sign Out',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to securely log out of your account? You will need to authenticate again to access your dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: AppTheme.backgroundLight,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.read<AuthProvider>().signOut();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PremiumSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final Color iconBgColor;
  final bool isDestructive;

  const _PremiumSettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.iconColor,
    required this.iconBgColor,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDestructive
              ? AppTheme.errorColor.withOpacity(0.15)
              : AppTheme.borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: iconColor.withOpacity(0.05),
          highlightColor: iconColor.withOpacity(0.02),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Minimalist Floating Icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                // Typography Focus
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDestructive
                              ? AppTheme.errorColor
                              : AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color:
                      (isDestructive ? AppTheme.errorColor : AppTheme.textMuted)
                          .withOpacity(0.4),
                  size: 14,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
