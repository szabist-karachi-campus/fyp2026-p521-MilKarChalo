import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../router.dart';
import 'package:frontend/core/api.dart';

class SignupFormPage extends StatefulWidget {
  const SignupFormPage({super.key, required this.role});

  /// 'driver' | 'passenger'
  final String role;

  @override
  State<SignupFormPage> createState() => _SignupFormPageState();
}

class _SignupFormPageState extends State<SignupFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameC  = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  final _passC  = TextEditingController();
  final _cityC  = TextEditingController();

  String? _gender;
  bool _obscure = true;
  bool _loading = false;

  static const _navy = Color(0xFF0A2540);

  // ---------- Responsive helpers ----------
  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.82, 1.18);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(28, w * 0.06));
  }
  double _buttonHeight(BuildContext c) => (_gap(c, 54)).clamp(46, 64);

  InputDecoration _dec(BuildContext c, {String? label, String? hint, Widget? suffix}) {
    final r = BorderRadius.circular(12 * _scale(c));
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: _gap(c, 18),
        vertical: _gap(c, 14),
      ),
      suffixIcon: suffix,
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final resp = await Api.signup({
        'role': widget.role, // 'driver' | 'passenger'
        'name': _nameC.text.trim(),
        'email': _emailC.text.trim().toLowerCase(),
        'phone': _phoneC.text.trim(),
        'gender': _gender!,
        'city': _cityC.text.trim(),
        'password': _passC.text,
      });

      Navigator.pushNamed(
        context,
        AppRoutes.verifySignupOtp,
        arguments: {
          'email': _emailC.text.trim(),
          'role': widget.role,
        },
      );
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  @override
  void dispose() {
    _nameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    _passC.dispose();
    _cityC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: Colors.black87,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: false,
        title: Text(
          'Create an account (${widget.role})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final pad = _hPad(context);
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(pad, _gap(context, 16), pad, _gap(context, 16)),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - bottomInset),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Name
                        Text('Name', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),
                        TextFormField(
                          controller: _nameC,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, label: 'Name', hint: 'Enter your full name'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                        ),

                        SizedBox(height: _gap(context, 14)),

                        // Email
                        Text('Email', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),
                        TextFormField(
                          controller: _emailC,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, label: 'Email', hint: 'example@example.com'),
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return 'Email is required';
                            final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(val);
                            return ok ? null : 'Enter a valid email';
                          },
                        ),

                        SizedBox(height: _gap(context, 14)),

                        // Phone
                        Text('Phone No', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),
                        TextFormField(
                          controller: _phoneC,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, label: 'Phone No', hint: 'Enter your number'),
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return 'Phone is required';
                            if (val.length < 7) return 'Enter a valid phone';
                            return null;
                          },
                        ),

                        SizedBox(height: _gap(context, 14)),

                        // Password
                        Text('Password', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),
                        TextFormField(
                          controller: _passC,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(
                            context,
                            label: 'Password',
                            hint: 'Enter password',
                            suffix: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Password is required';
                            if (v.length < 6) return 'At least 6 characters';
                            return null;
                          },
                        ),

                        SizedBox(height: _gap(context, 14)),

                        // Gender
                        Text('Gender', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),
                        DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: _dec(context, label: 'Gender', hint: 'Select gender'),
                          items: const [
                            DropdownMenuItem(value: 'male',   child: Text('Male')),
                            DropdownMenuItem(value: 'female', child: Text('Female')),
                            DropdownMenuItem(value: 'other',  child: Text('Other')),
                          ],
                          onChanged: (v) => setState(() => _gender = v),
                          validator: (v) => v == null ? 'Select gender' : null,
                        ),

                        SizedBox(height: _gap(context, 14)),

                        // City
                        Text('City', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),
                        TextFormField(
                          controller: _cityC,
                          textInputAction: TextInputAction.done,
                          decoration: _dec(context, label: 'City', hint: 'Enter your city'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'City is required' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),

                        SizedBox(height: _gap(context, 20)),

                        // Create account button
                        SizedBox(
                          height: _buttonHeight(context),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _navy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(_gap(context, 12)),
                              ),
                            ),
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                                : const Text('Create an account'),
                          ),
                        ),

                        const Spacer(),

                        // Footer
                        Padding(
                          padding: EdgeInsets.only(top: _gap(context, 24), bottom: _gap(context, 12)),
                          child: Center(
                            child: Text.rich(
                              TextSpan(
                                text: 'By using MilKar Chalo, you agree to the ',
                                children: const [
                                  TextSpan(
                                    text: 'Terms',
                                    style: TextStyle(decoration: TextDecoration.underline),
                                  ),
                                  TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: TextStyle(decoration: TextDecoration.underline),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.black54,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
