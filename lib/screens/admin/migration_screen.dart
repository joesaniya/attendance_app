// lib/screens/admin/migration_screen.dart
//
// One-time admin screen shown when legacy face descriptors are detected.
// Runs FaceDescriptorMigrationService.runMigration() with live progress.
// After success the attendance kiosk uses pixel-level matching and the
// Esther ↔ OM cross-match is resolved permanently.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/face_descriptor_migration_service.dart';

enum _MigState { idle, running, done, error }

class MigrationScreen extends StatefulWidget {
  /// Called after migration completes so the host can navigate away.
  final VoidCallback onComplete;
  const MigrationScreen({super.key, required this.onComplete});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  final _service = FaceDescriptorMigrationService();

  _MigState _state = _MigState.idle;
  int _processed = 0;
  int _total = 0;
  MigrationSummary? _summary;
  EmployeeMigrationResult? _latest;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), _start);
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() => _state = _MigState.running);
    try {
      final summary = await _service.runMigration(
        onProgress: (processed, total, latest) {
          if (!mounted) return;
          setState(() {
            _processed = processed;
            _total = total;
            _latest = latest;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _state = _MigState.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _MigState.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (_state) {
          _MigState.idle => _preparing(),
          _MigState.running => _running(),
          _MigState.done => _done(),
          _MigState.error => _error(),
        },
      ),
    ),
  );

  // ── Preparing ─────────────────────────────────────────────────────────────
  Widget _preparing() => _center(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppTheme.primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Preparing face data update…',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    ),
  );

  // ── Running ───────────────────────────────────────────────────────────────
  Widget _running() {
    final progress = _total > 0 ? _processed / _total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        // Header card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.face_retouching_natural,
                color: Colors.white,
                size: 48,
              ),
              SizedBox(height: 12),
              Text(
                'Updating Face Recognition',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Building accurate face descriptors for all employees.\n'
                'This runs once and takes about 1–2 minutes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 350.ms),

        const SizedBox(height: 28),

        // Progress bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Processing employees…',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
            ),
            Text(
              '$_processed / $_total',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
            valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
          ),
        ),

        const SizedBox(height: 20),

        if (_latest != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _resultTile(_latest!, key: ValueKey(_latest!.employee.id)),
          ),

        const Spacer(),

        // Warning
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.warningColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppTheme.warningColor,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Please do not close the app while the update is running.',
                  style: TextStyle(
                    color: AppTheme.warningColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Done ──────────────────────────────────────────────────────────────────
  Widget _done() {
    final s = _summary!;
    final allOk = s.needsManualReg == 0;
    final color = allOk ? AppTheme.successColor : AppTheme.warningColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(
                allOk ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: color,
                size: 56,
              ).animate().scale(duration: 400.ms),
              const SizedBox(height: 12),
              Text(
                allOk
                    ? 'Face data updated successfully!'
                    : 'Update complete — some employees need attention',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 20),

        // Stats row
        Row(
          children: [
            Expanded(
              child: _statBox(
                'Updated',
                s.succeeded,
                AppTheme.successColor,
                Icons.check_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statBox(
                'Already OK',
                s.skippedAlreadyNew,
                AppTheme.primaryColor,
                Icons.verified_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statBox(
                'Need Attention',
                s.needsManualReg,
                AppTheme.errorColor,
                Icons.person_rounded,
              ),
            ),
          ],
        ),

        if (s.needsManualReg > 0) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.errorColor.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.person_off_rounded,
                      color: AppTheme.errorColor,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Require manual face re-registration:',
                      style: TextStyle(
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...s.results
                    .where(
                      (r) =>
                          r.status == MigrationStatus.failed ||
                          r.status == MigrationStatus.skippedNoPhoto,
                    )
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 6,
                              color: AppTheme.errorColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${r.employee.name} — ${r.errorMessage ?? 'Unknown error'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],

        const Spacer(),

        ElevatedButton.icon(
          onPressed: widget.onComplete,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continue to Attendance'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        if (s.needsManualReg > 0) ...[
          const SizedBox(height: 8),
          const Text(
            'Employees listed above will not be able to use face attendance '
            'until an admin re-registers their face.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _error() => _center(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: AppTheme.errorColor,
          size: 64,
        ),
        const SizedBox(height: 16),
        const Text(
          'Migration failed',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Please check your internet connection and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _state = _MigState.idle;
              _processed = 0;
              _total = 0;
            });
            Future.delayed(const Duration(milliseconds: 400), _start);
          },
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _center(Widget child) =>
      Center(child: SingleChildScrollView(child: child));

  Widget _resultTile(EmployeeMigrationResult r, {Key? key}) {
    final (icon, color) = switch (r.status) {
      MigrationStatus.success => (
        Icons.check_circle_rounded,
        AppTheme.successColor,
      ),
      MigrationStatus.skippedAlreadyNew => (
        Icons.verified_rounded,
        AppTheme.primaryColor,
      ),
      MigrationStatus.skippedNoPhoto => (
        Icons.no_photography_rounded,
        AppTheme.warningColor,
      ),
      MigrationStatus.failed => (Icons.error_rounded, AppTheme.errorColor),
    };
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.employee.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (r.errorMessage != null)
                  Text(
                    r.errorMessage!,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, int value, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      );
}
