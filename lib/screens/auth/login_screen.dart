import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_widgets.dart';
import 'dart:developer';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _showAdminLogin = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.signIn(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );
    log(
      'Login attempt for ${_emailController.text.trim()} - Success: $success',
    );
    if (!success && mounted) {
      _showErrorSnackBar(auth.errorMessage ?? 'An error occurred');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Login Failed',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.darkGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo Area
                  Center(
                    child:
                        Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: AppTheme.accentGradient,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentColor.withOpacity(
                                      0.3,
                                    ),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.fingerprint_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            )
                            .animate()
                            .fadeIn(duration: 600.ms)
                            .slideY(begin: 0.2, end: 0),
                  ),
                  const SizedBox(height: 24),
                  Text(
                        'AttendX',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1.2,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 600.ms)
                      .scale(begin: const Offset(0.95, 0.95)),
                  const SizedBox(height: 8),
                  Text(
                    'Smart Attendance Management',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

                  const SizedBox(height: 32),

                  if (!_showAdminLogin) ...[
                    // Admin Login Toggle Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showAdminLogin = true),
                        icon: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 18),
                        label: Text(
                          'Admin Login',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.white.withOpacity(0.1),
                        ),
                      ).animate().fadeIn(delay: 300.ms, duration: 600.ms),
                    ),
                    const SizedBox(height: 16),

                    // Attendance Section (Main View)
                    GlassCard(
                      color: AppTheme.surfaceLight,
                      padding: const EdgeInsets.all(32),
                      borderRadius: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 48,
                              color: AppTheme.accentColor,
                            ),
                          ).animate().scale(delay: 400.ms, duration: 400.ms),
                          const SizedBox(height: 24),
                          Text(
                            'Employee Attendance',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(delay: 500.ms, duration: 600.ms),
                          const SizedBox(height: 8),
                          Text(
                            'Mark your daily attendance',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(delay: 600.ms, duration: 600.ms),
                          const SizedBox(height: 48),

                          // Mark Attendance Button
                          GradientButton(
                            label: 'Mark Attendance',
                            icon: Icons.qr_code_scanner_rounded,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/employee_attendance',
                            ),
                          ).animate().fadeIn(delay: 700.ms, duration: 600.ms).slideY(begin: 0.1, end: 0),
                        ],
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.1, end: 0),
                  ] else ...[
                    // Back to Attendance
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showAdminLogin = false),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                        label: Text(
                          'Back to Attendance',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.white.withOpacity(0.1),
                        ),
                      ).animate().fadeIn(duration: 400.ms),
                    ),
                    const SizedBox(height: 16),

                    // Login Form Card
                    GlassCard(
                      color: AppTheme.surfaceLight,
                      padding: const EdgeInsets.all(32),
                      borderRadius: 24,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Login',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ).animate().fadeIn(
                              delay: 100.ms,
                              duration: 600.ms,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to your account',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ).animate().fadeIn(
                              delay: 200.ms,
                              duration: 600.ms,
                            ),
                            const SizedBox(height: 32),

                            // Email Field
                            AppTextField(
                              label: 'Email Address',
                              hint: 'Enter your email',
                              controller: _emailController,
                              prefixIcon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty)
                                  return 'Please enter your email';
                                if (!value.contains('@'))
                                  return 'Please enter a valid email';
                                return null;
                              },
                            ).animate().fadeIn(
                              delay: 300.ms,
                              duration: 600.ms,
                            ),
                            const SizedBox(height: 24),

                            // Password Field
                            AppTextField(
                              label: 'Password',
                              hint: '••••••••',
                              controller: _passwordController,
                              prefixIcon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              suffixWidget: GestureDetector(
                                onTap: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty)
                                  return 'Please enter your password';
                                return null;
                              },
                            ).animate().fadeIn(
                              delay: 400.ms,
                              duration: 600.ms,
                            ),
                            const SizedBox(height: 32),

                            // Login Button
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) => GradientButton(
                                label: 'Sign In',
                                icon: Icons.login_rounded,
                                isLoading: auth.isLoading,
                                onTap: _handleLogin,
                              ),
                            ).animate().fadeIn(
                              delay: 500.ms,
                              duration: 600.ms,
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
