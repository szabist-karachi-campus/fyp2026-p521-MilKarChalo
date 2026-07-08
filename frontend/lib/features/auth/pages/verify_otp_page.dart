import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../router.dart';

class VerifyOtpPage extends StatefulWidget {
  const VerifyOtpPage({
    super.key,
    required this.purpose,        // 'login' | 'signup' | 'reset'
    required this.email,          // target email
    this.role,                    // optional hint from previous page
    this.nextRoute,               // optional explicit override
  });

  final String purpose;
  final String email;
  final String? role;
  final String? nextRoute;

  @override
  State<VerifyOtpPage> createState() => _VerifyOtpPageState();
}

class _VerifyOtpPageState extends State<VerifyOtpPage> {
  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  int _seconds = 120;
  Timer? _timer;

  static const _navy = Color(0xFF0A2540);

  // ---------- Responsive helpers ----------
  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.82, 1.18);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(28, w * 0.06));
  }
  double _buttonHeight(BuildContext c) => (_gap(c, 54)).clamp(46, 64);

  @override
  void initState() {
    super.initState();
    debugPrint('🔍 VerifyOtpPage opened - purpose: ${widget.purpose}, email: ${widget.email}');
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final n in _otpNodes) {
      n.dispose();
    }
    super.dispose();
  }

  // ---------- Timer ----------
  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 120);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) {
        t.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  String get _otp => _otpCtrls.map((c) => c.text).join();

  // ---------- Verify + Navigate ----------
  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(_otp)) {
      _toast('Enter the 6-digit code');
      return;
    }

    setState(() => _loading = true);

    final purpose = widget.purpose.toLowerCase();
    try {
      final resp = await Api.verifyOtp({
        'email': widget.email,
        'purpose': purpose,
        'code': _otp,
      });

      final prefs = await SharedPreferences.getInstance();

      if (resp['token'] != null) {
        final token = resp['token'] as String;
        Api.setToken(token);
        await prefs.setString('token', token);
      }

      final role = (resp['role'] as String?) ?? widget.role ?? 'passenger';
      final status = (resp['next'] as String?) ?? (resp['onboarding_status'] as String?) ?? 'ready';

      final user = resp['user'] as Map?;
      final driver = resp['driver'] as Map?;
      final passenger = resp['passenger'] as Map?;
      final vehicle = resp['vehicle'] as Map?;

      final nameToSave = (user?['name'] as String?) ?? (resp['name'] as String?) ?? '';
      final avatarToSave = (user?['image_url'] as String?) ?? (resp['avatar'] as String?) ?? '';
      
      await prefs.setString('user_email', user?['email'] ?? widget.email);
      await prefs.setString('user_name', nameToSave);
      await prefs.setString('user_avatar', avatarToSave);
      await prefs.setString('user_role', role);

      // Save user_id for chat and other features that need the current user's ID
      final userId = user?['id'];
      if (userId != null) {
        await prefs.setInt('user_id', userId is int ? userId : int.tryParse(userId.toString()) ?? 0);
      }

      if (driver != null) {
        await prefs.setString('user_emg_name', driver['emergency_contact_name'] ?? '');
        await prefs.setString('user_emg_phone', driver['emergency_contact_phone'] ?? '');
        await prefs.setString('user_address', driver['address'] ?? '');
        await prefs.setString('user_cnic', driver['cnic'] ?? '');
        await prefs.setString('user_license', driver['driving_license_no'] ?? '');
        await prefs.setString('user_insurance', driver['insurance_no'] ?? '');
      }

      if (passenger != null) {
        await prefs.setString('user_emg_name', passenger['emergency_contact_name'] ?? '');
        await prefs.setString('user_emg_phone', passenger['emergency_contact_phone'] ?? '');
        await prefs.setString('user_address', passenger['address'] ?? '');
        await prefs.setString('user_gender_pref', passenger['gender_preference'] ?? 'Both');
      }
      
      if (vehicle != null) {
        await prefs.setString('vehicle_make', vehicle['make'] ?? '');
        await prefs.setString('vehicle_model', vehicle['model'] ?? '');
        await prefs.setString('vehicle_color', vehicle['color'] ?? '');
        await prefs.setString('vehicle_plate', vehicle['plate_no'] ?? '');
        await prefs.setString('vehicle_total_seats', vehicle['total_seats']?.toString() ?? '');
      }

      final userArgs = <String, dynamic>{
        'email': user?['email'] ?? widget.email,
        'name': nameToSave,
        'avatarUrl': avatarToSave,
        'role': role,
      }..removeWhere((k, v) => v == null || (v is String && v.isEmpty));

      if (widget.nextRoute != null) {
        Navigator.pushReplacementNamed(context, widget.nextRoute!, arguments: userArgs);
        return;
      }

      if (purpose == 'reset') {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.resetPassword,
          arguments: {'email': widget.email},
        );
        return;
      }

      if (role == 'driver') {
        if (purpose == 'signup') {
          if (status == 'driver_profile_pending') {
            Navigator.pushReplacementNamed(context, AppRoutes.driverProfile, arguments: userArgs);
          } else if (status == 'vehicle_pending') {
            Navigator.pushReplacementNamed(context, AppRoutes.vehicle, arguments: userArgs);
          } else {
            Navigator.pushReplacementNamed(context, AppRoutes.driverDashboard, arguments: userArgs);
          }
        } else {
          if (status == 'driver_profile_pending') {
            Navigator.pushReplacementNamed(context, AppRoutes.driverProfile, arguments: userArgs);
          } else {
            Navigator.pushReplacementNamed(context, AppRoutes.driverDashboard, arguments: userArgs);
          }
        }
        return;
      }

      if (status == 'passenger_profile_pending') {
        Navigator.pushReplacementNamed(context, AppRoutes.passengerProfile, arguments: userArgs);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.passengerDashboard, arguments: userArgs);
      }
    } on ApiException catch (e) {
      final msg = e.data?['reason'] == 'wrong_code'
          ? 'Incorrect code. Please try again.'
          : e.data?['reason'] == 'expired_or_missing'
          ? 'Code expired. Tap Resend to get a new code.'
          : e.data?['reason'] == 'too_many_attempts'
          ? 'Too many attempts. Request a new code.'
          : e.message;
      _toast(msg);
    } catch (e) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0) return;

    try {
      await Api.sendOtp({'email': widget.email, 'purpose': widget.purpose.toLowerCase()});
      _toast('OTP sent to ${widget.email}');
      _startTimer();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Unable to send OTP. Try again.');
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _title() {
    switch (widget.purpose.toLowerCase()) {
      case 'login': return 'Verify your login';
      case 'signup': return 'Verify your email';
      case 'reset': return 'Verify to reset';
      default: return 'Verify';
    }
  }

  String _cta() {
    switch (widget.purpose.toLowerCase()) {
      case 'login': return 'Verify login';
      case 'signup': return 'Verify email';
      case 'reset': return 'Verify & continue';
      default: return 'Verify';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    String mmss(int s) {
      final m = (s ~/ 60).toString();
      final sec = (s % 60).toString().padLeft(2, '0');
      return '$m:$sec';
    }

    final media = MediaQuery.of(context);
    final clamped = media.copyWith(
      textScaler: media.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2),
    );

    return MediaQuery(
      data: clamped,
      child: Scaffold(
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
            _title(),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Text(
                            'We sent a 6-digit code to\n${widget.email}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black87),
                          ),
                        ),
                        SizedBox(height: _gap(context, 18)),

                        Text('Code', style: theme.textTheme.bodyMedium),
                        SizedBox(height: _gap(context, 8)),

                        // OTP boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (i) {
                            return _OtpBox(
                              controller: _otpCtrls[i],
                              focusNode: _otpNodes[i],
                              onChanged: (val) {
                                if (val.isNotEmpty) {
                                  if (i < 5) {
                                    _otpNodes[i + 1].requestFocus();
                                  } else {
                                    FocusScope.of(context).unfocus();
                                  }
                                } else if (i > 0) {
                                  _otpNodes[i - 1].requestFocus();
                                }
                              },
                            );
                          }),
                        ),

                        SizedBox(height: _gap(context, 10)),

                        // Resend OTP link
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _seconds == 0 ? _resend : null,
                            child: Text(
                              _seconds == 0 ? 'Resend OTP' : 'Resend OTP in ${mmss(_seconds)}',
                              style: TextStyle(
                                color: _seconds == 0 ? _navy : Colors.black38,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: _gap(context, 12)),

                        // Verify button
                        SizedBox(
                          height: _buttonHeight(context),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _navy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(_gap(context, 12)),
                              ),
                            ),
                            onPressed: _loading ? null : _verify,
                            child: _loading
                                ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                                : Text(_cta()),
                          ),
                        ),

                        SizedBox(height: _gap(context, 12)),

                        // Wrong email line
                        Center(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              const Text('Wrong email?'),
                              GestureDetector(
                                onTap: () => Navigator.of(context).maybePop(),
                                child: Text(
                                  'Send to a different email',
                                  style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
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
                                  TextSpan(text: 'Terms', style: TextStyle(decoration: TextDecoration.underline)),
                                  TextSpan(text: ' and '),
                                  TextSpan(text: 'Privacy Policy', style: TextStyle(decoration: TextDecoration.underline)),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---- Single OTP box ----
class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scale = (MediaQuery.sizeOf(context).width / 375).clamp(0.82, 1.18);
    final side = (52 * scale).clamp(44, 60).toDouble();

    return SizedBox(
      width: side,
      height: side,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12 * scale)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12 * scale)),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) => onChanged(v.replaceAll(RegExp(r'\D'), '')),
      ),
    );
  }
}
