// lib/screens/employees/employee_detail_screen.dart

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/attendance_model.dart';
import '../../widgets/app_widgets.dart';
import 'employee_form_screen.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final EmployeeModel employee;

  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  // Full list including today — used for "This Month Attendance"
  List<AttendanceModel> _allMonthHistory = [];
  // Today's record shown separately in the "Today's Activity" section
  AttendanceModel? _todayAttendance;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final provider = context.read<AttendanceProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final history = await provider.getEmployeeAttendanceHistory(
      widget.employee.id,
      startDate: DateTime(now.year, now.month, 1),
      endDate: now,
    );

    // Sort newest first
    history.sort((a, b) => b.date.compareTo(a.date));

    // Find today's record separately (for the dedicated Today's Activity card)
    AttendanceModel? todayRecord;
    for (final record in history) {
      final recDay = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      if (recDay == today) {
        todayRecord = record;
        break;
      }
    }

    setState(() {
      _todayAttendance = todayRecord;
      // Keep ALL records in _allMonthHistory (including today) for the month list
      _allMonthHistory = history;
      _loadingHistory = false;
    });
  }

  Future<void> _deleteEmployee() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Employee'),
        content: Text(
          'Are you sure you want to remove ${widget.employee.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await context.read<EmployeeProvider>().deleteEmployee(
        widget.employee.id,
      );
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee removed successfully'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _fmt(DateTime? dt) =>
      dt != null ? DateFormat('hh:mm a').format(dt) : '--:--';

  String _durationBetween(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '';
    final diff = end.difference(start);
    if (diff.isNegative) return '';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  /// Builds a flat, chronologically-sorted list of timeline events.
  List<_TimelineEvent> _buildTimeline(AttendanceModel r) {
    final map = r.toMap();
    final breaks = (map['breaks'] as List<dynamic>?) ?? [];
    final lunches = (map['lunches'] as List<dynamic>?) ?? [];
    final events = <_TimelineEvent>[];

    if (r.loginTime != null) {
      events.add(
        _TimelineEvent(
          time: r.loginTime!,
          label: 'Checked In',
          icon: Icons.login_rounded,
          color: AppTheme.successColor,
        ),
      );
    }

    for (int i = 0; i < breaks.length; i++) {
      final bIn = _parseTs(breaks[i]['breakIn']);
      final bOut = _parseTs(breaks[i]['breakOut']);
      final label = breaks.length > 1 ? 'Break #${i + 1}' : 'Break';
      if (bIn != null) {
        events.add(
          _TimelineEvent(
            time: bIn,
            label: '$label Start',
            icon: Icons.coffee_rounded,
            color: const Color(0xFFFF9800),
            subtitle: bOut != null
                ? 'Duration: ${_durationBetween(bIn, bOut)}'
                : null,
          ),
        );
      }
      if (bOut != null) {
        events.add(
          _TimelineEvent(
            time: bOut,
            label: '$label End',
            icon: Icons.coffee_outlined,
            color: const Color(0xFFFF9800),
          ),
        );
      }
    }

    for (int i = 0; i < lunches.length; i++) {
      final lIn = _parseTs(lunches[i]['lunchIn']);
      final lOut = _parseTs(lunches[i]['lunchOut']);
      final label = lunches.length > 1 ? 'Lunch #${i + 1}' : 'Lunch';
      if (lIn != null) {
        events.add(
          _TimelineEvent(
            time: lIn,
            label: '$label Start',
            icon: Icons.restaurant_rounded,
            color: const Color(0xFF9C27B0),
            subtitle: lOut != null
                ? 'Duration: ${_durationBetween(lIn, lOut)}'
                : null,
          ),
        );
      }
      if (lOut != null) {
        events.add(
          _TimelineEvent(
            time: lOut,
            label: '$label End',
            icon: Icons.restaurant_menu_rounded,
            color: const Color(0xFF9C27B0),
          ),
        );
      }
    }

    if (r.logoutTime != null) {
      events.add(
        _TimelineEvent(
          time: r.logoutTime!,
          label: 'Checked Out',
          icon: Icons.logout_rounded,
          color: AppTheme.errorColor,
        ),
      );
    } else {
      events.add(
        _TimelineEvent(
          time: DateTime.now(),
          label: 'Still Working',
          icon: Icons.more_horiz_rounded,
          color: AppTheme.textMuted,
          isVirtual: true,
        ),
      );
    }

    // Always sort chronologically — fixes reversed break/lunch times from Firebase
    events.sort((a, b) => a.time.compareTo(b.time));
    return events;
  }

  /// Net work hours: (logout - login) minus all break + lunch durations.
  String _computeWorkHours(AttendanceModel r) {
    if (r.loginTime == null) return '--';
    final end = r.logoutTime ?? DateTime.now();
    var total = end.difference(r.loginTime!);

    final map = r.toMap();
    for (final b in (map['breaks'] as List<dynamic>?) ?? []) {
      final bIn = _parseTs(b['breakIn']);
      final bOut = _parseTs(b['breakOut']);
      if (bIn != null && bOut != null) {
        final d = bOut.difference(bIn);
        if (!d.isNegative) total -= d;
      }
    }
    for (final l in (map['lunches'] as List<dynamic>?) ?? []) {
      final lIn = _parseTs(l['lunchIn']);
      final lOut = _parseTs(l['lunchOut']);
      if (lIn != null && lOut != null) {
        final d = lOut.difference(lIn);
        if (!d.isNegative) total -= d;
      }
    }

    if (total.isNegative) return '0h 0m';
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    final presentDays = _allMonthHistory
        .where((a) => a.status == 'present')
        .length;
    final absentDays = _allMonthHistory
        .where((a) => a.status == 'absent')
        .length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: CustomScrollView(
        slivers: [
          // ── Header ───────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppTheme.backgroundLight,
            leading: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 16,
                  color: AppTheme.textPrimary,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EmployeeFormScreen(employee: widget.employee),
                  ),
                ),
              ),
              IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_rounded,
                    size: 16,
                    color: AppTheme.errorColor,
                  ),
                ),
                onPressed: _deleteEmployee,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F0F1A), Color(0xFF16213E)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Hero(
                          tag: 'avatar_${emp.id}',
                          child: AppAvatar(
                            imageUrl: emp.photoUrl,
                            name: emp.name,
                            size: 70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          emp.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          emp.position.isNotEmpty
                              ? emp.position
                              : 'Farm Worker',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Employee Code + Department
                Row(
                  children: [
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'EMPLOYEE CODE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              emp.employeeCode ?? '--',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DEPARTMENT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              emp.department,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 16),

                // Monthly Stats
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Present Days',
                        value: presentDays.toString(),
                        icon: Icons.check_circle_rounded,
                        color: AppTheme.successColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Absent Days',
                        value: absentDays.toString(),
                        icon: Icons.cancel_rounded,
                        color: AppTheme.errorColor,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
                const SizedBox(height: 20),

                // ── TODAY'S ATTENDANCE ────────────────────────────────
                if (_loadingHistory)
                  const ShimmerCard()
                else if (_todayAttendance != null) ...[
                  _buildTodaySection(_todayAttendance!),
                  const SizedBox(height: 20),
                ],

                // Contact Info
                const SectionHeader(title: 'Contact Information'),
                const SizedBox(height: 12),
                _infoCard(
                  Icons.email_outlined,
                  'Email',
                  emp.email.isEmpty ? 'Not Available' : emp.email,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  Icons.phone_outlined,
                  'Phone',
                  emp.phone.isEmpty ? 'Not Available' : emp.phone,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  Icons.location_on_outlined,
                  'Address',
                  emp.address.isEmpty ? 'Not Available' : emp.address,
                ),
                const SizedBox(height: 20),

                // Created by
                GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Record Created By',
                              style: AppTextStyles.caption,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${emp.createdByName} · ${emp.createdByRole == 'super_admin' ? 'Super Admin' : 'Manager'}',
                              style: AppTextStyles.bodyBold,
                            ),
                            Text(
                              DateFormat('MMM d, yyyy').format(emp.createdAt),
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                const SizedBox(height: 20),

                // ── THIS MONTH ATTENDANCE ─────────────────────────────
                // Always rendered — never skipped even if only today exists
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'This Month Attendance'),
                    ),
                    if (!_loadingHistory && _allMonthHistory.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_allMonthHistory.length} day${_allMonthHistory.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_loadingHistory)
                  ...List.generate(3, (_) => const ShimmerCard())
                else if (_allMonthHistory.isEmpty)
                  const EmptyState(
                    icon: Icons.calendar_today_rounded,
                    title: 'No Records Yet',
                    subtitle: 'No attendance records this month',
                  )
                else
                  ..._allMonthHistory.map(
                    (record) => _buildHistoryCard(record),
                  ),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── TODAY's full detail section ─────────────────────────────────────────
  Widget _buildTodaySection(AttendanceModel r) {
    final workHours = _computeWorkHours(r);
    final timeline = _buildTimeline(r);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader(title: "Today's Activity")),
            StatusBadge(status: r.status),
          ],
        ),
        const SizedBox(height: 12),

        // Summary strip
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            children: [
              _summaryTile(
                icon: Icons.login_rounded,
                iconColor: AppTheme.successColor,
                label: 'Check In',
                value: _fmt(r.loginTime),
              ),
              _verticalDivider(),
              _summaryTile(
                icon: Icons.timer_rounded,
                iconColor: AppTheme.primaryColor,
                label: 'Work Hours',
                value: workHours,
              ),
              _verticalDivider(),
              _summaryTile(
                icon: Icons.logout_rounded,
                iconColor: r.logoutTime != null
                    ? AppTheme.errorColor
                    : AppTheme.textMuted,
                label: 'Check Out',
                value: _fmt(r.logoutTime),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms),

        const SizedBox(height: 12),

        // Timeline
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ACTIVITY TIMELINE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(timeline.length, (i) {
                final e = timeline[i];
                return _timelineEntry(
                  icon: e.icon,
                  color: e.color,
                  title: e.label,
                  time: e.isVirtual ? 'Now' : _fmt(e.time),
                  subtitle: e.subtitle,
                  isFirst: i == 0,
                  isLast: i == timeline.length - 1,
                );
              }),
              if (r.notes != null && r.notes!.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.notes_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.notes!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
      ],
    );
  }

  // ── Monthly history card ──────────────────────────────────────────────────
  Widget _buildHistoryCard(AttendanceModel record) {
    final map = record.toMap();
    final breaks = (map['breaks'] as List<dynamic>?) ?? [];
    final lunches = (map['lunches'] as List<dynamic>?) ?? [];
    final workHrs = _computeWorkHours(record);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recDay = DateTime(
      record.date.year,
      record.date.month,
      record.date.day,
    );
    final isToday = recDay == today;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(0),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.only(
              left: 14,
              right: 14,
              bottom: 14,
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _statusColor(record.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  DateFormat('d').format(record.date),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(record.status),
                  ),
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMM d').format(record.date),
                    style: AppTextStyles.bodyBold,
                  ),
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              record.loginTime != null
                  ? 'In: ${_fmt(record.loginTime)}  ·  Out: ${_fmt(record.logoutTime)}  ·  $workHrs'
                  : record.status.toUpperCase(),
              style: AppTextStyles.caption,
            ),
            trailing: StatusBadge(status: record.status),
            children: [
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  _miniStat(
                    Icons.login_rounded,
                    AppTheme.successColor,
                    'In',
                    _fmt(record.loginTime),
                  ),
                  _miniStat(
                    Icons.logout_rounded,
                    AppTheme.errorColor,
                    'Out',
                    _fmt(record.logoutTime),
                  ),
                  _miniStat(
                    Icons.timer_rounded,
                    AppTheme.primaryColor,
                    'Hours',
                    workHrs,
                  ),
                ],
              ),
              if (breaks.isNotEmpty) ...[
                const SizedBox(height: 10),
                _subSection(
                  icon: Icons.coffee_rounded,
                  color: const Color(0xFFFF9800),
                  title: 'Breaks',
                  items: breaks.map((b) {
                    final bIn = _parseTs(b['breakIn']);
                    final bOut = _parseTs(b['breakOut']);
                    final dur = _durationBetween(bIn, bOut);
                    return '${_fmt(bIn)} → ${_fmt(bOut)}'
                        '${dur.isNotEmpty ? '  ($dur)' : ''}';
                  }).toList(),
                ),
              ],
              if (lunches.isNotEmpty) ...[
                const SizedBox(height: 8),
                _subSection(
                  icon: Icons.restaurant_rounded,
                  color: const Color(0xFF9C27B0),
                  title: 'Lunch',
                  items: lunches.map((l) {
                    final lIn = _parseTs(l['lunchIn']);
                    final lOut = _parseTs(l['lunchOut']);
                    final dur = _durationBetween(lIn, lOut);
                    return '${_fmt(lIn)} → ${_fmt(lOut)}'
                        '${dur.isNotEmpty ? '  ($dur)' : ''}';
                  }).toList(),
                ),
              ],
              if (record.notes != null && record.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.notes_rounded,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.notes!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _summaryTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() =>
      Container(width: 1, height: 50, color: Colors.grey.withOpacity(0.2));

  Widget _timelineEntry({
    required IconData icon,
    required Color color,
    required String title,
    required String time,
    String? subtitle,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                if (!isFirst)
                  Expanded(
                    flex: 1,
                    child: Container(
                      width: 2,
                      color: Colors.grey.withOpacity(0.25),
                    ),
                  )
                else
                  const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                if (!isLast)
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: 2,
                      color: Colors.grey.withOpacity(0.25),
                    ),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, Color color, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subSection({
    required IconData icon,
    required Color color,
    required String title,
    required List<String> items,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return AppTheme.successColor;
      case 'absent':
        return AppTheme.errorColor;
      default:
        return AppTheme.warningColor;
    }
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.bodyBold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data class for timeline events ──────────────────────────────────────────
class _TimelineEvent {
  final DateTime time;
  final String label;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final bool isVirtual;

  const _TimelineEvent({
    required this.time,
    required this.label,
    required this.icon,
    required this.color,
    this.subtitle,
    this.isVirtual = false,
  });
}




/*

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/attendance_model.dart';
import '../../widgets/app_widgets.dart';
import 'employee_form_screen.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final EmployeeModel employee;

  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  List<AttendanceModel> _attendanceHistory = [];
  AttendanceModel? _todayAttendance;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final provider = context.read<AttendanceProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final history = await provider.getEmployeeAttendanceHistory(
      widget.employee.id,
      startDate: DateTime(now.year, now.month, 1),
      endDate: now,
    );

    // Separate today's record from the rest
    AttendanceModel? todayRecord;
    final List<AttendanceModel> pastHistory = [];

    for (final record in history) {
      final recDay = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      if (recDay == today) {
        todayRecord = record;
      } else {
        pastHistory.add(record);
      }
    }

    setState(() {
      _todayAttendance = todayRecord;
      _attendanceHistory = pastHistory;
      _loadingHistory = false;
    });
  }

  Future<void> _deleteEmployee() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Employee'),
        content: Text(
          'Are you sure you want to remove ${widget.employee.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await context.read<EmployeeProvider>().deleteEmployee(
        widget.employee.id,
      );
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee removed successfully'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Formats a nullable DateTime as "hh:mm a", fallback "--:--"
  String _fmt(DateTime? dt) =>
      dt != null ? DateFormat('hh:mm a').format(dt) : '--:--';

  /// Formats a nullable DateTime as ISO string to Duration string
  String _durationBetween(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '';
    final diff = end.difference(start);
    if (diff.isNegative) return '';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// Safely parses ISO-string timestamps stored in break/lunch arrays
  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  /// Computes total work hours correctly:
  /// total = (logout - login) - break time - lunch time
  String _computeWorkHours(AttendanceModel r) {
    if (r.loginTime == null) return '--';

    final end = r.logoutTime ?? DateTime.now();
    var total = end.difference(r.loginTime!);

    // Subtract breaks
    final breaks = (r.toMap()['breaks'] as List<dynamic>?) ?? [];
    for (final b in breaks) {
      final bIn = _parseTs(b['breakIn']);
      final bOut = _parseTs(b['breakOut']);
      if (bIn != null && bOut != null) {
        final diff = bOut.difference(bIn);
        if (!diff.isNegative) total -= diff;
      }
    }

    // Subtract lunches
    final lunches = (r.toMap()['lunches'] as List<dynamic>?) ?? [];
    for (final l in lunches) {
      final lIn = _parseTs(l['lunchIn']);
      final lOut = _parseTs(l['lunchOut']);
      if (lIn != null && lOut != null) {
        final diff = lOut.difference(lIn);
        if (!diff.isNegative) total -= diff;
      }
    }

    if (total.isNegative) return '0h 0m';
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    final allRecords = [
      if (_todayAttendance != null) _todayAttendance!,
      ..._attendanceHistory,
    ];
    final presentDays = allRecords.where((a) => a.status == 'present').length;
    final absentDays = allRecords.where((a) => a.status == 'absent').length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppTheme.backgroundLight,
            leading: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 16,
                  color: AppTheme.textPrimary,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EmployeeFormScreen(employee: widget.employee),
                  ),
                ),
              ),
              IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_rounded,
                    size: 16,
                    color: AppTheme.errorColor,
                  ),
                ),
                onPressed: _deleteEmployee,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F0F1A), Color(0xFF16213E)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Hero(
                          tag: 'avatar_${emp.id}',
                          child: AppAvatar(
                            imageUrl: emp.photoUrl,
                            name: emp.name,
                            size: 70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          emp.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          emp.position.isNotEmpty
                              ? emp.position
                              : 'Farm Worker',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Employee Code + Department
                Row(
                  children: [
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'EMPLOYEE CODE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              emp.employeeCode ?? '--',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DEPARTMENT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              emp.department,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 16),

                // Monthly Stats
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Present Days',
                        value: presentDays.toString(),
                        icon: Icons.check_circle_rounded,
                        color: AppTheme.successColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Absent Days',
                        value: absentDays.toString(),
                        icon: Icons.cancel_rounded,
                        color: AppTheme.errorColor,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
                const SizedBox(height: 20),

                // ── TODAY'S ATTENDANCE DETAIL ────────────────────────────────
                if (_loadingHistory)
                  const ShimmerCard()
                else if (_todayAttendance != null) ...[
                  _buildTodaySection(_todayAttendance!),
                  const SizedBox(height: 20),
                ],

                // Contact Info
                const SectionHeader(title: 'Contact Information'),
                const SizedBox(height: 12),
                _infoCard(
                  Icons.email_outlined,
                  'Email',
                  emp.email.isEmpty ? 'Not Available' : emp.email,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  Icons.phone_outlined,
                  'Phone',
                  emp.phone.isEmpty ? 'Not Available' : emp.phone,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  Icons.location_on_outlined,
                  'Address',
                  emp.address.isEmpty ? 'Not Available' : emp.address,
                ),
                const SizedBox(height: 20),

                // Created by
                GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Record Created By',
                              style: AppTextStyles.caption,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${emp.createdByName} · ${emp.createdByRole == 'super_admin' ? 'Super Admin' : 'Manager'}',
                              style: AppTextStyles.bodyBold,
                            ),
                            Text(
                              DateFormat('MMM d, yyyy').format(emp.createdAt),
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                const SizedBox(height: 20),

                // ── MONTHLY ATTENDANCE HISTORY ───────────────────────────────
                const SectionHeader(title: 'This Month Attendance'),
                const SizedBox(height: 12),

                if (_loadingHistory)
                  ...List.generate(4, (_) => const ShimmerCard())
                else if (_attendanceHistory.isEmpty && _todayAttendance == null)
                  const EmptyState(
                    icon: Icons.calendar_today_rounded,
                    title: 'No History',
                    subtitle: 'No attendance records this month',
                  )
                else
                  ..._attendanceHistory.map(
                    (record) => _buildHistoryCard(record),
                  ),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── TODAY's full detail section ─────────────────────────────────────────────
  Widget _buildTodaySection(AttendanceModel r) {
    final map = r.toMap();
    final breaks = (map['breaks'] as List<dynamic>?) ?? [];
    final lunches = (map['lunches'] as List<dynamic>?) ?? [];
    final workHours = _computeWorkHours(r);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: "Today's Activity" + status badge
        Row(
          children: [
            const Expanded(child: SectionHeader(title: "Today's Activity")),
            StatusBadge(status: r.status),
          ],
        ),
        const SizedBox(height: 12),

        // Summary strip: Check-in | Work Hours | Check-out
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            children: [
              _summaryTile(
                icon: Icons.login_rounded,
                iconColor: AppTheme.successColor,
                label: 'Check In',
                value: _fmt(r.loginTime),
              ),
              _verticalDivider(),
              _summaryTile(
                icon: Icons.timer_rounded,
                iconColor: AppTheme.primaryColor,
                label: 'Work Hours',
                value: workHours,
              ),
              _verticalDivider(),
              _summaryTile(
                icon: Icons.logout_rounded,
                iconColor: r.logoutTime != null
                    ? AppTheme.errorColor
                    : AppTheme.textMuted,
                label: 'Check Out',
                value: _fmt(r.logoutTime),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms),

        const SizedBox(height: 12),

        // Timeline
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ACTIVITY TIMELINE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 16),

              // Check In
              _timelineEntry(
                icon: Icons.login_rounded,
                color: AppTheme.successColor,
                title: 'Checked In',
                time: _fmt(r.loginTime),
                isFirst: true,
              ),

              // Breaks
              for (int i = 0; i < breaks.length; i++) ...[
                _timelineEntry(
                  icon: Icons.coffee_rounded,
                  color: const Color(0xFFFF9800),
                  title: 'Break ${breaks.length > 1 ? '#${i + 1} ' : ''}Start',
                  time: _fmt(_parseTs(breaks[i]['breakIn'])),
                  subtitle:
                      _durationBetween(
                        _parseTs(breaks[i]['breakIn']),
                        _parseTs(breaks[i]['breakOut']),
                      ).isNotEmpty
                      ? 'Duration: ${_durationBetween(_parseTs(breaks[i]['breakIn']), _parseTs(breaks[i]['breakOut']))}'
                      : null,
                ),
                if (_parseTs(breaks[i]['breakOut']) != null)
                  _timelineEntry(
                    icon: Icons.coffee_outlined,
                    color: const Color(0xFFFF9800),
                    title: 'Break ${breaks.length > 1 ? '#${i + 1} ' : ''}End',
                    time: _fmt(_parseTs(breaks[i]['breakOut'])),
                  ),
              ],

              // Lunches
              for (int i = 0; i < lunches.length; i++) ...[
                _timelineEntry(
                  icon: Icons.restaurant_rounded,
                  color: const Color(0xFF9C27B0),
                  title: 'Lunch ${lunches.length > 1 ? '#${i + 1} ' : ''}Start',
                  time: _fmt(_parseTs(lunches[i]['lunchIn'])),
                  subtitle:
                      _durationBetween(
                        _parseTs(lunches[i]['lunchIn']),
                        _parseTs(lunches[i]['lunchOut']),
                      ).isNotEmpty
                      ? 'Duration: ${_durationBetween(_parseTs(lunches[i]['lunchIn']), _parseTs(lunches[i]['lunchOut']))}'
                      : null,
                ),
                if (_parseTs(lunches[i]['lunchOut']) != null)
                  _timelineEntry(
                    icon: Icons.restaurant_menu_rounded,
                    color: const Color(0xFF9C27B0),
                    title: 'Lunch ${lunches.length > 1 ? '#${i + 1} ' : ''}End',
                    time: _fmt(_parseTs(lunches[i]['lunchOut'])),
                  ),
              ],

              // Check Out
              _timelineEntry(
                icon: r.logoutTime != null
                    ? Icons.logout_rounded
                    : Icons.more_horiz_rounded,
                color: r.logoutTime != null
                    ? AppTheme.errorColor
                    : AppTheme.textMuted,
                title: r.logoutTime != null ? 'Checked Out' : 'Still Working',
                time: _fmt(r.logoutTime),
                isLast: true,
              ),

              // Notes if present
              if (r.notes != null && r.notes!.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.notes_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.notes!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
      ],
    );
  }

  // ── Monthly history card ────────────────────────────────────────────────────
  Widget _buildHistoryCard(AttendanceModel record) {
    final map = record.toMap();
    final breaks = (map['breaks'] as List<dynamic>?) ?? [];
    final lunches = (map['lunches'] as List<dynamic>?) ?? [];
    final workHrs = _computeWorkHours(record);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(0),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.only(
              left: 14,
              right: 14,
              bottom: 14,
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _statusColor(record.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  DateFormat('d').format(record.date),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(record.status),
                  ),
                ),
              ),
            ),
            title: Text(
              DateFormat('EEEE, MMM d').format(record.date),
              style: AppTextStyles.bodyBold,
            ),
            subtitle: Text(
              record.loginTime != null
                  ? 'In: ${_fmt(record.loginTime)}  ·  Out: ${_fmt(record.logoutTime)}  ·  $workHrs'
                  : record.status.toUpperCase(),
              style: AppTextStyles.caption,
            ),
            trailing: StatusBadge(status: record.status),
            children: [
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Mini summary row
              Row(
                children: [
                  _miniStat(
                    Icons.login_rounded,
                    AppTheme.successColor,
                    'In',
                    _fmt(record.loginTime),
                  ),
                  _miniStat(
                    Icons.logout_rounded,
                    AppTheme.errorColor,
                    'Out',
                    _fmt(record.logoutTime),
                  ),
                  _miniStat(
                    Icons.timer_rounded,
                    AppTheme.primaryColor,
                    'Hours',
                    workHrs,
                  ),
                ],
              ),

              // Breaks
              if (breaks.isNotEmpty) ...[
                const SizedBox(height: 10),
                _subSection(
                  icon: Icons.coffee_rounded,
                  color: const Color(0xFFFF9800),
                  title: 'Breaks',
                  items: breaks.map((b) {
                    final bIn = _parseTs(b['breakIn']);
                    final bOut = _parseTs(b['breakOut']);
                    final dur = _durationBetween(bIn, bOut);
                    return '${_fmt(bIn)} → ${_fmt(bOut)}'
                        '${dur.isNotEmpty ? '  ($dur)' : ''}';
                  }).toList(),
                ),
              ],

              // Lunches
              if (lunches.isNotEmpty) ...[
                const SizedBox(height: 8),
                _subSection(
                  icon: Icons.restaurant_rounded,
                  color: const Color(0xFF9C27B0),
                  title: 'Lunch',
                  items: lunches.map((l) {
                    final lIn = _parseTs(l['lunchIn']);
                    final lOut = _parseTs(l['lunchOut']);
                    final dur = _durationBetween(lIn, lOut);
                    return '${_fmt(lIn)} → ${_fmt(lOut)}'
                        '${dur.isNotEmpty ? '  ($dur)' : ''}';
                  }).toList(),
                ),
              ],

              // Notes
              if (record.notes != null && record.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.notes_rounded,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.notes!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared small widgets ────────────────────────────────────────────────────

  Widget _summaryTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() =>
      Container(width: 1, height: 50, color: Colors.grey.withOpacity(0.2));

  Widget _timelineEntry({
    required IconData icon,
    required Color color,
    required String title,
    required String time,
    String? subtitle,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line + dot column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Top line
                if (!isFirst)
                  Expanded(
                    flex: 1,
                    child: Container(
                      width: 2,
                      color: Colors.grey.withOpacity(0.25),
                    ),
                  )
                else
                  const SizedBox(height: 4),
                // Dot
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                // Bottom line
                if (!isLast)
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: 2,
                      color: Colors.grey.withOpacity(0.25),
                    ),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, Color color, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subSection({
    required IconData icon,
    required Color color,
    required String title,
    required List<String> items,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Reused from original ────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return AppTheme.successColor;
      case 'absent':
        return AppTheme.errorColor;
      default:
        return AppTheme.warningColor;
    }
  }

  Widget _infoCard(IconData icon, String label, String value) {
    log('Building info card for $label: $value');
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.bodyBold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
*/