// lib/screens/employees/employee_form_screen.dart
//
// Changes from original:
//  • Farm assignment (department) and Role (position) dropdowns REMOVED — they
//    are no longer shown or validated.  The fields are still saved as empty
//    strings so existing records stay compatible.
//  • Name is mandatory (unchanged).
//  • Photo is mandatory (unchanged).
//  • Face registration is NOW mandatory — the form cannot be saved until a face
//    descriptor has been captured from the selected photo.
//  • FIXED: Camera crash on Android — added retrieveLostData() recovery,
//    maxWidth/maxHeight limits to prevent OOM, PlatformException handling,
//    and file existence guard.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../data/models/employee_model.dart';
import '../../data/services/face_detection_service.dart';
import '../../widgets/app_widgets.dart';

class EmployeeFormScreen extends StatefulWidget {
  final EmployeeModel? employee;
  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  File? _selectedPhoto;
  bool _photoError = false;
  bool _faceError = false;
  bool _isEditing = false;

  String? _capturedFaceDescriptor;
  bool _isScanningFace = false;
  bool _faceRegistered = false;
  final FaceDetectionService _faceService = FaceDetectionService();

  @override
  void initState() {
    super.initState();
    _isEditing = widget.employee != null;
    _faceService.initialize();
    // _recoverLostPhoto(); // Recover image if Android killed the activity

    if (_isEditing) {
      final e = widget.employee!;
      _nameController.text = e.name;
      _emailController.text = e.email;
      _phoneController.text = e.phone;
      _addressController.text = e.address;

      _capturedFaceDescriptor = e.faceDescriptor;
      _faceRegistered =
          e.faceDescriptor != null && e.faceDescriptor!.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _faceService.dispose();
    super.dispose();
  }

  // ── Lost data recovery (Android camera activity killed by OS) ─────────────────
  Future<void> _recoverLostPhoto() async {
    try {
      final LostDataResponse response = await ImagePicker().retrieveLostData();
      if (response.isEmpty) return;

      if (response.file != null) {
        final file = File(response.file!.path);
        if (await file.exists()) {
          if (mounted) {
            setState(() {
              _selectedPhoto = file;
              _photoError = false;
              _faceRegistered = false;
              _capturedFaceDescriptor = null;
              _faceError = false;
            });
          }
        }
      } else if (response.exception != null) {
        debugPrint('Lost image recovery error: ${response.exception}');
      }
    } catch (e) {
      debugPrint('retrieveLostData error: $e');
    }
  }

  // ── Photo picker ──────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
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
              onTap: () => Navigator.pop(context, ImageSource.camera),
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
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1280, // Prevents OOM from high-res back camera shots
        maxHeight: 1280,
      );

      if (image == null) return; // User cancelled or camera dismissed

      final file = File(image.path);
      if (!await file.exists()) {
        _snack(
          'Could not access the photo. Please try again.',
          AppTheme.errorColor,
        );
        return;
      }

