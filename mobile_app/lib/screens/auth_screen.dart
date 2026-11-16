import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

enum AuthMode { login, register, forgot }

class AuthScreen extends StatefulWidget {
  final ValueChanged<AuthUser> onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _registerOtpController = TextEditingController();
  final TextEditingController _resetCodeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  AuthMode _mode = AuthMode.login;
  String _selectedRole = 'Media Analyst';
  bool _obscurePassword = true;
  bool _loading = false;
  bool _registerOtpSent = false;
  bool _resetCodeSent = false;
  String? _registerOtpToken;
  String? _serverResetToken;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _registerOtpController.dispose();
    _resetCodeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@') || password.length < 6) {
      setState(() => _error = 'Please enter a valid email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final user = await ApiService.login(email: email, password: password);
      widget.onAuthenticated(user);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSendRegisterOtp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (name.length < 2) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final token = await ApiService.sendRegisterOtp(name: name, email: email);
      if (!mounted) return;
      _startResendCooldown();
      setState(() {
        _registerOtpSent = true;
        _registerOtpToken = token;
        _successMessage =
            'Real-time 6-digit OTP sent to $email. Please check your inbox (or Spam).';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final otp = _registerOtpController.text.trim();

    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP sent to your email.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final user = await ApiService.register(
        name: name,
        email: email,
        password: password,
        otp: otp,
        otpToken: _registerOtpToken ?? '',
        role: _selectedRole,
      );
      widget.onAuthenticated(user);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleForgotRequest() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your registered email first.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final resetToken = await ApiService.forgotPassword(email: email);
      if (!mounted) return;
      _startResendCooldown();
      setState(() {
        _resetCodeSent = true;
        _serverResetToken = resetToken;
        _successMessage =
            'Real-time 6-digit OTP sent to $email. Check your inbox and enter it below.';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final code = _resetCodeController.text.trim();
    final newPass = _newPasswordController.text;

    if (code.length != 6 || newPass.length < 6) {
      setState(() => _error =
          'Enter the 6-digit email OTP and a new password (min 6 chars).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiService.resetPassword(
        email: email,
        code: code,
        newPassword: newPass,
        resetToken: _serverResetToken ?? '',
      );

      if (!mounted) return;
      setState(() {
        _mode = AuthMode.login;
        _resetCodeSent = false;
        _resetCodeController.clear();
        _newPasswordController.clear();
        _passwordController.text = newPass;
        _successMessage = 'Password updated! Sign in with your new password.';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 880;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 940 : 460),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: _buildBrandPanel()),
                          Expanded(flex: 6, child: _buildFormPanel()),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildBrandPanel(compact: true),
                        _buildFormPanel(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandPanel({bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 22 : 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'VeriLens AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Multimodal Fake Image & Voice Deepfake Forensics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 18 : 24,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Inspect photos, AI-generated portraits, cloned voices, and forwarded WhatsApp/Instagram posts in seconds.',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 28),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FeatureLine(
                    icon: Icons.image_search,
                    text: 'EXIF, Compression & AI Pixel Forensics'),
                SizedBox(height: 10),
                _FeatureLine(
                    icon: Icons.graphic_eq,
                    text: 'AI Voice Clone & Human Speech Verification'),
                SizedBox(height: 10),
                _FeatureLine(
                    icon: Icons.mark_email_read_outlined,
                    text: 'Real-Time Email OTP Security & Cloud Sync'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<AuthMode>(
            segments: const [
              ButtonSegment(value: AuthMode.login, label: Text('Login', maxLines: 1, softWrap: false)),
              ButtonSegment(value: AuthMode.register, label: Text('Register', maxLines: 1, softWrap: false)),
              ButtonSegment(value: AuthMode.forgot, label: Text('Forgot', maxLines: 1, softWrap: false)),
            ],
            selected: {_mode},
            onSelectionChanged: (val) => setState(() {
              _mode = val.first;
              _error = null;
              _successMessage = null;
            }),
          ),
          const SizedBox(height: 20),
          if (_mode == AuthMode.register) ...[
            TextField(
              controller: _nameController,
              decoration: _inputDeco('Full Name', Icons.person_outline),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: _inputDeco('Role', Icons.badge_outlined),
              items: const [
                DropdownMenuItem(
                    value: 'Media Analyst', child: Text('Media Analyst')),
                DropdownMenuItem(
                    value: 'Journalist', child: Text('Journalist')),
                DropdownMenuItem(
                    value: 'Content Creator', child: Text('Content Creator')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDeco('Email Address', Icons.email_outlined),
          ),
          if (_mode != AuthMode.forgot) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _inputDeco('Password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          ],
          if (_mode == AuthMode.register && _registerOtpSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _registerOtpController,
              keyboardType: TextInputType.number,
              decoration:
                  _inputDeco('6-Digit Email OTP', Icons.mark_email_read_outlined),
            ),
          ],
          if (_mode == AuthMode.forgot && _resetCodeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _resetCodeController,
              keyboardType: TextInputType.number,
              decoration: _inputDeco('6-Digit Email OTP', Icons.pin_outlined),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: _obscurePassword,
              decoration: _inputDeco('New Password (min 6 chars)',
                  Icons.lock_reset_outlined),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
              ),
            ),
          ],
          if (_successMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Text(
                _successMessage!,
                style: const TextStyle(color: Color(0xFF15803D), fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _loading
                ? null
                : () {
                    if (_mode == AuthMode.login) {
                      _handleLogin();
                    } else if (_mode == AuthMode.register) {
                      if (_registerOtpSent) {
                        _handleRegister();
                      } else {
                        _handleSendRegisterOtp();
                      }
                    } else if (!_resetCodeSent) {
                      _handleForgotRequest();
                    } else {
                      _handleResetPassword();
                    }
                  },
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _mode == AuthMode.login
                        ? 'Sign In to VeriLens'
                        : _mode == AuthMode.register
                            ? (_registerOtpSent
                                ? 'Verify OTP & Create Account'
                                : 'Send Real-Time Email OTP')
                            : (_resetCodeSent
                                ? 'Verify OTP & Update Password'
                                : 'Send Real-Time Reset OTP'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
          if ((_mode == AuthMode.register && _registerOtpSent) ||
              (_mode == AuthMode.forgot && _resetCodeSent)) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading || _resendSeconds > 0
                  ? null
                  : () {
                      if (_mode == AuthMode.register) {
                        _handleSendRegisterOtp();
                      } else {
                        _handleForgotRequest();
                      }
                    },
              child: Text(
                _resendSeconds > 0
                    ? 'Resend OTP in ${_resendSeconds}s'
                    : 'Resend 6-Digit Email OTP',
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1D4ED8), width: 1.6),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF93C5FD), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
          ),
        ),
      ],
    );
  }
}