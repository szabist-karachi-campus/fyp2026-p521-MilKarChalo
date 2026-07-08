import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api.dart';
import '../../../router.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});
  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _emgNameC    = TextEditingController();
  final _emgPhoneC   = TextEditingController();
  final _addressC    = TextEditingController();
  final _cnicC       = TextEditingController();
  final _licenseC    = TextEditingController();
  final _insuranceC  = TextEditingController();

  bool _loading = false;
  
  bool _depsLoaded = false;

  File? _pickedImage;
  final ImagePicker _picker = ImagePicker();

  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.85, 1.15);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(28, w * 0.06));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guard so we only read args once — prevents the late final crash
    if (_depsLoaded) return;
    _depsLoaded = true;
    // No need to store userId — backend extracts it from the Bearer token
  }

  @override
  void dispose() {
    _emgNameC.dispose();
    _emgPhoneC.dispose();
    _addressC.dispose();
    _cnicC.dispose();
    _licenseC.dispose();
    _insuranceC.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 60); // FIX: compress aggressively to avoid timeout
      if (xfile == null) return;
      setState(() => _pickedImage = File(xfile.path));
    } catch (_) {}
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Camera'),
            onTap: () { Navigator.pop(c); _pickImage(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () { Navigator.pop(c); _pickImage(ImageSource.gallery); },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(c),
          ),
        ]),
      ),
    );
  }

  String _normalizePhone(String input) {
    final s = input.trim();
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return s;
    if (digits.length == 10 && digits.startsWith('3'))    return '+92$digits';
    if (digits.length == 11 && digits.startsWith('03'))   return '+92${digits.substring(1)}';
    if (digits.length == 12 && digits.startsWith('92'))   return '+$digits';
    if (digits.length == 13 && digits.startsWith('0092')) return '+${digits.substring(2)}';
    return s;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a profile picture')));
      return;
    }

    setState(() => _loading = true);
    try {
      final Map<String, String> data = {
        'emergency_contact_name':  _emgNameC.text.trim(),
        'emergency_contact_phone': _normalizePhone(_emgPhoneC.text),
        'address':                 _addressC.text.trim(),
        'cnic':                    _cnicC.text.trim(),
        'driving_license_no':      _licenseC.text.trim(),
        'insurance_no':            _insuranceC.text.trim(),
      };

      final resp = await Api.saveDriverProfile(data, _pickedImage);
      if (!mounted) return;

      if (resp['ok'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_emg_name',  data['emergency_contact_name']!);
        await prefs.setString('user_emg_phone',  data['emergency_contact_phone']!);
        await prefs.setString('user_address',    data['address']!);
        await prefs.setString('user_cnic',       data['cnic']!);
        await prefs.setString('user_license',    data['driving_license_no']!);
        await prefs.setString('user_insurance',  data['insurance_no']!);
        if (resp['image_url'] is String) {
          await prefs.setString('user_avatar', resp['image_url'] as String);
        }

        // FIX 2: navigate to the Vehicle page (with dropdowns) after saving profile
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.vehicle);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save profile. Please try again.')));
      }
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(BuildContext c, String hint) {
    final r = BorderRadius.circular(12 * _scale(c));
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14 * _scale(c)),
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: _gap(c, 16), vertical: _gap(c, 14)),
    );
  }

  Widget _label(BuildContext c, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(fontSize: 13 * _scale(c), color: Colors.black87)),
      );

  @override
  Widget build(BuildContext context) {
    final pad = _hPad(context);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: const Text('Complete Your Profile',
            style: TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, _gap(context, 8), pad, _gap(context, 18)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: _gap(context, 6)),

              // ── Avatar picker ──
              GestureDetector(
                onTap: _showImageSourceSheet,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: _gap(context, 110),
                      height: _gap(context, 110),
                      decoration: const BoxDecoration(
                          color: Color(0xFFE8DFFF), shape: BoxShape.circle),
                    ),
                    Container(
                      width: _gap(context, 86),
                      height: _gap(context, 86),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: ClipOval(
                        child: _pickedImage == null
                            ? Center(
                                child: Icon(Icons.person,
                                    size: _gap(context, 44),
                                    color: const Color(0xFF042D4A)))
                            : Image.file(_pickedImage!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity),
                      ),
                    ),
                    Positioned(
                      right: _gap(context, 6),
                      bottom: _gap(context, 6),
                      child: Container(
                        width: _gap(context, 36),
                        height: _gap(context, 36),
                        decoration: BoxDecoration(
                          color: const Color(0xFF042D4A),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Icon(Icons.cloud_upload,
                            size: _gap(context, 18), color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: _gap(context, 8)),
              const Text('Upload Profile Pic',
                  style: TextStyle(fontSize: 14, color: Colors.black54)),
              SizedBox(height: _gap(context, 18)),

              // ── Fields ──
              _label(context, 'Emergency Contact Name'),
              SizedBox(height: _gap(context, 6)),
              TextFormField(
                controller: _emgNameC,
                decoration: _dec(context, 'Enter Full Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              SizedBox(height: _gap(context, 12)),

              _label(context, 'Emergency Contact No'),
              SizedBox(height: _gap(context, 6)),
              TextFormField(
                controller: _emgPhoneC,
                decoration: _dec(context, 'e.g. 03001234567'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) return 'Required';
                  if ((digits.length == 11 && digits.startsWith('03')) ||
                      (digits.length == 12 && digits.startsWith('92'))) return null;
                  return 'Enter valid PK number (03XXXXXXXXX)';
                },
              ),
              SizedBox(height: _gap(context, 12)),

              _label(context, 'Address'),
              SizedBox(height: _gap(context, 6)),
              TextFormField(
                controller: _addressC,
                decoration: _dec(context, 'Enter Your Address'),
                validator: (v) =>
                    (v == null || v.trim().length < 5) ? 'Enter a valid address' : null,
              ),
              SizedBox(height: _gap(context, 12)),

              _label(context, 'CNIC / National ID'),
              SizedBox(height: _gap(context, 6)),
              TextFormField(
                controller: _cnicC,
                decoration: _dec(context, 'Enter 13 digits (e.g. 3520112345671)'),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    RegExp(r'^\d{13}$').hasMatch(v ?? '') ? null : 'Enter 13 digits',
              ),
              SizedBox(height: _gap(context, 12)),

              _label(context, 'Driving License No'),
              SizedBox(height: _gap(context, 6)),
              TextFormField(
                controller: _licenseC,
                decoration: _dec(context, 'Enter License Number'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              SizedBox(height: _gap(context, 12)),

              _label(context, 'Insurance No (optional)'),
              SizedBox(height: _gap(context, 6)),
              TextFormField(
                controller: _insuranceC,
                decoration: _dec(context, 'Enter Insurance Number'),
              ),
              SizedBox(height: _gap(context, 24)),

              // ── Submit ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF042D4A),
                    padding: EdgeInsets.symmetric(vertical: _gap(context, 14)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * _scale(context))),
                  ),
                  child: _loading
                      ? SizedBox(
                          height: 22 * _scale(context),
                          width: 22 * _scale(context),
                          child: const CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save & Continue',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
