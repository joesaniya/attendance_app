// lib/screens/attendance/employee_attendance_screen.dart
//
// STRICT FACE-ONLY ATTENDANCE — using FaceDetectionService typed API
// ─────────────────────────────────────────────────────────────────────────────
// Flow:
//   STEP 1 — IDENTIFY  (1-to-N)
//     Camera scans → identifyEmployee() across all registered employees.
//     On success: employee is locked-in for this session (_sessionEmployee).
//     On failure: explicit rejection message from FaceMatchResult.message.
//
//   STEP 2 — VERIFY  (1-to-1)
//     Every subsequent action (Check-Out, Break-Out/In, Lunch-Out/In)
//     calls verifyEmployee(expectedEmployee: _sessionEmployee).
//     A different person's face will fail here and see
//     "Unauthorized person detected. Only [Name] can perform this action."
//
//   Manual fallback: REMOVED — face is the only authentication method.

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

// ── Enums ─────────────────────────────────────────────────────────────────────
enum _Screen { scanner, result }

enum _ScanPhase {
  idle, // camera running, no face
  faceDetected, // face in frame, waiting for cooldown
  matching, // running FaceDetectionService
  accepted, // match passed — brief success frame
  rejected, // match failed — show reason
}

/// Which attendance action triggered the scanner.
enum _ActionType {
  identify, // Step 1: who is this person?
  checkOut,
  breakOut,
  breakIn,
  lunchOut,
  lunchIn,
}

class EmployeeAttendanceScreen extends StatefulWidget {
  const EmployeeAttendanceScreen({super.key});

  @override
  State<EmployeeAttendanceScreen> createState() =>
      _EmployeeAttendanceScreenState();
}

