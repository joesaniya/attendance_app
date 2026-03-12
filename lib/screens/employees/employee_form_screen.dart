// lib/screens/employees/employee_form_screen.dart

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

  // Farming / Gardening work areas
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

  // Farming / Gardening roles
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

    if (_isEditing) {
      final emp = widget.employee!;
      _nameController.text = emp.name;
      _emailController.text = emp.email;
      _phoneController.text = emp.phone;
      _departmentController.text = emp.department;
      _positionController.text = emp.position;
      _addressController.text = emp.address;
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
                child: const Icon(Icons.camera_alt_rounded,
                    color: AppTheme.primaryColor),
              ),
              title: const Text('Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image =
                    await picker.pickImage(source: ImageSource.camera);
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
                child: const Icon(Icons.photo_library_rounded,
                    color: AppTheme.accentColor),
              ),
              title: const Text('Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image =
                    await picker.pickImage(source: ImageSource.gallery);
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
              content: Text('Worker record updated successfully!'),
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
      );

      if (mounted) {
        if (employee != null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${employee.name} added to the team! Code: ${employee.employeeCode}'),
              backgroundColor: AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(employeeProvider.error ?? 'Failed to add worker'),
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
                            : (_isEditing && widget.employee?.photoUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(55),
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
                            border: Border.all(color: Colors.white, width: 2),
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
              ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.8, 0.8)),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Photo used for attendance & identification',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),

              // Personal Info Section
              _sectionTitle('Personal Information', Icons.person_outline_rounded),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Full Name',
                hint: 'e.g. Ravi Kumar',
                controller: _nameController,
                prefixIcon: Icons.person_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email Address',
                hint: 'ravi@farm.com',
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
                hint: '+91 98765 43210',
                controller: _phoneController,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Phone is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Home Address / Village',
                hint: 'e.g. 12 Green Acres, Kovai',
                controller: _addressController,
                prefixIcon: Icons.location_on_outlined,
                maxLines: 2,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Address is required' : null,
              ),

              const SizedBox(height: 28),
              _sectionTitle('Farm Assignment', Icons.agriculture_rounded),
              const SizedBox(height: 16),

              // Work Area Dropdown (replaces "Department")
              _dropdownField(
                label: 'WORK AREA',
                hint: 'Select work area',
                icon: Icons.park_outlined,
                items: _workAreas,
                currentValue: _departmentController.text.isNotEmpty &&
                        _workAreas.contains(_departmentController.text)
                    ? _departmentController.text
                    : null,
                onChanged: (value) {
                  if (value != null) _departmentController.text = value;
                },
                validator: (v) =>
                    v == null || v.isEmpty ? 'Work area is required' : null,
              ),

              const SizedBox(height: 16),

              // Role Dropdown (replaces free-text "Position")
              _dropdownField(
                label: 'ROLE',
                hint: 'Select worker role',
                icon: Icons.badge_outlined,
                items: _roles,
                currentValue: _positionController.text.isNotEmpty &&
                        _roles.contains(_positionController.text)
                    ? _positionController.text
                    : null,
                onChanged: (value) {
                  if (value != null) _positionController.text = value;
                },
                validator: (v) =>
                    v == null || v.isEmpty ? 'Role is required' : null,
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
                        child: const Icon(Icons.agriculture_rounded,
                            color: AppTheme.primaryColor, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
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
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              Consumer<EmployeeProvider>(
                builder: (context, provider, _) => GradientButton(
                  label: _isEditing ? 'Update Worker' : 'Add Worker',
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

  Widget _sectionTitle(String title, IconData icon) {
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
        Icon(icon, size: 16, color: AppTheme.primaryColor),
        const SizedBox(width: 6),
        Text(title, style: AppTextStyles.heading3),
      ],
    );
  }

  Widget _dropdownField({
    required String label,
    required String hint,
    required IconData icon,
    required List<String> items,
    required String? currentValue,
    required ValueChanged<String?> onChanged,
    required FormFieldValidator<String> validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: currentValue,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
          isExpanded: true,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }
}
