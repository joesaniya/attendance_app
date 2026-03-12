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
      );

      if (mounted) {
        if (employee != null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${employee.name} added successfully! Code: ${employee.employeeCode}'),
              backgroundColor: AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(employeeProvider.error ?? 'Failed to add employee'),
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
                  'This photo will be used for face detection',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
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
                      prefixIcon: const Icon(Icons.business_outlined,
                          size: 18, color: AppTheme.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppTheme.borderColor),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      hintText: 'Select department',
                      hintStyle: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 14),
                    ),
                    items: _departments
                        .map((dept) => DropdownMenuItem(
                              value: dept,
                              child: Text(dept),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _departmentController.text = value;
                    },
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Department is required' : null,
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
                        child: const Icon(Icons.info_outline_rounded,
                            color: AppTheme.primaryColor, size: 18),
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
