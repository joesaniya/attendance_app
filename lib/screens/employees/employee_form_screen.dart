// lib/screens/employees/employee_form_screen.dart

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

  // work-area & role driven by dropdowns
  String? _selectedWorkArea;
  String? _selectedRole;

  File? _selectedPhoto;
  bool _photoError = false; // shown when user tries to save without photo
  bool _isEditing = false;

  // face
  String? _capturedFaceDescriptor;
  bool _isScanningFace = false;
  bool _faceRegistered = false;
  final FaceDetectionService _faceService = FaceDetectionService();

  // ── Farming / gardening work areas ──────────────────────────────────────────
  static const List<String> _workAreas = [
    'Field Crops',
    'Greenhouse',
    'Nursery',
    'Orchard',
    'Vegetable Garden',
    'Irrigation',
    'Livestock',
    'Composting',
    'Harvest & Packing',
    'Equipment & Maintenance',
    'Landscaping',
    'Soil Management',
  ];

  static const List<String> _roles = [
    'Field Worker',
    'Greenhouse Technician',
    'Nursery Assistant',
    'Irrigation Operator',
    'Harvest Hand',
    'Equipment Operator',
    'Soil Analyst',
    'Pest Control Worker',
    'Livestock Caretaker',
    'Farm Supervisor',
    'Garden Coordinator',
    'General Labourer',
  ];

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

      _selectedWorkArea = _workAreas.contains(e.department)
          ? e.department
          : null;
      _selectedRole = _roles.contains(e.position) ? e.position : null;

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
        // reset face if photo changed
        _faceRegistered = false;
        _capturedFaceDescriptor = null;
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
    // Photo mandatory check
    final hasPhoto =
        _selectedPhoto != null ||
        (_isEditing && widget.employee?.photoUrl != null);
    if (!hasPhoto) {
      setState(() => _photoError = true);
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
        'department': _selectedWorkArea ?? '',
        'position': _selectedRole ?? '',
        'address': _addressController.text.trim(),
        if (_capturedFaceDescriptor != null)
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
      final employee = await provider.createEmployee(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        department: _selectedWorkArea ?? '',
        position: _selectedRole ?? '',
        address: _addressController.text.trim(),
        photoFile: _selectedPhoto,
        createdBy: auth.currentUser!.id,
        createdByRole: auth.currentUser!.role,
        createdByName: auth.currentUser!.name,
        faceDescriptor: _capturedFaceDescriptor,
      );

      if (!mounted) return;
      if (employee != null) {
        // Stream auto-updates list — just pop back
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

              // Name
              _fieldLabel('FULL NAME'),
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

              // Email
              _fieldLabel('EMAIL ADDRESS'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco('ravi@farm.com', Icons.email_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@') || !v.contains('.'))
                    return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone — exactly 10 digits
              _fieldLabel('PHONE NUMBER'),
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
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) return 'Phone number is required';
                  if (digits.length < 10)
                    return 'Phone number must be exactly 10 digits (${digits.length} entered)';
                  if (digits.length > 10)
                    return 'Phone number must be exactly 10 digits (${digits.length} entered)';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Address
              _fieldLabel('HOME ADDRESS / VILLAGE'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: _inputDeco(
                  'e.g. 12 Green Acres, Kovai',
                  Icons.location_on_outlined,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Address is required'
                    : null,
              ),
              const SizedBox(height: 28),

              // ── Farm Assignment ───────────────────────────────────────────
              _sectionTitle('Farm Assignment', Icons.agriculture_rounded),
              const SizedBox(height: 16),

              _fieldLabel('WORK AREA'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedWorkArea,
                decoration: _inputDeco('Select work area', Icons.park_outlined),
                isExpanded: true,
                items: _workAreas
                    .map(
                      (w) => DropdownMenuItem(
                        value: w,
                        child: Text(w, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedWorkArea = v),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Work area is required' : null,
              ),
              const SizedBox(height: 16),

              _fieldLabel('ROLE'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: _inputDeco(
                  'Select worker role',
                  Icons.badge_outlined,
                ),
                isExpanded: true,
                items: _roles
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedRole = v),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Role is required' : null,
              ),
              const SizedBox(height: 28),

              // ── Face Registration ─────────────────────────────────────────
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
          _sectionTitle('Face Registration', Icons.face_rounded),
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
                    icon: Icons.info_outline_rounded,
                    color: AppTheme.warningColor,
                    text:
                        'No face registered. Add a front-facing photo then tap Register Face.',
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
                    : null,
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

  // ── Helpers ───────────────────────────────────────────────────────────────────
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


/*

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../data/models/employee_model.dart';
import '../../widgets/app_widgets.dart';
import '../../data/services/face_detection_service.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class EmployeeFormScreen extends StatefulWidget {
  final EmployeeModel? employee; // null = create, non-null = edit

  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _departmentController = TextEditingController();
  final _positionController = TextEditingController();
  final _addressController = TextEditingController();

  File? _selectedPhoto;
  bool _isEditing = false;
  String? _capturedFaceDescriptor;
  bool _isScanningFace = false;
  bool _faceRegistered = false;
  final FaceDetectionService _faceService = FaceDetectionService();

  final List<String> _departments = [
    'Engineering',
    'Design',
    'Marketing',
    'Sales',
    'HR',
    'Finance',
    'Operations',
    'Legal',
    'Customer Support',
    'Management',
  ];

  @override
  void initState() {
    super.initState();
    _isEditing = widget.employee != null;

    _faceService.initialize();
    if (_isEditing) {
      final emp = widget.employee!;
      _nameController.text = emp.name;
      _emailController.text = emp.email;
      _phoneController.text = emp.phone;
      _departmentController.text = emp.department;
      _positionController.text = emp.position;
      _addressController.text = emp.address;
      _capturedFaceDescriptor = emp.faceDescriptor;
      _faceRegistered =
          emp.faceDescriptor != null && emp.faceDescriptor!.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _positionController.dispose();
    _addressController.dispose();
    _faceService.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.primaryColor,
                ),
              ),
              title: const Text(
                'Take Photo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image = await picker.pickImage(
                  source: ImageSource.camera,
                );
                if (image != null) {
                  setState(() => _selectedPhoto = File(image.path));
                }
              },
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: AppTheme.accentColor,
                ),
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (image != null) {
                  setState(() => _selectedPhoto = File(image.path));
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _captureFace() async {
    if (_selectedPhoto == null &&
        (!_isEditing || widget.employee?.photoUrl == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a photo first before registering face'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isScanningFace = true);

    try {
      File? imageFile;
      if (_selectedPhoto != null) {
        imageFile = _selectedPhoto;
      } else if (_isEditing && widget.employee?.photoUrl != null) {
        // Download the existing photo to detect from
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please take a new photo to register face'),
            backgroundColor: AppTheme.infoColor,
          ),
        );
        setState(() => _isScanningFace = false);
        return;
      }

      if (imageFile == null) {
        setState(() => _isScanningFace = false);
        return;
      }

      final faces = await _faceService.detectFacesFromFile(imageFile);

      if (faces.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No face detected in photo. Please use a clear front-facing photo.',
              ),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        setState(() => _isScanningFace = false);
        return;
      }

      if (faces.length > 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Multiple faces detected. Please use a photo with only one person.',
              ),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
        setState(() => _isScanningFace = false);
        return;
      }

      final descriptor = _faceService.buildFaceDescriptor(faces.first);
      if (descriptor == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not extract face features. Try a clearer front-facing photo.',
              ),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        setState(() => _isScanningFace = false);
        return;
      }

      setState(() {
        _capturedFaceDescriptor = descriptor;
        _faceRegistered = true;
        _isScanningFace = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Face registered successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      setState(() => _isScanningFace = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Face detection error: \$e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final employeeProvider = context.read<EmployeeProvider>();

    if (_isEditing) {
      final success = await employeeProvider.updateEmployee(
        employeeId: widget.employee!.id,
        data: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'department': _departmentController.text.trim(),
          'position': _positionController.text.trim(),
          'address': _addressController.text.trim(),
        },
        newPhotoFile: _selectedPhoto,
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee updated successfully!'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(employeeProvider.error ?? 'Update failed'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } else {
      final employee = await employeeProvider.createEmployee(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        department: _departmentController.text.trim(),
        position: _positionController.text.trim(),
        address: _addressController.text.trim(),
        photoFile: _selectedPhoto,
        createdBy: auth.currentUser!.id,
        createdByRole: auth.currentUser!.role,
        createdByName: auth.currentUser!.name,
        faceDescriptor: _capturedFaceDescriptor,
      );

      if (mounted) {
        if (employee != null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${employee.name} added successfully! Code: ${employee.employeeCode}',
              ),
              backgroundColor: AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(employeeProvider.error ?? 'Failed to add employee'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Employee' : 'Add Employee'),
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
              // Photo Picker
              Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withOpacity(0.3),
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
                                          borderRadius: BorderRadius.circular(
                                            55,
                                          ),
                                          child: Image.network(
                                            widget.employee!.photoUrl!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_rounded,
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
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'This photo will be used for face detection',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),

              // Personal Info Section
              _sectionTitle('Personal Information'),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Full Name',
                hint: 'John Doe',
                controller: _nameController,
                prefixIcon: Icons.person_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email Address',
                hint: 'john@example.com',
                controller: _emailController,
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Phone Number',
                hint: '+1 234 567 8900',
                controller: _phoneController,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Phone is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Address',
                hint: '123 Main St, City, Country',
                controller: _addressController,
                prefixIcon: Icons.location_on_outlined,
                maxLines: 2,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Address is required' : null,
              ),

              const SizedBox(height: 28),
              _sectionTitle('Work Information'),
              const SizedBox(height: 16),

              // Department Dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEPARTMENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _departmentController.text.isNotEmpty
                        ? _departmentController.text
                        : null,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.business_outlined,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppTheme.borderColor,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppTheme.borderColor,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      hintText: 'Select department',
                      hintStyle: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    items: _departments
                        .map(
                          (dept) =>
                              DropdownMenuItem(value: dept, child: Text(dept)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _departmentController.text = value;
                    },
                    validator: (v) => v == null || v.isEmpty
                        ? 'Department is required'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Position/Job Title',
                hint: 'Software Engineer',
                controller: _positionController,
                prefixIcon: Icons.work_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Position is required' : null,
              ),

              const SizedBox(height: 32),

              // Created by info
              Consumer<AuthProvider>(
                builder: (context, auth, _) => GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.primaryColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Record created by',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            Text(
                              '${auth.currentUser?.name ?? ''} (${auth.currentUser?.role == 'super_admin' ? 'Super Admin' : 'Manager'})',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Face Registration
              _buildFaceRegisterCard(),
              const SizedBox(height: 16),

              // Submit Button
              Consumer<EmployeeProvider>(
                builder: (context, provider, _) => GradientButton(
                  label: _isEditing ? 'Update Employee' : 'Add Employee',
                  icon: _isEditing
                      ? Icons.check_rounded
                      : Icons.person_add_rounded,
                  isLoading: provider.isLoading,
                  onTap: _saveEmployee,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceRegisterCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const Icon(
                Icons.face_rounded,
                size: 16,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 6),
              const Text('Face Registration', style: AppTextStyles.heading3),
            ],
          ),
          const SizedBox(height: 12),
          if (_faceRegistered)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.successColor.withOpacity(0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: AppTheme.successColor,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Face registered! This employee will be auto-detected at check-in.',
                      style: TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.warningColor.withOpacity(0.3),
                ),
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
                      'No face registered. Add a clear front-facing photo then tap Register Face.',
                      style: TextStyle(
                        color: AppTheme.warningColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _isScanningFace ? null : _captureFace,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                gradient: _faceRegistered ? null : AppTheme.primaryGradient,
                color: _faceRegistered
                    ? AppTheme.successColor.withOpacity(0.1)
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: _faceRegistered
                    ? Border.all(color: AppTheme.successColor.withOpacity(0.4))
                    : null,
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

  Widget _sectionTitle(String title) {
    return Row(
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
        Text(title, style: AppTextStyles.heading3),
      ],
    );
  }
}
*/