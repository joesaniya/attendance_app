// lib/screens/employees/employee_form_screen.dart
//
// FaceRegistrationScreen is called from the "Register Face" button inside
// _buildFaceCard(). The descriptor it returns is stored in
// _capturedFaceDescriptor and saved to Firestore when the form is submitted.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../data/models/employee_model.dart';
import '../../widgets/app_widgets.dart';
// ★ FaceRegistrationScreen import — this is where it plugs in
import 'face_registration_screen.dart';

class EmployeeFormScreen extends StatefulWidget {
  final EmployeeModel? employee;
  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _picker = ImagePicker();

  File? _selectedPhoto;
  bool _photoError = false;
  bool _faceError = false;
  bool _isEditing = false;
  bool _faceRegistered = false;
  String? _capturedFaceDescriptor;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.employee != null;
    if (_isEditing) {
      final e = widget.employee!;
      _nameCtrl.text = e.name;
      _emailCtrl.text = e.email;
      _phoneCtrl.text = e.phone;
      _addressCtrl.text = e.address;
      _capturedFaceDescriptor = e.faceDescriptor;
      _faceRegistered =
          e.faceDescriptor != null && e.faceDescriptor!.isNotEmpty;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostPhoto());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // ── Recover lost gallery image ────────────────────────────────────────────
  Future<void> _recoverLostPhoto() async {
    if (!mounted) return;
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty || response.file == null) return;
      await Future.delayed(const Duration(milliseconds: 200));
      final file = File(response.file!.path);
      if (await file.exists() && mounted) _applyPhoto(file);
    } catch (e) {
      debugPrint('[LostData] $e');
    }
  }

  void _applyPhoto(File file) {
    if (!mounted) return;
    setState(() {
      _selectedPhoto = file;
      _photoError = false;
    });
  }

  // ── Photo picker (profile picture only) ──────────────────────────────────
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 16),
            ListTile(
              leading: _iconBox(
                Icons.camera_alt_rounded,
                AppTheme.primaryColor,
              ),
              title: const Text(
                'Take Photo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(context, _PhotoSource.camera),
            ),
            ListTile(
              leading: _iconBox(
                Icons.photo_library_rounded,
                AppTheme.accentColor,
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(context, _PhotoSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == _PhotoSource.camera) {
      await _openInAppCamera();
    } else {
      await _pickFromGallery();
    }
  }

  Future<void> _openInAppCamera() async {
    final File? result = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _InAppCameraScreen(),
      ),
    );
    if (result != null && mounted) await _validateAndApplyPhoto(result);
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (image == null) {
        await _recoverLostPhoto();
        return;
      }
      await _validateAndApplyPhoto(File(image.path));
    } on PlatformException catch (pe) {
      if (mounted)
        _snack(
          pe.code == 'photo_access_denied'
              ? 'Gallery permission denied. Please enable it in Settings.'
              : 'Gallery error: ${pe.message ?? 'Unknown error.'}',
          AppTheme.errorColor,
        );
    } catch (e) {
      if (mounted) _snack('Could not open gallery.', AppTheme.errorColor);
    }
  }

  Future<void> _validateAndApplyPhoto(File file) async {
    if (!await file.exists()) {
      if (mounted) _snack('Could not access photo.', AppTheme.errorColor);
      return;
    }
    if (await file.length() == 0) {
      if (mounted) _snack('Photo file is empty.', AppTheme.errorColor);
      return;
    }
    final bytes = await file.readAsBytes();
    if (img.decodeImage(bytes) == null) {
      if (mounted) _snack('Image could not be read.', AppTheme.errorColor);
      return;
    }
    if (mounted) _applyPhoto(file);
  }

  // ── ★ FACE REGISTRATION — opens FaceRegistrationScreen ───────────────────
  //
  // This is where FaceRegistrationScreen is called.
  // It pushes the screen as a full-screen dialog, awaits the descriptor
  // string returned by the live-camera registration flow, and stores it
  // in _capturedFaceDescriptor ready to be saved with the form.
  //
  Future<void> _registerFace() async {
    final String? descriptor = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FaceRegistrationScreen(),
      ),
    );

    if (!mounted) return;

    if (descriptor == null) {
      // User cancelled — do nothing
      return;
    }

    setState(() {
      _capturedFaceDescriptor = descriptor;
      _faceRegistered = true;
      _faceError = false;
    });
    _snack('✓ Face registered successfully!', AppTheme.successColor);
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final hasPhoto =
        _selectedPhoto != null ||
        (_isEditing && widget.employee?.photoUrl != null);
    if (!hasPhoto) {
      setState(() => _photoError = true);
      return;
    }

    if (!_faceRegistered || _capturedFaceDescriptor == null) {
      setState(() => _faceError = true);
      _snack(
        'Face registration is required. Tap "Register Face".',
        AppTheme.errorColor,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final provider = context.read<EmployeeProvider>();

    if (_isEditing) {
      final ok = await provider.updateEmployee(
        employeeId: widget.employee!.id,
        data: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'department': widget.employee?.department ?? '',
          'position': widget.employee?.position ?? '',
          'address': _addressCtrl.text.trim(),
          'faceDescriptor': _capturedFaceDescriptor,
        },
        newPhotoFile: _selectedPhoto,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        _snack('Worker updated successfully!', AppTheme.successColor);
      } else {
        _snack(provider.error ?? 'Update failed', AppTheme.errorColor);
      }
    } else {
      if (await provider.isNameDuplicate(_nameCtrl.text.trim())) {
        _snack(
          'An employee with this name already exists.',
          AppTheme.errorColor,
        );
        return;
      }
      final employee = await provider.createEmployee(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        department: '',
        position: '',
        address: _addressCtrl.text.trim(),
        photoFile: _selectedPhoto,
        createdBy: auth.currentUser!.id,
        createdByRole: auth.currentUser!.role,
        createdByName: auth.currentUser!.name,
        faceDescriptor: _capturedFaceDescriptor,
      );
      if (!mounted) return;
      if (employee != null) {
        Navigator.pop(context);
        _snack(
          '${employee.name} added! Code: ${employee.employeeCode}',
          AppTheme.successColor,
        );
      } else {
        _snack(provider.error ?? 'Failed to add worker', AppTheme.errorColor);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // =========================================================================
  // BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Worker' : 'Add Worker'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Profile photo (separate from face registration) ──────
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                          onTap: _pickPhoto,
                          child: Stack(
                            children: [
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: _photoError
                                      ? const LinearGradient(
                                          colors: [
                                            AppTheme.errorColor,
                                            Color(0xFFFF8C42),
                                          ],
                                        )
                                      : AppTheme.primaryGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_photoError
                                                  ? AppTheme.errorColor
                                                  : AppTheme.primaryColor)
                                              .withOpacity(0.35),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: _photoWidget(),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(begin: const Offset(0.8, 0.8)),
                    const SizedBox(height: 6),
                    if (_photoError)
                      const Text(
                        'Photo is required *',
                        style: TextStyle(
                          color: AppTheme.errorColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        _selectedPhoto != null
                            ? '✓ Photo selected'
                            : (_isEditing
                                  ? 'Tap to change photo'
                                  : 'Tap to add photo *'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedPhoto != null
                              ? AppTheme.successColor
                              : AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Personal Info ────────────────────────────────────────
              _sectionTitle(
                'Personal Information',
                Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),

              _fieldLabel('FULL NAME *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco(
                  'e.g. Ravi Kumar',
                  Icons.person_outlined,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              _fieldLabel('EMAIL ADDRESS (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco('ravi@farm.com', Icons.email_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _fieldLabel('PHONE NUMBER (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                decoration: _inputDeco(
                  '10-digit number',
                  Icons.phone_outlined,
                ).copyWith(counterText: ''),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final d = v.replaceAll(RegExp(r'\D'), '');
                  if (d.length != 10) {
                    return 'Phone must be exactly 10 digits '
                        '(${d.length} entered)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _fieldLabel('HOME ADDRESS / VILLAGE (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: _inputDeco(
                  'e.g. 12 Green Acres, Kovai',
                  Icons.location_on_outlined,
                ),
              ),
              const SizedBox(height: 28),

              // ── ★ Face Registration card ─────────────────────────────
              // This is the section that calls FaceRegistrationScreen
              _buildFaceCard(),
              const SizedBox(height: 24),

              // ── Created by ───────────────────────────────────────────
              Consumer<AuthProvider>(
                builder: (_, auth, __) => GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _iconBox(
                        Icons.agriculture_rounded,
                        AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Record added by',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Text(
                            auth.currentUser?.name ?? 'Admin',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Submit ───────────────────────────────────────────────
              Consumer<EmployeeProvider>(
                builder: (_, p, __) => GradientButton(
                  label: _isEditing ? 'Update Worker' : 'Add Worker',
                  icon: _isEditing
                      ? Icons.check_rounded
                      : Icons.person_add_rounded,
                  isLoading: p.isLoading,
                  onTap: _save,
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  // ── Photo widget ──────────────────────────────────────────────────────────
  Widget _photoWidget() {
    if (_selectedPhoto != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(55),
        child: Image.file(
          _selectedPhoto!,
          fit: BoxFit.cover,
          width: 110,
          height: 110,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_rounded,
            color: Colors.white,
            size: 50,
          ),
        ),
      );
    }
    if (_isEditing && widget.employee?.photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(55),
        child: Image.network(
          widget.employee!.photoUrl!,
          fit: BoxFit.cover,
          width: 110,
          height: 110,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.person_rounded, color: Colors.white, size: 50),
        ),
      );
    }
    return Icon(
      _photoError ? Icons.error_rounded : Icons.person_rounded,
      color: Colors.white,
      size: 50,
    );
  }

  // ── ★ Face registration card ──────────────────────────────────────────────
  //
  // This card contains the "Register Face" button.
  // Tapping it calls _registerFace() which pushes FaceRegistrationScreen.
  //
  Widget _buildFaceCard() => GlassCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Face Registration *', Icons.face_rounded),
        const SizedBox(height: 4),

        const Text(
          'Required — opens the front camera to capture a live face signature.\n'
          'This ensures accurate, tamper-proof matching at attendance time.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 12),

        // Status banner
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _faceRegistered
              ? _infoBanner(
                  key: const ValueKey('ok'),
                  icon: Icons.verified_rounded,
                  color: AppTheme.successColor,
                  text:
                      'Face registered via live camera. '
                      'This worker will be auto-detected at attendance.',
                )
              : _infoBanner(
                  key: const ValueKey('warn'),
                  icon: _faceError
                      ? Icons.error_outline_rounded
                      : Icons.info_outline_rounded,
                  color: _faceError
                      ? AppTheme.errorColor
                      : AppTheme.warningColor,
                  text: _faceError
                      ? 'Face registration is required before saving.'
                      : 'Tap "Register Face" and follow the on-screen instructions.',
                ),
        ),
        const SizedBox(height: 12),

        // ★ Register Face button — tapping this opens FaceRegistrationScreen
        GestureDetector(
          onTap: _registerFace,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 48,
            decoration: BoxDecoration(
              gradient: _faceRegistered ? null : AppTheme.primaryGradient,
              color: _faceRegistered
                  ? AppTheme.successColor.withOpacity(0.1)
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: _faceRegistered
                  ? Border.all(color: AppTheme.successColor.withOpacity(0.4))
                  : (_faceError
                        ? Border.all(color: AppTheme.errorColor)
                        : null),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _faceRegistered ? Icons.refresh_rounded : Icons.face_rounded,
                  color: _faceRegistered ? AppTheme.successColor : Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _faceRegistered ? 'Re-register Face' : 'Register Face',
                  style: TextStyle(
                    color: _faceRegistered
                        ? AppTheme.successColor
                        : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Hint
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 12,
              color: AppTheme.textMuted,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'The employee must be physically present to register their face.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _infoBanner({
    required Key key,
    required IconData icon,
    required Color color,
    required String text,
  }) => Container(
    key: key,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _iconBox(IconData icon, Color color) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: color),
  );

  Widget _sectionTitle(String t, IconData icon) => Row(
    children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Icon(icon, size: 16, color: AppTheme.primaryColor),
      const SizedBox(width: 6),
      Text(t, style: AppTextStyles.heading3),
    ],
  );

  Widget _fieldLabel(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textSecondary,
      letterSpacing: 0.8,
    ),
  );

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.errorColor),
    ),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
  );
}

enum _PhotoSource { camera, gallery }

// ─────────────────────────────────────────────────────────────────────────────
// In-app camera (profile photo capture — NOT face registration)
// ─────────────────────────────────────────────────────────────────────────────
class _InAppCameraScreen extends StatefulWidget {
  const _InAppCameraScreen();
  @override
  State<_InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<_InAppCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isCapturing = false;
  bool _flashOn = false;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty) _initController(_cameras[_cameraIndex]);
    }
  }

  Future<void> _disposeController() async {
    final ctrl = _controller;
    _controller = null;
    try {
      await ctrl?.dispose();
    } catch (_) {}
  }

  Future<void> _initCameras() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted)
          setState(() {
            _error = 'No cameras found.';
            _initializing = false;
          });
        return;
      }
      final backIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = backIdx >= 0 ? backIdx : 0;
      await _initController(_cameras[_cameraIndex]);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Camera error: $e';
          _initializing = false;
        });
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    if (!mounted) return;
    await _disposeController();
    final ctrl = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      await ctrl.dispose();
      if (mounted)
        setState(() {
          _error = 'Camera error: ${e.description ?? e.code}';
          _initializing = false;
        });
      return;
    }
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    setState(() {
      _controller = ctrl;
      _initializing = false;
      _error = null;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isCapturing) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _flashOn = false;
    await _initController(_cameras[_cameraIndex]);
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final isBack =
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    if (!isBack) return;
    try {
      _flashOn = !_flashOn;
      await ctrl.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      if (_flashOn) {
        try {
          await ctrl.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      final XFile photo = await ctrl.takePicture();
      final File file = File(photo.path);
      if (!await file.exists() || await file.length() == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Capture failed. Please try again.'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
          setState(() => _isCapturing = false);
        }
        return;
      }
      if (mounted) Navigator.pop(context, file);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: ${e.description ?? e.code}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        setState(() => _isCapturing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture failed. Please try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(backgroundColor: Colors.black, body: _buildBody());

  Widget _buildBody() {
    if (_error != null) return _errorView();
    if (_initializing ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    final isBack =
        _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(_controller!)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _glassBtn(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context, null),
                ),
                const Spacer(),
                if (isBack)
                  _glassBtn(
                    icon: _flashOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    onTap: _toggleFlash,
                    active: _flashOn,
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_cameras.length > 1)
                    _glassBtn(
                      icon: Icons.flip_camera_ios_rounded,
                      onTap: _initializing ? null : _switchCamera,
                      size: 48,
                    )
                  else
                    const SizedBox(width: 48),
                  GestureDetector(
                    onTap: _isCapturing ? null : _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _isCapturing ? Colors.white38 : Colors.white,
                      ),
                      child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.camera_alt_outlined,
            color: Colors.white54,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _initCameras,
            child: const Text(
              'Retry',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _glassBtn({
    required IconData icon,
    VoidCallback? onTap,
    bool active = false,
    double size = 40,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? Colors.white.withOpacity(0.30)
            : Colors.black.withOpacity(0.45),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    ),
  );
}
