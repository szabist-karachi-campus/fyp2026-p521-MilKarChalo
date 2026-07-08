import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/api.dart';
import '../../../router.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
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
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      // Print email for debugging
      print('Email to send OTP: ${_emailC.text.trim()}');

      await Api.sendOtp({'email': _emailC.text.trim().toLowerCase(), 'purpose': 'reset'});

      print('Navigating to ResetPasswordPage with email: ${_emailC}');
      Navigator.pushNamed(
        context,
        AppRoutes.resetPassword,
        arguments: {'email': _emailC.text.trim().toLowerCase()},
      );
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(BuildContext c, String label) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = _hPad(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
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

                  final regex = RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                  if (!regex.hasMatch(s)) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              SizedBox(height: _gap(context, 16)),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _loading ? null : _send,
                  child: _loading
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'Send',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
