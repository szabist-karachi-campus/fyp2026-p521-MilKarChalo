import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api.dart';
import '../../../router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _passC  = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.85, 1.15);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(28, w * 0.06));
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final email = _emailC.text.trim().toLowerCase();
      final resp = await Api.login({
        'email': email,
        'password': _passC.text,
      });

      // The login endpoint only sends the OTP. The role is returned as a hint.
      final role = resp['role'] as String?;

      // Persist the email and role hint for the OTP page.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);
      if (role != null) {
        await prefs.setString('user_role', role);
      }

      Navigator.pushNamed(
        context,
        AppRoutes.verifyLoginOtp,
        arguments: {
          'email': email,
          'role': role, // Pass role hint to OTP page
          'purpose': 'login',
        },
      );
    } on ApiException catch (e) {
      debugPrint('❌ Login failed: ${e.message}, data: ${e.data}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(BuildContext c, String label, {Widget? suffix}) {
    final r = BorderRadius.circular(12 * _scale(c));
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: _gap(c, 16), vertical: _gap(c, 14)),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = _hPad(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, _gap(context, 18), pad, _gap(context, 18)),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailC,
                keyboardType: TextInputType.emailAddress,
                decoration: _dec(context, 'Email'),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Email is required';
                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s);
                  return ok ? null : 'Enter a valid email';
                },
              ),
              SizedBox(height: _gap(context, 12)),
              TextFormField(
                controller: _passC,
                obscureText: _obscure,
                decoration: _dec(
                  context, 'Password',
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
              ),
              SizedBox(height: _gap(context, 12)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.forgotPassword),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: Color(0xFF0A2540), // custom navy color
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(height: _gap(context, 16)),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Continue'),
                ),
              ),
              SizedBox(height: _gap(context, 14)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.signupRole),
                    child: Text('Sign up', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF0A2540))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