      if (mounted) {
        setState(() {
          _selectedPhoto = file;
          _photoError = false;
          // Reset face when photo changes — force re-registration
          _faceRegistered = false;
          _capturedFaceDescriptor = null;
          _faceError = false;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Image picker PlatformException: $e');
      if (mounted) {
        _snack(
          e.code == 'camera_access_denied'
              ? 'Camera permission denied. Please enable it in Settings.'
              : 'Camera error: ${e.message ?? 'Unknown error'}',
          AppTheme.errorColor,
        );
      }
    } catch (e) {
      debugPrint('Image picker unexpected error: $e');
      if (mounted) {
        _snack(
          'Unexpected error opening camera. Please try again.',
          AppTheme.errorColor,
        );
      }
    }
  }

  Widget _iconBox(IconData icon, Color color) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: color),
  );

  // ── Face capture ──────────────────────────────────────────────────────────────
  Future<void> _captureFace() async {
    if (_selectedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a photo first, then register the face.'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isScanningFace = true);

    try {
      final faces = await _faceService.detectFacesFromFile(_selectedPhoto!);

      if (faces.isEmpty) {
        _snack(
          'No face detected. Use a clear front-facing photo.',
          AppTheme.errorColor,
        );
        setState(() => _isScanningFace = false);
        return;
      }
      if (faces.length > 1) {
        _snack(
          'Multiple faces detected. Use a photo with only one person.',
          AppTheme.warningColor,
        );
        setState(() => _isScanningFace = false);
        return;
      }

      final descriptor = _faceService.buildFaceDescriptor(faces.first);
      if (descriptor == null) {
        _snack(
          'Could not extract face features. Try a clearer photo.',
          AppTheme.errorColor,
        );
        setState(() => _isScanningFace = false);
        return;
      }

      setState(() {
        _capturedFaceDescriptor = descriptor;
        _faceRegistered = true;
        _faceError = false;
        _isScanningFace = false;
      });
      _snack('✓ Face registered successfully!', AppTheme.successColor);
    } catch (e) {
      _snack('Face detection error: $e', AppTheme.errorColor);
      setState(() => _isScanningFace = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Save ──────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    // Photo mandatory
    final hasPhoto =
        _selectedPhoto != null ||
        (_isEditing && widget.employee?.photoUrl != null);
    if (!hasPhoto) {
      setState(() => _photoError = true);
      return;
    }

    // Face registration mandatory
    if (!_faceRegistered || _capturedFaceDescriptor == null) {
      setState(() => _faceError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Face registration is required. Tap "Register Face from Photo".',
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final provider = context.read<EmployeeProvider>();

    if (_isEditing) {
      final data = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'department': widget.employee?.department ?? '',
        'position': widget.employee?.position ?? '',
        'address': _addressController.text.trim(),
        'faceDescriptor': _capturedFaceDescriptor,
      };

      final ok = await provider.updateEmployee(
        employeeId: widget.employee!.id,
        data: data,
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
      // Check for duplicate name
      final isDuplicate = await provider.isNameDuplicate(
        _nameController.text.trim(),
      );
      if (isDuplicate) {
        _snack(
          'An employee with this name already exists.',
          AppTheme.errorColor,
        );
        return;
      }

      final employee = await provider.createEmployee(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        department: '',
        position: '',
        address: _addressController.text.trim(),
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

  // ── Build ─────────────────────────────────────────────────────────────────────
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
              // ── Photo (mandatory) ─────────────────────────────────────────
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
                                child: _selectedPhoto != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(55),
                                        child: Image.file(
                                          _selectedPhoto!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : (_isEditing &&
                                              widget.employee?.photoUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(55),
                                              child: Image.network(
                                                widget.employee!.photoUrl!,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Icon(
                                              _photoError
                                                  ? Icons.error_rounded
                                                  : Icons.person_rounded,
                                              color: Colors.white,
                                              size: 50,
                                            )),
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

              // ── Personal Info ─────────────────────────────────────────────
              _sectionTitle(
                'Personal Information',
                Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),

              // Name (mandatory + unique)
              _fieldLabel('FULL NAME *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: _inputDeco(
                  'e.g. Ravi Kumar',
                  Icons.person_outlined,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              // Email (optional)
              _fieldLabel('EMAIL ADDRESS (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
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

              // Phone (optional)
              _fieldLabel('PHONE NUMBER (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                decoration: _inputDeco(
                  '10-digit number',
                  Icons.phone_outlined,
                ).copyWith(counterText: ''),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final digits = v.replaceAll(RegExp(r'\D'), '');
                  if (digits.length != 10) {
                    return 'Phone must be exactly 10 digits (${digits.length} entered)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Address (optional)
              _fieldLabel('HOME ADDRESS / VILLAGE (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: _inputDeco(
                  'e.g. 12 Green Acres, Kovai',
                  Icons.location_on_outlined,
                ),
              ),
              const SizedBox(height: 28),

              // ── Face Registration (mandatory) ─────────────────────────────
              _buildFaceRegisterCard(),
              const SizedBox(height: 24),

              // ── Created by info ───────────────────────────────────────────
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

              // ── Submit ────────────────────────────────────────────────────
              Consumer<EmployeeProvider>(
                builder: (_, provider, __) => GradientButton(
                  label: _isEditing ? 'Update Worker' : 'Add Worker',
                  icon: _isEditing
                      ? Icons.check_rounded
                      : Icons.person_add_rounded,
                  isLoading: provider.isLoading,
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

  // ── Face register card ────────────────────────────────────────────────────────
  Widget _buildFaceRegisterCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Face Registration *', Icons.face_rounded),
          const SizedBox(height: 4),
          const Text(
            'Required — the employee will be identified by face at check-in/out.',
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
                        'Face registered! This worker will be auto-detected at check-in.',
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
                        : 'No face registered. Add a front-facing photo then tap Register Face.',
                  ),
          ),
          const SizedBox(height: 12),

          // Register button
          GestureDetector(
            onTap: _isScanningFace ? null : _captureFace,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
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
              child: _isScanningFace
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _faceRegistered
                              ? Icons.refresh_rounded
                              : Icons.face_rounded,
                          color: _faceRegistered
                              ? AppTheme.successColor
                              : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _faceRegistered
                              ? 'Re-register Face'
                              : 'Register Face from Photo',
                          style: TextStyle(
                            color: _faceRegistered
                                ? AppTheme.successColor
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner({
    required Key key,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
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
  }

  Widget _sectionTitle(String title, IconData icon) => Row(
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
      Text(title, style: AppTextStyles.heading3),
    ],
  );

  Widget _fieldLabel(String text) => Text(
    text,
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


/*crushissue
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../data/models/employee_model.dart';
import '../../data/services/face_detection_service.dart';
import '../../widgets/app_widgets.dart';

class EmployeeFormScreen extends StatefulWidget {
  final EmployeeModel? employee;
  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  File? _selectedPhoto;
  bool _photoError = false;
  bool _faceError = false; // shown when user tries to save without face
  bool _isEditing = false;

  String? _capturedFaceDescriptor;
  bool _isScanningFace = false;
  bool _faceRegistered = false;
  final FaceDetectionService _faceService = FaceDetectionService();

  @override
  void initState() {
    super.initState();
    _isEditing = widget.employee != null;
    _faceService.initialize();

    if (_isEditing) {
      final e = widget.employee!;
      _nameController.text = e.name;
      _emailController.text = e.email;
      _phoneController.text = e.phone;
      _addressController.text = e.address;

      _capturedFaceDescriptor = e.faceDescriptor;
      _faceRegistered =
          e.faceDescriptor != null && e.faceDescriptor!.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _faceService.dispose();
    super.dispose();
  }

  // ── Photo picker ──────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
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
              onTap: () => Navigator.pop(context, ImageSource.camera),
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
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null) return;
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _selectedPhoto = File(image.path);
        _photoError = false;
        // Reset face when photo changes — force re-registration
        _faceRegistered = false;
        _capturedFaceDescriptor = null;
        _faceError = false;
      });
    }
  }

  Widget _iconBox(IconData icon, Color color) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: color),
  );

  // ── Face capture ──────────────────────────────────────────────────────────────
  Future<void> _captureFace() async {
    if (_selectedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a photo first, then register the face.'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isScanningFace = true);

    try {
      final faces = await _faceService.detectFacesFromFile(_selectedPhoto!);

      if (faces.isEmpty) {
        _snack(
          'No face detected. Use a clear front-facing photo.',
          AppTheme.errorColor,
        );
        setState(() => _isScanningFace = false);
        return;
      }
      if (faces.length > 1) {
        _snack(
          'Multiple faces detected. Use a photo with only one person.',
          AppTheme.warningColor,
        );
        setState(() => _isScanningFace = false);
        return;
      }

      final descriptor = _faceService.buildFaceDescriptor(faces.first);
      if (descriptor == null) {
        _snack(
          'Could not extract face features. Try a clearer photo.',
          AppTheme.errorColor,
        );
        setState(() => _isScanningFace = false);
        return;
      }

      setState(() {
        _capturedFaceDescriptor = descriptor;
        _faceRegistered = true;
        _faceError = false;
        _isScanningFace = false;
      });
      _snack('✓ Face registered successfully!', AppTheme.successColor);
    } catch (e) {
      _snack('Face detection error: $e', AppTheme.errorColor);
      setState(() => _isScanningFace = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Save ──────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    // Photo mandatory
    final hasPhoto =
        _selectedPhoto != null ||
        (_isEditing && widget.employee?.photoUrl != null);
    if (!hasPhoto) {
      setState(() => _photoError = true);
      return;
    }

    // Face registration mandatory
    if (!_faceRegistered || _capturedFaceDescriptor == null) {
      setState(() => _faceError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Face registration is required. Tap "Register Face from Photo".',
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final provider = context.read<EmployeeProvider>();

    if (_isEditing) {
      final data = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'department': widget.employee?.department ?? '',
        'position': widget.employee?.position ?? '',
        'address': _addressController.text.trim(),
        'faceDescriptor': _capturedFaceDescriptor,
      };

      final ok = await provider.updateEmployee(
        employeeId: widget.employee!.id,
        data: data,
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
      // Check for duplicate name
      final isDuplicate = await provider.isNameDuplicate(
        _nameController.text.trim(),
      );
      if (isDuplicate) {
        _snack(
          'An employee with this name already exists.',
          AppTheme.errorColor,
        );
        return;
      }

      final employee = await provider.createEmployee(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        department: '',
        position: '',
        address: _addressController.text.trim(),
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

  // ── Build ─────────────────────────────────────────────────────────────────────
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
              // ── Photo (mandatory) ─────────────────────────────────────────
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
                                child: _selectedPhoto != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(55),
                                        child: Image.file(
                                          _selectedPhoto!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : (_isEditing &&
                                              widget.employee?.photoUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(55),
                                              child: Image.network(
                                                widget.employee!.photoUrl!,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Icon(
                                              _photoError
                                                  ? Icons.error_rounded
                                                  : Icons.person_rounded,
                                              color: Colors.white,
                                              size: 50,
                                            )),
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

              // ── Personal Info ─────────────────────────────────────────────
              _sectionTitle(
                'Personal Information',
                Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),

              // Name (mandatory + unique)
              _fieldLabel('FULL NAME *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: _inputDeco(
                  'e.g. Ravi Kumar',
                  Icons.person_outlined,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              // Email (optional)
              _fieldLabel('EMAIL ADDRESS (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco('ravi@farm.com', Icons.email_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // optional
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone (optional)
              _fieldLabel('PHONE NUMBER (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                decoration: _inputDeco(
                  '10-digit number',
                  Icons.phone_outlined,
                ).copyWith(counterText: ''),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // optional
                  final digits = v.replaceAll(RegExp(r'\D'), '');
                  if (digits.length != 10) {
                    return 'Phone must be exactly 10 digits (${digits.length} entered)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Address (optional)
              _fieldLabel('HOME ADDRESS / VILLAGE (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: _inputDeco(
                  'e.g. 12 Green Acres, Kovai',
                  Icons.location_on_outlined,
                ),
              ),
              const SizedBox(height: 28),

              // ── Face Registration (mandatory) ─────────────────────────────
              _buildFaceRegisterCard(),
              const SizedBox(height: 24),

              // ── Created by info ───────────────────────────────────────────
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

              // ── Submit ────────────────────────────────────────────────────
              Consumer<EmployeeProvider>(
                builder: (_, provider, __) => GradientButton(
                  label: _isEditing ? 'Update Worker' : 'Add Worker',
                  icon: _isEditing
                      ? Icons.check_rounded
                      : Icons.person_add_rounded,
                  isLoading: provider.isLoading,
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

  // ── Face register card ────────────────────────────────────────────────────────
  Widget _buildFaceRegisterCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Face Registration *', Icons.face_rounded),
          const SizedBox(height: 4),
          const Text(
            'Required — the employee will be identified by face at check-in/out.',
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
                        'Face registered! This worker will be auto-detected at check-in.',
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
                        : 'No face registered. Add a front-facing photo then tap Register Face.',
                  ),
          ),
          const SizedBox(height: 12),

          // Register button
          GestureDetector(
            onTap: _isScanningFace ? null : _captureFace,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
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
              child: _isScanningFace
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _faceRegistered
                              ? Icons.refresh_rounded
                              : Icons.face_rounded,
                          color: _faceRegistered
                              ? AppTheme.successColor
                              : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _faceRegistered
                              ? 'Re-register Face'
                              : 'Register Face from Photo',
                          style: TextStyle(
                            color: _faceRegistered
                                ? AppTheme.successColor
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner({
    required Key key,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
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
  }

  Widget _sectionTitle(String title, IconData icon) => Row(
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
      Text(title, style: AppTextStyles.heading3),
    ],
  );

  Widget _fieldLabel(String text) => Text(
    text,
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
*/