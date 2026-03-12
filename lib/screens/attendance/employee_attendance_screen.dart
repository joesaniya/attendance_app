// lib/screens/attendance/employee_attendance_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/employee_provider.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/attendance_model.dart';
import '../../data/services/face_detection_service.dart';
import '../../widgets/app_widgets.dart';

// ── Scan states ────────────────────────────────────────────────────────────────
enum ScanState {
  scanning, // camera live, looking for face
  faceDetected, // face in frame, ready to match
  matching, // running match algorithm
  matched, // employee found
  noMatch, // face not recognised
  notRegistered, // employee has no face on file
  result, // show clock-in / clock-out UI
}

class EmployeeAttendanceScreen extends StatefulWidget {
  const EmployeeAttendanceScreen({super.key});

  @override
  State<EmployeeAttendanceScreen> createState() =>
      _EmployeeAttendanceScreenState();
}

class _EmployeeAttendanceScreenState extends State<EmployeeAttendanceScreen>
    with TickerProviderStateMixin {
  // ── Camera ───────────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // ── Face detection ───────────────────────────────────────────────────────────
  final FaceDetectionService _faceService = FaceDetectionService();
  bool _isDetecting = false;
  List<Face> _detectedFaces = [];

  // ── State ────────────────────────────────────────────────────────────────────
  ScanState _scanState = ScanState.scanning;
  EmployeeModel? _matchedEmployee;
  AttendanceModel? _existingAttendance;
  bool _isProcessing = false;
  bool _attendanceMarked = false;

  // ── Animations ────────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _scanController;

  // ── Debounce: only attempt match once per 2 s ────────────────────────────────
  DateTime _lastMatchAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _faceService.initialize();
    _initCamera();
  }

  // ── Camera init ───────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startDetection();
      }
    } catch (e) {
      setState(() => _scanState = ScanState.scanning);
    }
  }

  // ── Continuous face detection stream ─────────────────────────────────────────
  void _startDetection() {
    _cameraController?.startImageStream((CameraImage image) async {
      if (_isDetecting || !mounted) return;
      if (_scanState == ScanState.matching ||
          _scanState == ScanState.matched ||
          _scanState == ScanState.result)
        return;

      _isDetecting = true;
      try {
        final cameras = await availableCameras();
        final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        final faces = await _faceService.detectFacesFromCameraImage(
          image,
          front,
        );

        if (!mounted) return;
        setState(() => _detectedFaces = faces);

        if (faces.isNotEmpty) {
          setState(() => _scanState = ScanState.faceDetected);

          // Auto-match after debounce
          final now = DateTime.now();
          if (now.difference(_lastMatchAttempt).inSeconds >= 2) {
            _lastMatchAttempt = now;
            await _autoMatchFace(faces.first);
          }
        } else {
          if (_scanState == ScanState.faceDetected) {
            setState(() => _scanState = ScanState.scanning);
          }
        }
      } catch (_) {}
      _isDetecting = false;
    });
  }

  // ── Auto match face to employee ───────────────────────────────────────────────
  Future<void> _autoMatchFace(Face face) async {
    if (!_faceService.isFaceGoodQuality(face)) return;

    setState(() => _scanState = ScanState.matching);

    final employees = await context
        .read<EmployeeProvider>()
        .getAllEmployeesForAttendance();

    // Check if ANY employee has a registered face
    final registeredEmployees = employees
        .where((e) => e.faceDescriptor != null && e.faceDescriptor!.isNotEmpty)
        .toList();

    if (registeredEmployees.isEmpty) {
      // No faces registered — fall back to manual selection
      if (mounted) setState(() => _scanState = ScanState.scanning);
      _showManualSelectSheet(employees);
      return;
    }

    final matched = _faceService.matchFaceToEmployee(
      detectedFace: face,
      employees: registeredEmployees,
    );

    if (!mounted) return;

    if (matched != null) {
      setState(() {
        _scanState = ScanState.matched;
        _matchedEmployee = matched;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      await _loadAndShowResult(matched);
    } else {
      setState(() => _scanState = ScanState.noMatch);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _scanState = ScanState.scanning);
    }
  }

  // ── Load existing attendance and show result ──────────────────────────────────
  Future<void> _loadAndShowResult(EmployeeModel employee) async {
    final attendanceProvider = context.read<AttendanceProvider>();
    await attendanceProvider.loadEmployeeAttendance(employee.id);
    if (!mounted) return;
    setState(() {
      _existingAttendance = attendanceProvider.currentEmployeeAttendance;
      _scanState = ScanState.result;
    });
  }

  // ── Mark attendance ───────────────────────────────────────────────────────────
  Future<void> _markAttendance(bool isLogin) async {
    if (_matchedEmployee == null) return;
    setState(() => _isProcessing = true);

    final attendanceProvider = context.read<AttendanceProvider>();
    final success = isLogin
        ? await attendanceProvider.markLogin(_matchedEmployee!)
        : await attendanceProvider.markLogout(_matchedEmployee!.id);

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _attendanceMarked = success;
        if (success) {
          _existingAttendance = attendanceProvider.currentEmployeeAttendance;
        }
      });
    }
  }

  // ── Manual selection fallback (for employees without face registered) ─────────
  Future<void> _showManualSelectSheet(List<EmployeeModel> employees) async {
    await _cameraController?.stopImageStream();

    if (!mounted) return;
    final selected = await showModalBottomSheet<EmployeeModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EmployeeSelectSheet(employees: employees),
    );

    if (selected != null && mounted) {
      setState(() => _matchedEmployee = selected);
      await _loadAndShowResult(selected);
    } else {
      // Restart detection
      _startDetection();
    }
  }

  void _reset() {
    setState(() {
      _scanState = ScanState.scanning;
      _matchedEmployee = null;
      _existingAttendance = null;
      _attendanceMarked = false;
      _isProcessing = false;
    });
    _startDetection();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    _cameraController?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_scanState == ScanState.result && _matchedEmployee != null) {
      return _buildResultScreen();
    }
    return _buildScannerScreen();
  }

  // ── Scanner screen ────────────────────────────────────────────────────────────
  Widget _buildScannerScreen() {
    final hasFace = _detectedFaces.isNotEmpty;
    final isMatching = _scanState == ScanState.matching;
    final isMatched = _scanState == ScanState.matched;
    final noMatch = _scanState == ScanState.noMatch;

    Color frameColor = AppTheme.primaryColor;
    if (isMatched) frameColor = AppTheme.successColor;
    if (noMatch) frameColor = AppTheme.errorColor;
    if (hasFace && !isMatching && !noMatch) frameColor = AppTheme.successColor;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera
          if (_isCameraInitialized && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            Container(
              color: const Color(0xFF0F0F1A),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
            ),

          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.85),
                  ],
                  stops: const [0, 0.25, 0.6, 1],
                ),
              ),
            ),
          ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AttendX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Face Recognition',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Face frame
          Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                width: 240,
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: frameColor.withOpacity(
                      0.4 + 0.4 * _pulseController.value,
                    ),
                    width: 2.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // Corner decorations
                    ...['tl', 'tr', 'bl', 'br'].map(
                      (pos) => Positioned(
                        top: pos.startsWith('t') ? 0 : null,
                        bottom: pos.startsWith('b') ? 0 : null,
                        left: pos.endsWith('l') ? 0 : null,
                        right: pos.endsWith('r') ? 0 : null,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            border: Border(
                              top: pos.startsWith('t')
                                  ? BorderSide(color: frameColor, width: 3)
                                  : BorderSide.none,
                              bottom: pos.startsWith('b')
                                  ? BorderSide(color: frameColor, width: 3)
                                  : BorderSide.none,
                              left: pos.endsWith('l')
                                  ? BorderSide(color: frameColor, width: 3)
                                  : BorderSide.none,
                              right: pos.endsWith('r')
                                  ? BorderSide(color: frameColor, width: 3)
                                  : BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Scan line
                    if (hasFace && !isMatching && !noMatch)
                      AnimatedBuilder(
                        animation: _scanController,
                        builder: (_, __) => Positioned(
                          top: 280 * _scanController.value,
                          left: 8,
                          right: 8,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  frameColor,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Matching spinner
                    if (isMatching)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),

                    // Matched icon
                    if (isMatched)
                      Center(
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.successColor,
                          size: 60,
                        ).animate().scale(duration: 400.ms),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom UI
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status pill
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        key: ValueKey(_scanState),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcon(),
                              color: _statusColor(),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _statusText(),
                              style: TextStyle(
                                color: _statusColor(),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Clock
                    Text(
                      DateFormat('hh:mm a').format(DateTime.now()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Manual fallback button
                    GestureDetector(
                      onTap: _isProcessing
                          ? null
                          : () async {
                              final employees = await context
                                  .read<EmployeeProvider>()
                                  .getAllEmployeesForAttendance();
                              _showManualSelectSheet(employees);
                            },
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.list_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Select Manually',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate().slideY(begin: 0.5, end: 0, duration: 600.ms),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon() {
    switch (_scanState) {
      case ScanState.scanning:
        return Icons.face_retouching_natural;
      case ScanState.faceDetected:
        return Icons.face_rounded;
      case ScanState.matching:
        return Icons.manage_search_rounded;
      case ScanState.matched:
        return Icons.check_circle_rounded;
      case ScanState.noMatch:
        return Icons.help_outline_rounded;
      default:
        return Icons.face_retouching_natural;
    }
  }

  Color _statusColor() {
    switch (_scanState) {
      case ScanState.faceDetected:
      case ScanState.matched:
        return AppTheme.successColor;
      case ScanState.noMatch:
        return AppTheme.errorColor;
      case ScanState.matching:
        return AppTheme.warningColor;
      default:
        return Colors.white;
    }
  }

  String _statusText() {
    switch (_scanState) {
      case ScanState.scanning:
        return 'Position your face in the frame';
      case ScanState.faceDetected:
        return 'Face detected — hold still...';
      case ScanState.matching:
        return 'Identifying...';
      case ScanState.matched:
        return 'Match found!';
      case ScanState.noMatch:
        return 'Face not recognised — try again';
      default:
        return 'Position your face in the frame';
    }
  }

  // ── Result screen ─────────────────────────────────────────────────────────────
  Widget _buildResultScreen() {
    final isLoggedIn = _existingAttendance?.isLoggedIn ?? false;
    final isCompleted = _existingAttendance?.isCompleted ?? false;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Matched badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.successColor.withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: AppTheme.successColor,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Face Verified',
                      style: TextStyle(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: 16),

              // Avatar
              AppAvatar(
                imageUrl: _matchedEmployee?.photoUrl,
                name: _matchedEmployee?.name ?? '',
                size: 88,
              ).animate().scale(
                begin: const Offset(0.5, 0.5),
                duration: 500.ms,
              ),
              const SizedBox(height: 14),
              Text(
                _matchedEmployee?.name ?? '',
                style: AppTextStyles.heading2,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms),
              Text(
                '${_matchedEmployee?.position} · ${_matchedEmployee?.department}',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 24),

              // Time card
              GlassCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.access_time_rounded,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Time',
                              style: AppTextStyles.caption,
                            ),
                            Text(
                              DateFormat('hh:mm a').format(DateTime.now()),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _timeBox(
                            'Login Time',
                            _existingAttendance?.loginTime != null
                                ? DateFormat(
                                    'hh:mm a',
                                  ).format(_existingAttendance!.loginTime!)
                                : '--:--',
                            AppTheme.successColor,
                            Icons.login_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _timeBox(
                            'Logout Time',
                            _existingAttendance?.logoutTime != null
                                ? DateFormat(
                                    'hh:mm a',
                                  ).format(_existingAttendance!.logoutTime!)
                                : '--:--',
                            AppTheme.errorColor,
                            Icons.logout_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 24),

              // Action
              if (_attendanceMarked) ...[
                _successBanner(isLoggedIn),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ] else if (isCompleted) ...[
                _completedBanner(),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Go Back',
                  onTap: () => Navigator.pop(context),
                ),
              ] else
                Consumer<AttendanceProvider>(
                  builder: (context, att, _) => Column(
                    children: [
                      if (!isLoggedIn)
                        GradientButton(
                          label: 'Clock In',
                          icon: Icons.login_rounded,
                          gradient: AppTheme.accentGradient,
                          isLoading: att.isLoading || _isProcessing,
                          onTap: () => _markAttendance(true),
                        )
                      else
                        GradientButton(
                          label: 'Clock Out',
                          icon: Icons.logout_rounded,
                          gradient: const LinearGradient(
                            colors: [AppTheme.errorColor, Color(0xFFFF8C42)],
                          ),
                          isLoading: att.isLoading || _isProcessing,
                          onTap: () => _markAttendance(false),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _reset,
                        child: const Text(
                          '← Scan Again',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _successBanner(bool wasLoggedIn) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.successColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.successColor.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: AppTheme.successColor,
          size: 26,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            wasLoggedIn
                ? 'Logged out successfully!'
                : 'Clocked in successfully!',
            style: const TextStyle(
              color: AppTheme.successColor,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ],
    ),
  ).animate().scale(begin: const Offset(0.8, 0.8), duration: 400.ms);

  Widget _completedBanner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.infoColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.infoColor.withOpacity(0.3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_rounded, color: AppTheme.infoColor, size: 24),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Attendance already completed for today.',
            style: TextStyle(
              color: AppTheme.infoColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _timeBox(String label, String time, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              time,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );
}

// ── Manual Employee Select Sheet ───────────────────────────────────────────────
class _EmployeeSelectSheet extends StatefulWidget {
  final List<EmployeeModel> employees;
  const _EmployeeSelectSheet({required this.employees});

  @override
  State<_EmployeeSelectSheet> createState() => _EmployeeSelectSheetState();
}

class _EmployeeSelectSheetState extends State<_EmployeeSelectSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.employees
        .where(
          (e) =>
              _search.isEmpty ||
              e.name.toLowerCase().contains(_search.toLowerCase()) ||
              (e.employeeCode?.toLowerCase().contains(_search.toLowerCase()) ??
                  false),
        )
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Employee', style: AppTextStyles.heading3),
                  const SizedBox(height: 4),
                  const Text(
                    'Face not matched — choose manually',
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: const InputDecoration(
                      hintText: 'Search by name or code',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      filled: true,
                      fillColor: Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppTheme.borderColor),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final emp = filtered[i];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, emp),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AppAvatar(
                            imageUrl: emp.photoUrl,
                            name: emp.name,
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(emp.name, style: AppTextStyles.bodyBold),
                                Text(
                                  '${emp.position} · ${emp.department}',
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                          // Show face registered badge
                          if (emp.faceDescriptor != null &&
                              emp.faceDescriptor!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.face_rounded,
                                    size: 10,
                                    color: AppTheme.successColor,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Face ID',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.successColor,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (emp.employeeCode != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                emp.employeeCode!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