class _EmployeeAttendanceScreenState extends State<EmployeeAttendanceScreen>
    with TickerProviderStateMixin {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraReady = false;
  bool _streaming = false;
  bool _detecting = false;

  // ── Face service ──────────────────────────────────────────────────────────
  final FaceDetectionService _faceService = FaceDetectionService();
  List<Face> _frames = [];

  // ── Session state ─────────────────────────────────────────────────────────
  _Screen _screen = _Screen.scanner;
  _ScanPhase _phase = _ScanPhase.idle;
  _ActionType _actionType = _ActionType.identify;

  /// The employee locked in after successful identification.
  EmployeeModel? _sessionEmployee;

  /// Latest attendance record for _sessionEmployee.
  AttendanceModel? _attendance;

  bool _processing = false;
  bool _disposed = false;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last rejection message from FaceDetectionService.
  String _rejectionMessage = '';

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _faceService.initialize();
    _initCamera();
  }

  @override
  void dispose() {
    _disposed = true;
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _stopStream();
    _camera?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || _disposed) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _camera = ctrl;
      await ctrl.initialize();
      if (_disposed || !mounted) {
        await ctrl.dispose();
        return;
      }
      if (mounted) setState(() => _cameraReady = true);
      _startStream();
    } catch (e) {
      debugPrint('[Camera] $e');
    }
  }

  void _startStream() {
    final ctrl = _camera;
    if (ctrl == null || !ctrl.value.isInitialized || _streaming) return;
    _streaming = true;
    _detecting = false;

    ctrl.startImageStream((CameraImage img) async {
      if (_disposed || !mounted || _detecting) return;
      if (_phase == _ScanPhase.matching ||
          _phase == _ScanPhase.accepted ||
          _screen == _Screen.result)
        return;

      _detecting = true;
      try {
        final cameras = await availableCameras();
        if (_disposed) return;
        final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        final faces = await _faceService.detectFacesFromCameraImage(img, front);
        if (_disposed || !mounted) return;
        if (mounted) setState(() => _frames = faces);

        if (faces.isEmpty) {
          if (_phase == _ScanPhase.faceDetected && mounted) {
            setState(() => _phase = _ScanPhase.idle);
          }
        } else {
          if (_phase == _ScanPhase.idle && mounted) {
            setState(() => _phase = _ScanPhase.faceDetected);
          }
          final now = DateTime.now();
          // Cooldown: 2 s between match attempts (3 s after a rejection)
          final cooldown = _phase == _ScanPhase.rejected ? 3 : 2;
          if (now.difference(_lastAttempt).inSeconds >= cooldown) {
            _lastAttempt = now;
            await _runMatch(faces.first);
          }
        }
      } catch (e) {
        debugPrint('[Stream] $e');
      } finally {
        _detecting = false;
      }
    });
  }

  Future<void> _stopStream() async {
    _streaming = false;
    final ctrl = _camera;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isStreamingImages) {
      try {
        await ctrl.stopImageStream();
      } catch (_) {}
    }
  }

  // ── Core matching logic ───────────────────────────────────────────────────
  Future<void> _runMatch(Face face) async {
    if (_disposed || !mounted) return;
    if (mounted) setState(() => _phase = _ScanPhase.matching);

    FaceMatchResult result;

    if (_actionType == _ActionType.identify) {
      // ── STEP 1: identify who this is ──────────────────────────────────
      final employees = await context
          .read<EmployeeProvider>()
          .getAllEmployeesForAttendance();
      if (_disposed || !mounted) return;

      final registered = employees
          .where(
            (e) => e.faceDescriptor != null && e.faceDescriptor!.isNotEmpty,
          )
          .toList();

      if (registered.isEmpty) {
        _onRejected(
          'No registered employees found. Please register faces first.',
        );
        return;
      }

      result = _faceService.identifyEmployee(
        detectedFace: face,
        employees: registered,
      );
    } else {
      // ── STEP 2: verify it's still the same person ─────────────────────
      if (_sessionEmployee == null) {
        _onRejected('Session expired. Please scan again from the beginning.');
        return;
      }
      result = _faceService.verifyEmployee(
        detectedFace: face,
        expectedEmployee: _sessionEmployee!,
        useSamples: true,
      ); // multi-sample averaging for extra strictness

      // Not enough samples yet — keep collecting silently
      if (result.status == FaceMatchStatus.insufficientData &&
          result.message.contains('hold still')) {
        if (mounted) setState(() => _phase = _ScanPhase.faceDetected);
        return;
      }
    }

    if (_disposed || !mounted) return;

    if (result.isMatched) {
      await _onMatched(result.employee ?? _sessionEmployee!);
    } else {
      _onRejected(result.message);
    }
  }

  Future<void> _onMatched(EmployeeModel employee) async {
    await _stopStream();
    if (_disposed || !mounted) return;

    setState(() {
      _phase = _ScanPhase.accepted;
      _sessionEmployee = employee;
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (_disposed || !mounted) return;

    if (_actionType == _ActionType.identify) {
      // Load today's attendance and show result screen
      final attProv = context.read<AttendanceProvider>();
      await attProv.loadEmployeeAttendance(employee.id);
      if (_disposed || !mounted) return;
      final att = attProv.currentEmployeeAttendance;

      // Auto check-in if not yet clocked in
      if (att == null || (!att.isLoggedIn && !att.isCompleted)) {
        await _executeAction(_ActionType.identify, employee);
      } else {
        setState(() {
          _attendance = att;
          _screen = _Screen.result;
        });
      }
    } else {
      await _executeAction(_actionType, employee);
    }
  }

  void _onRejected(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _ScanPhase.rejected;
      _rejectionMessage = message;
    });
    // Auto-reset rejection after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_disposed && _phase == _ScanPhase.rejected) {
        setState(() => _phase = _ScanPhase.idle);
        _faceService.resetSamples();
      }
    });
  }

  // ── Execute attendance action ──────────────────────────────────────────────
  Future<void> _executeAction(_ActionType action, EmployeeModel emp) async {
    if (_disposed || !mounted) return;
    setState(() => _processing = true);

    final photo = await _capturePhoto();
    if (_disposed || !mounted) return;

    final attProv = context.read<AttendanceProvider>();
    bool success = false;
    String? errorMsg;

    try {
      switch (action) {
        case _ActionType.identify: // auto check-in
          success = await attProv.markLogin(emp, localPhotoPath: photo?.path);
          break;
        case _ActionType.checkOut:
          success = await attProv.markLogout(
            emp.id,
            localPhotoPath: photo?.path,
          );
          break;
        case _ActionType.breakOut:
          success = await attProv.startBreak(emp.id);
          break;
        case _ActionType.breakIn:
          success = await attProv.endBreak(emp.id);
          break;
        case _ActionType.lunchOut:
          success = await attProv.startLunch(emp.id);
          break;
        case _ActionType.lunchIn:
          success = await attProv.endLunch(emp.id);
          break;
      }
      errorMsg = attProv.error;
    } catch (e) {
      errorMsg = e.toString();
    }

    if (_disposed || !mounted) return;

    if (success) {
      _toast(_actionSuccessMsg(action), AppTheme.successColor);
    } else {
      _toast(
        errorMsg ?? 'Something went wrong. Please try again.',
        AppTheme.errorColor,
      );
    }

    setState(() {
      _processing = false;
      _attendance = attProv.currentEmployeeAttendance;
      _screen = _Screen.result;
      _actionType = _ActionType.identify; // reset for next cycle
    });
  }

  // ── Trigger face scan for a specific action ───────────────────────────────
  void _requestScan(_ActionType action) {
    if (_disposed) return;
    _faceService.resetSamples();
    setState(() {
      _actionType = action;
      _phase = _ScanPhase.idle;
      _frames = [];
      _screen = _Screen.scanner;
      _rejectionMessage = '';
    });
    _startStream();
  }

  void _resetSession() {
    if (_disposed) return;
    _faceService.resetSamples();
    setState(() {
      _screen = _Screen.scanner;
      _phase = _ScanPhase.idle;
      _actionType = _ActionType.identify;
      _sessionEmployee = null;
      _attendance = null;
      _processing = false;
      _frames = [];
      _rejectionMessage = '';
    });
    _startStream();
  }

  // ── Photo capture ─────────────────────────────────────────────────────────
  Future<XFile?> _capturePhoto() async {
    final ctrl = _camera;
    if (ctrl == null || !ctrl.value.isInitialized) return null;
    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
        _streaming = false;
        await Future.delayed(const Duration(milliseconds: 350));
      }
      return await ctrl.takePicture();
    } catch (e) {
      debugPrint('[Photo] $e');
      return null;
    }
  }

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _actionSuccessMsg(_ActionType action) {
    switch (action) {
      case _ActionType.identify:
        return '✓ Checked in successfully!';
      case _ActionType.checkOut:
        return '✓ Checked out. Have a great day!';
      case _ActionType.breakOut:
        return '✓ Break started.';
      case _ActionType.breakIn:
        return '✓ Break ended. Welcome back!';
      case _ActionType.lunchOut:
        return '✓ Lunch started.';
      case _ActionType.lunchIn:
        return '✓ Lunch ended. Welcome back!';
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return _screen == _Screen.result && _sessionEmployee != null
        ? _buildResultScreen()
        : _buildScannerScreen();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SCANNER SCREEN
  // ═════════════════════════════════════════════════════════════════════════
  Widget _buildScannerScreen() {
    final hasFace = _frames.isNotEmpty;
    final isRejected = _phase == _ScanPhase.rejected;
    final isAccepted = _phase == _ScanPhase.accepted;
    final isMatching = _phase == _ScanPhase.matching;

    Color frameColor = AppTheme.primaryColor;
    if (isAccepted) frameColor = AppTheme.successColor;
    if (isRejected) frameColor = AppTheme.errorColor;
    if (hasFace && !isMatching && !isRejected) {
      frameColor = AppTheme.successColor;
    }

    final isVerifying = _actionType != _ActionType.identify;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera
          if (_cameraReady && _camera != null)
            CameraPreview(_camera!)
          else
            const ColoredBox(
              color: Color(0xFF0A0A14),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
            ),

          // Dark gradient
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.65),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.90),
                ],
                stops: const [0, 0.25, 0.55, 1],
              ),
            ),
          ),

          // ── Top bar ────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _glassBtn(
                    icon: Icons.arrow_back_ios_rounded,
                    onTap: () {
                      if (isVerifying) {
                        setState(() {
                          _actionType = _ActionType.identify;
                          _screen = _Screen.result;
                        });
                        _stopStream();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'AttendX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        isVerifying ? _verifyingLabel() : 'Face Recognition',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Action verification banner ──────────────────────────────────
          if (isVerifying)
            Positioned(top: 100, left: 20, right: 20, child: _verifyBanner()),

          // ── Face frame ──────────────────────────────────────────────────
          Center(
            child: _buildFaceFrame(
              frameColor,
              hasFace,
              isMatching,
              isAccepted,
              isRejected,
            ),
          ),

          // ── Bottom HUD ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusPill(),
                    const SizedBox(height: 14),
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
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _faceOnlyBadge(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceFrame(
    Color frameColor,
    bool hasFace,
    bool isMatching,
    bool isAccepted,
    bool isRejected,
  ) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        width: 240,
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: frameColor.withOpacity(0.35 + 0.45 * _pulseCtrl.value),
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Corner brackets
              for (final pos in ['tl', 'tr', 'bl', 'br'])
                Positioned(
                  top: pos.startsWith('t') ? 0 : null,
                  bottom: pos.startsWith('b') ? 0 : null,
                  left: pos.endsWith('l') ? 0 : null,
                  right: pos.endsWith('r') ? 0 : null,
                  child: Container(
                    width: 26,
                    height: 26,
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

              // Scan line
              if (hasFace && !isMatching && !isRejected)
                AnimatedBuilder(
                  animation: _scanCtrl,
                  builder: (_, __) => Positioned(
                    top: 295 * _scanCtrl.value,
                    left: 10,
                    right: 10,
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

              // State icons
              if (isMatching)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),

              if (isAccepted)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.successColor,
                        size: 68,
                      ).animate().scale(duration: 400.ms),
                      const SizedBox(height: 8),
                      const Text(
                        'Identity Confirmed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

              if (isRejected)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.gpp_bad_rounded,
                        color: AppTheme.errorColor,
                        size: 60,
                      ).animate().scale(duration: 350.ms),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _rejectionMessage.length > 60
                              ? _rejectionMessage.substring(0, 57) + '...'
                              : _rejectionMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _statusPill() {
    final (icon, color, text) = _phaseInfo();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey('$_phase-$_rejectionMessage'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _phaseInfo() {
    switch (_phase) {
      case _ScanPhase.idle:
        return (
          Icons.face_retouching_natural,
          Colors.white,
          'Position your face in the frame',
        );
      case _ScanPhase.faceDetected:
        return (
          Icons.face_rounded,
          AppTheme.successColor,
          'Face detected — hold still...',
        );
      case _ScanPhase.matching:
        return (
          Icons.manage_search_rounded,
          AppTheme.warningColor,
          'Verifying identity...',
        );
      case _ScanPhase.accepted:
        return (
          Icons.verified_rounded,
          AppTheme.successColor,
          'Identity confirmed ✓',
        );
      case _ScanPhase.rejected:
        final short = _rejectionMessage.split('.').first;
        return (Icons.block_rounded, AppTheme.errorColor, short);
    }
  }

  String _verifyingLabel() {
    switch (_actionType) {
      case _ActionType.checkOut:
        return 'Verify to Check Out';
      case _ActionType.breakOut:
        return 'Verify to Start Break';
      case _ActionType.breakIn:
        return 'Verify to End Break';
      case _ActionType.lunchOut:
        return 'Verify to Start Lunch';
      case _ActionType.lunchIn:
        return 'Verify to End Lunch';
      default:
        return 'Face Recognition';
    }
  }

  Widget _verifyBanner() {
    final Color color;
    final IconData icon;
    final String name = _sessionEmployee?.name ?? 'the registered employee';

    switch (_actionType) {
      case _ActionType.checkOut:
        color = AppTheme.errorColor;
        icon = Icons.logout_rounded;
        break;
      case _ActionType.breakOut:
      case _ActionType.breakIn:
        color = AppTheme.warningColor;
        icon = Icons.coffee_rounded;
        break;
      case _ActionType.lunchOut:
      case _ActionType.lunchIn:
        color = AppTheme.infoColor;
        icon = Icons.restaurant_rounded;
        break;
      default:
        color = AppTheme.primaryColor;
        icon = Icons.security_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _verifyingLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Only $name\'s face is accepted',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: -0.3, end: 0, duration: 300.ms);
  }

  Widget _faceOnlyBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.15)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.security_rounded, color: Colors.white54, size: 13),
        SizedBox(width: 6),
        Text(
          'Only registered faces are accepted',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _glassBtn({required IconData icon, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      );

  // ═════════════════════════════════════════════════════════════════════════
  // RESULT SCREEN
  // ═════════════════════════════════════════════════════════════════════════
  Widget _buildResultScreen() {
    final att = _attendance;
    final isLoggedIn = att?.isLoggedIn ?? false;
    final isCompleted = att?.isCompleted ?? false;
    final isOnBreak = att?.isOnBreak ?? false;
    final isOnLunch = att?.isOnLunch ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ────────────────────────────────────────────────
              Row(
                children: [
                  _backBtn(),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Attendance Record',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  _verifiedBadge(),
                ],
              ),
              const SizedBox(height: 16),

              // ── Employee card ─────────────────────────────────────────
              _employeeCard().animate().fadeIn(duration: 350.ms),
              const SizedBox(height: 12),

              // ── Active status chips ───────────────────────────────────
              if (isOnBreak || isOnLunch) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (isOnBreak) _chip('● On Break', AppTheme.warningColor),
                    if (isOnLunch) _chip('● On Lunch', AppTheme.infoColor),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // ── Timeline card ─────────────────────────────────────────
              _timelineCard(att).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 10),

              // ── Summary card ──────────────────────────────────────────
              if (att != null)
                _summaryCard(att).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 20),

              // ── Actions ───────────────────────────────────────────────
              _buildActions(
                isLoggedIn,
                isCompleted,
                isOnBreak,
                isOnLunch,
              ).animate().fadeIn(delay: 300.ms),
            ],
          ),
        ),
      ),
    );
  }

  // ── Employee card ─────────────────────────────────────────────────────────
  Widget _employeeCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primaryColor.withOpacity(0.28),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Row(
      children: [
        AppAvatar(
          imageUrl: _sessionEmployee?.photoUrl,
          name: _sessionEmployee?.name ?? '',
          size: 58,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sessionEmployee?.name ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((_sessionEmployee?.employeeCode ?? '').isNotEmpty)
                Text(
                  'ID: ${_sessionEmployee!.employeeCode}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              const SizedBox(height: 4),
              _dateBadge(DateFormat('EEEE, d MMM yyyy').format(DateTime.now())),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _dateBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  // ── Timeline card (all timestamps) ────────────────────────────────────────
  Widget _timelineCard(AttendanceModel? att) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHead(
          'Attendance Timeline',
          Icons.timeline_rounded,
          AppTheme.primaryColor,
        ),
        const SizedBox(height: 14),

        // Check-in / Check-out
        Row(
          children: [
            Expanded(
              child: _tbox(
                'Check-In',
                _fmt(att?.loginTime),
                AppTheme.successColor,
                Icons.login_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tbox(
                'Check-Out',
                _fmt(att?.logoutTime),
                att?.isCompleted == true
                    ? AppTheme.errorColor
                    : const Color(0xFFBBC0CA),
                Icons.logout_rounded,
              ),
            ),
          ],
        ),

        // Break sessions
        if ((att?.breaks ?? []).isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionHead(
            'Break Sessions',
            Icons.coffee_rounded,
            AppTheme.warningColor,
          ),
          const SizedBox(height: 8),
          ...List.generate(att!.breaks.length, (i) {
            final br = att.breaks[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _tbox(
                      'Break ${i + 1} Out',
                      DateFormat('hh:mm a').format(br.breakOut),
                      AppTheme.warningColor,
                      Icons.directions_walk_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tbox(
                      'Break ${i + 1} In',
                      br.breakIn != null
                          ? DateFormat('hh:mm a').format(br.breakIn!)
                          : '● Active',
                      br.breakIn != null
                          ? AppTheme.warningColor
                          : AppTheme.warningColor.withOpacity(0.5),
                      Icons.keyboard_return_rounded,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        // Lunch sessions
        if ((att?.lunches ?? []).isNotEmpty) ...[
          const SizedBox(height: 6),
          _sectionHead(
            'Lunch Sessions',
            Icons.restaurant_rounded,
            AppTheme.infoColor,
          ),
          const SizedBox(height: 8),
          ...List.generate(att!.lunches.length, (i) {
            final ln = att.lunches[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _tbox(
                      'Lunch ${i + 1} Out',
                      DateFormat('hh:mm a').format(ln.lunchOut),
                      AppTheme.infoColor,
                      Icons.restaurant_menu_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tbox(
                      'Lunch ${i + 1} In',
                      ln.lunchIn != null
                          ? DateFormat('hh:mm a').format(ln.lunchIn!)
                          : '● Active',
                      ln.lunchIn != null
                          ? AppTheme.infoColor
                          : AppTheme.infoColor.withOpacity(0.5),
                      Icons.keyboard_return_rounded,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    ),
  );

  // ── Summary card ──────────────────────────────────────────────────────────
  Widget _summaryCard(AttendanceModel att) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHead(
          'Work Summary',
          Icons.summarize_rounded,
          AppTheme.primaryColor,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _sbox(
                'Break',
                att.formattedBreakHours,
                AppTheme.warningColor,
                Icons.coffee_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _sbox(
                'Lunch',
                att.formattedLunchHours,
                AppTheme.infoColor,
                Icons.restaurant_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _sbox(
                'Net Work',
                att.logoutTime != null ? att.formattedWorkHours : 'In progress',
                AppTheme.primaryColor,
                Icons.timer_rounded,
              ),
            ),
          ],
        ),
        if (att.logoutTime != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.successColor.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.successColor,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Net Work = Check-Out − Check-In − Breaks − Lunch',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.successColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  // ── Action buttons ────────────────────────────────────────────────────────
  Widget _buildActions(
    bool isLoggedIn,
    bool isCompleted,
    bool isOnBreak,
    bool isOnLunch,
  ) {
    if (isCompleted) {
      return Column(
        children: [
          _banner(
            Icons.check_circle_rounded,
            AppTheme.successColor,
            "Today's attendance is complete. See you tomorrow!",
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Done',
            icon: Icons.check_rounded,
            onTap: () => Navigator.pop(context),
          ),
        ],
      );
    }

    if (!isLoggedIn) {
      return Column(
        children: [
          _banner(
            Icons.info_rounded,
            AppTheme.infoColor,
            'Tap Check In — face verification will be required.',
          ),
          const SizedBox(height: 12),
          Consumer<AttendanceProvider>(
            builder: (_, att, __) => GradientButton(
              label: 'Check In',
              icon: Icons.login_rounded,
              gradient: AppTheme.accentGradient,
              isLoading: att.isLoading || _processing,
              onTap: () => _requestScan(_ActionType.identify),
            ),
          ),
          const SizedBox(height: 8),
          _faceNote(),
        ],
      );
    }

    // Clocked in
    return Consumer<AttendanceProvider>(
      builder: (_, attProv, __) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  label: isOnBreak ? 'Break In' : 'Break Out',
                  icon: isOnBreak
                      ? Icons.keyboard_return_rounded
                      : Icons.coffee_rounded,
                  color: AppTheme.warningColor,
                  loading: attProv.isLoading || _processing,
                  onTap: () => _requestScan(
                    isOnBreak ? _ActionType.breakIn : _ActionType.breakOut,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionBtn(
                  label: isOnLunch ? 'Lunch In' : 'Lunch Out',
                  icon: isOnLunch
                      ? Icons.keyboard_return_rounded
                      : Icons.restaurant_rounded,
                  color: AppTheme.infoColor,
                  loading: attProv.isLoading || _processing,
                  onTap: () => _requestScan(
                    isOnLunch ? _ActionType.lunchIn : _ActionType.lunchOut,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Check Out',
            icon: Icons.logout_rounded,
            gradient: const LinearGradient(
              colors: [AppTheme.errorColor, Color(0xFFFF8C42)],
            ),
            isLoading: attProv.isLoading || _processing,
            onTap: () => _requestScan(_ActionType.checkOut),
          ),
          const SizedBox(height: 8),
          _faceNote(),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _resetSession,
            child: const Text(
              '← Scan Different Employee',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Small UI helpers ──────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _sectionHead(String label, IconData icon, Color color) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );

  Widget _tbox(String label, String value, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(10),
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
                Icon(icon, size: 10, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _sbox(String label, String value, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required bool loading,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: loading
          ? Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
    ),
  ).animate().fadeIn(duration: 300.ms);

  Widget _banner(IconData icon, Color color, String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  ).animate().scale(begin: const Offset(0.9, 0.9), duration: 350.ms);

  Widget _faceNote() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.security_rounded, size: 11, color: AppTheme.textMuted),
      const SizedBox(width: 4),
      Text(
        'Face verification required for every action',
        style: TextStyle(
          fontSize: 10,
          color: AppTheme.textMuted,
          fontStyle: FontStyle.italic,
        ),
      ),
    ],
  );

  Widget _verifiedBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.successColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.successColor.withOpacity(0.3)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, color: AppTheme.successColor, size: 12),
        SizedBox(width: 4),
        Text(
          'Verified',
          style: TextStyle(
            color: AppTheme.successColor,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );

  Widget _backBtn() => GestureDetector(
    onTap: () => Navigator.pop(context),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: const Icon(
        Icons.arrow_back_ios_rounded,
        size: 15,
        color: AppTheme.textPrimary,
      ),
    ),
  );

  String _fmt(DateTime? dt) =>
      dt != null ? DateFormat('hh:mm a').format(dt) : '--:--';
}
