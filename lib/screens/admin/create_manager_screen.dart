// lib/screens/admin/create_manager_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../data/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/app_widgets.dart';

class CreateManagerScreen extends StatefulWidget {
  const CreateManagerScreen({super.key});

  @override
  State<CreateManagerScreen> createState() => _CreateManagerScreenState();
}

class _CreateManagerScreenState extends State<CreateManagerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createManager() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final authService = AuthService();

      await authService.createAdminUser(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        role: AppConstants.roleManager,
        createdBy: auth.currentUser!.id,
        createdByRole: AppConstants.roleSuperAdmin,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Manager account created for ${_nameController.text}'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().contains('email-already-in-use')
            ? 'An account with this email already exists'
            : 'Failed to create manager account';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Create Manager Account'),
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.manage_accounts_rounded,
                      color: AppTheme.accentColor, size: 40),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Manager Account',
                  style: AppTextStyles.heading2,
                ),
              ),
               Center(
                child: Text(
                  'Create a new manager account with full employee management access',
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              AppTextField(
                label: 'Full Name',
                hint: 'John Manager',
                controller: _nameController,
                prefixIcon: Icons.person_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email Address',
                hint: 'manager@company.com',
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
                label: 'Password',
                hint: 'Min. 6 characters',
                controller: _passwordController,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixWidget: GestureDetector(
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'Min. 6 characters';
                  return null;
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.errorColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppTheme.errorColor, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: AppTheme.errorColor, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              GradientButton(
                label: 'Create Manager Account',
                icon: Icons.person_add_rounded,
                gradient: AppTheme.accentGradient,
                isLoading: _isLoading,
                onTap: _createManager,
              ),

              const SizedBox(height: 16),

              GlassCard(
                padding: const EdgeInsets.all(14),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppTheme.primaryColor, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Manager will have access to employee management and attendance records.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.4,
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
}
