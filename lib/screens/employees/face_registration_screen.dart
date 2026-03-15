// lib/screens/employees/face_registration_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// WHERE THIS SCREEN IS USED
// ─────────────────────────────────────────────────────────────────────────────
//  1. EmployeeFormScreen  → "Register Face" button (Add Worker / Edit Worker)
//     The descriptor returned here is stored in Firestore as faceDescriptor.
//
//  2. EmployeeDetailScreen → "Re-register Face" button (admin can re-register
//     an existing employee if their face data is stale or shows needsMigration)
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW TO USE
// ─────────────────────────────────────────────────────────────────────────────
//   final String? descriptor = await Navigator.push<String>(
//     context,
//     MaterialPageRoute(builder: (_) => const FaceRegistrationScreen()),
//   );
//   if (descriptor != null) {
//     // Save descriptor to employee record via EmployeeProvider.updateEmployee
//   }
//
// Returns null if user cancels. Returns a JSON descriptor string on success.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/face_detection_service.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() =>
      _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen>
    with WidgetsBindingObserver {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _ctrl;
  CameraDescription? _frontCamera;
  bool _cameraReady = false;
  bool _streaming   = false;
  bool _detecting   = false;

  // ── Face service ──────────────────────────────────────────────────────────
  final FaceDetectionService _faceService = FaceDetectionService();

  // ── State ─────────────────────────────────────────────────────────────────
  _RegPhase _phase          = _RegPhase.positioning;
  String    _statusMsg      = 'Position your face in the frame';
  Color     _statusColor    = Colors.white;
  int       _samplesCollected = 0;
  bool      _disposed       = false;

  static const int _requiredSamples = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceService.initialize();
    _faceService.resetSamples();
    _initCamera();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _ctrl?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopStream();
      _ctrl?.dispose();
      _ctrl = null;
      if (mounted) setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      if (_frontCamera != null) _initController(_frontCamera!);
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || _disposed) return;

      // Front camera — same lens as attendance scanner
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _frontCamera = front;
      await _initController(front);
    } catch (e) {
      debugPrint('[FaceReg] initCamera: $e');
      if (mounted) setState(() {
        _statusMsg   = 'Camera unavailable. Please try again.';
        _statusColor = AppTheme.errorColor;
      });
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    if (_disposed) return;
    try {
      final ctrl = CameraController(
        camera,
        ResolutionPreset.medium, // 640×480 — same as attendance scanner
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // NV21 — same as attendance
      );
      await ctrl.initialize();
      if (_disposed || !mounted) { await ctrl.dispose(); return; }
      setState(() { _ctrl = ctrl; _cameraReady = true; });
      _startStream();
    } catch (e) {
      debugPrint('[FaceReg] initController: $e');
      if (mounted) setState(() {
        _statusMsg   = 'Camera error. Please try again.';
        _statusColor = AppTheme.errorColor;
      });
    }
  }

  void _startStream() {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _streaming) return;
    _streaming = true;

    ctrl.startImageStream((frame) async {
      if (_disposed || !mounted || _detecting) return;
      if (_phase == _RegPhase.done || _phase == _RegPhase.error) return;

      _detecting = true;
      try {
        final cameras = await availableCameras();
        if (_disposed) return;
        final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        final faces =
            await _faceService.detectFacesFromCameraImage(frame, front);

        if (_disposed || !mounted) return;

        if (faces.isEmpty) {
          setState(() {
            _phase       = _RegPhase.positioning;
            _statusMsg   = 'Position your face in the frame';
            _statusColor = Colors.white;
          });
          return;
        }

        final face        = faces.first;
        final livenessErr = _faceService.livenessCheck(face,
            frameWidth:  frame.width,
            frameHeight: frame.height);

        if (livenessErr != null) {
          setState(() {
            _phase       = _RegPhase.positioning;
            _statusMsg   = livenessErr;
            _statusColor = AppTheme.warningColor;
          });
          return;
        }

        // Good frame — start/continue collecting
        if (mounted) setState(() {
          _phase       = _RegPhase.collecting;
          _statusColor = AppTheme.successColor;
          _statusMsg   = 'Hold still... ($_samplesCollected / $_requiredSamples)';
        });

        final descriptor =
            _faceService.accumulateRegistrationFrame(frame, face);

        if (mounted) {
          setState(() =>
              _samplesCollected = _faceService.sampleCount);
        }

        if (descriptor != null) {
          // All 10 samples done — return descriptor to caller
          await _stopStream();
          if (!mounted) return;
          setState(() {
            _phase       = _RegPhase.done;
            _statusMsg   = 'Face registered successfully!';
            _statusColor = AppTheme.successColor;
          });
          await Future.delayed(const Duration(milliseconds: 900));
          if (mounted) Navigator.pop(context, descriptor);
        }
      } catch (e) {
        debugPrint('[FaceReg] stream: $e');
      } finally {
        _detecting = false;
      }
    });
  }

  Future<void> _stopStream() async {
    _streaming = false;
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isStreamingImages) {
      try { await ctrl.stopImageStream(); } catch (_) {}
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [

        // ── Camera preview ───────────────────────────────────────────────
        if (_cameraReady && _ctrl != null)
          CameraPreview(_ctrl!)
        else
          const ColoredBox(
            color: Color(0xFF0A0A14),
            child: Center(child: CircularProgressIndicator(
                color: AppTheme.primaryColor)),
          ),

        // ── Dark gradient ────────────────────────────────────────────────
        DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.70),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.85),
            ],
            stops: const [0, 0.25, 0.60, 1],
          ),
        )),

        // ── Top bar ──────────────────────────────────────────────────────
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context, null),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black45,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Register Face', style: TextStyle(
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w800)),
                Text('Use front camera for best results',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ]),
        )),

        // ── Face oval ────────────────────────────────────────────────────
        Center(child: _buildFaceOval()),

        // ── Progress bar (while collecting) ─────────────────────────────
        if (_phase == _RegPhase.collecting)
          Positioned(
            left:  60,
            right: 60,
            top:   MediaQuery.of(context).size.height * 0.68,
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _samplesCollected / _requiredSamples,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(
                      AppTheme.successColor),
                ),
              ),
              const SizedBox(height: 6),
              Text('$_samplesCollected of $_requiredSamples frames captured',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11)),
            ]),
          ),

        // ── Bottom HUD ───────────────────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Status pill
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Container(
                  key: ValueKey(_statusMsg),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_phaseIcon(), color: _statusColor, size: 15),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_statusMsg,
                        style: TextStyle(color: _statusColor,
                            fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Look straight at the camera and keep still.\n'
                'The system captures automatically — no button needed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _buildFaceOval() {
    Color frameColor;
    switch (_phase) {
      case _RegPhase.positioning:
        frameColor = Colors.white54;
        break;
      case _RegPhase.collecting:
        frameColor = AppTheme.successColor;
        break;
      case _RegPhase.done:
        frameColor = AppTheme.successColor;
        break;
      case _RegPhase.error:
        frameColor = AppTheme.errorColor;
        break;
    }

    return AnimatedBuilder(
      animation: const AlwaysStoppedAnimation(0),
      builder: (_, __) => Container(
        width: 220, height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(110),
          border: Border.all(color: frameColor, width: 3),
        ),
        child: _phase == _RegPhase.done
            ? Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppTheme.successColor, size: 72)
                      .animate().scale(duration: 400.ms),
                  const SizedBox(height: 10),
                  const Text('Done!', style: TextStyle(
                      color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w700)),
                ]))
            : null,
      ),
    );
  }

  IconData _phaseIcon() {
    switch (_phase) {
      case _RegPhase.positioning: return Icons.face_retouching_natural;
      case _RegPhase.collecting:  return Icons.adjust_rounded;
      case _RegPhase.done:        return Icons.verified_rounded;
      case _RegPhase.error:       return Icons.error_outline_rounded;
    }
  }
}

enum _RegPhase { positioning, collecting, done, error }