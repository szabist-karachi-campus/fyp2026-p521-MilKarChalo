import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api.dart';
import '../../../router.dart';

class PassengerProfilePage extends StatefulWidget {
  const PassengerProfilePage({super.key});
  @override
  State<PassengerProfilePage> createState() => _PassengerProfilePageState();
}

class _PassengerProfilePageState extends State<PassengerProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _imageUrlC = TextEditingController(); // optional
  final _emgNameC = TextEditingController();
  final _emgPhoneC = TextEditingController();
  final _addressC  = TextEditingController();
  String _pref = 'both';

  bool _loading = false;
  late final int userId;
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
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {};
    userId = (args['user_id'] as int?) ?? args['userId'] as int? ?? 0;
  }

  @override
  void dispose() {
    _imageUrlC.dispose();
    _emgNameC.dispose();
    _emgPhoneC.dispose();
    _addressC.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 60);
      if (xfile == null) return;
      setState(() => _pickedImage = File(xfile.path));
    } catch (e) {
      // ignore errors for now
    }
  }

  Future<void> _showImageSourceActionSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Camera'), onTap: () { Navigator.pop(c); _pickImage(ImageSource.camera); }),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () { Navigator.pop(c); _pickImage(ImageSource.gallery); }),
            ListTile(leading: const Icon(Icons.close), title: const Text('Cancel'), onTap: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      // 1. Prepare Text Data (Must be Map<String, String>)
      final Map<String, String> data = {
        'emergency_contact_name': _emgNameC.text.trim(),
        'emergency_contact_phone': _emgPhoneC.text.trim(),
        'address': _addressC.text.trim(),
        'gender_preference': _pref,
      };

      // 2. Call the updated API method with the image file
      final resp = await Api.savePassengerProfile(data, _pickedImage);

      if (!mounted) return;

      if (resp != null && resp['ok'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_emg_name', data['emergency_contact_name']!);
        await prefs.setString('user_emg_phone', data['emergency_contact_phone']!);
        await prefs.setString('user_address', data['address']!);
        await prefs.setString('user_gender_pref', data['gender_preference']!);

        if (resp['image_url'] is String) {
          await prefs.setString('user_avatar', resp['image_url'] as String);
        }

        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.passengerDashboard, (r) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save profile. Please try again.')));
      }
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(BuildContext c, String label) {
    final r = BorderRadius.circular(12 * _scale(c));
    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14 * _scale(c)),
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
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: const Text('Complete Your Profile', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, _gap(context, 8), pad, _gap(context, 18)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: _gap(context, 6)),
              Center(
                child: GestureDetector(
                  onTap: _showImageSourceActionSheet,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: _gap(context, 110),
                        height: _gap(context, 110),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8DFFF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: _gap(context, 86),
                        height: _gap(context, 86),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: Builder(builder: (ctx) {
                            final targetDecodeWidth = (_gap(ctx, 86) * MediaQuery.of(ctx).devicePixelRatio).toInt();
                            if (_pickedImage == null) {
                              return Center(child: Icon(Icons.person, size: _gap(ctx, 44), color: const Color(0xFF042D4A)));
                            }
                            return Image.file(
                              _pickedImage!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Center(child: Icon(Icons.broken_image, color: Colors.grey.shade400)),
                            );
                          }),
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
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0,2))],
                          ),
                          child: Icon(Icons.cloud_upload, size: _gap(context, 18), color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: _gap(context, 8)),
              const Text('Upload Profile Pic', style: TextStyle(fontSize: 14, color: Colors.black54)),
              SizedBox(height: _gap(context, 18)),

              // Emergency Contact Name
              Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: _gap(context, 2)), child: Text('Emergency Contact Name', style: TextStyle(fontSize: 13 * _scale(context), color: Colors.black87)))),
              SizedBox(height: _gap(context, 6)),
              TextFormField(controller: _emgNameC, decoration: _dec(context, 'Enter your Full Name'), validator: (v)=> (v==null||v.isEmpty)?'Required':null),
              SizedBox(height: _gap(context, 12)),

              // Emergency Contact Phone
              Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: _gap(context, 2)), child: Text('Emergency Contact No', style: TextStyle(fontSize: 13 * _scale(context), color: Colors.black87)))),
              SizedBox(height: _gap(context, 6)),
                TextFormField(
                  controller: _emgPhoneC,
                  decoration: _dec(context, 'Enter Your number'),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Required';
                    final digits = s.replaceAll(RegExp(r'\D'), '');
                    if ((digits.length == 11 && digits.startsWith('03')) || (digits.length == 12 && digits.startsWith('92'))) return null;
                    return 'Enter valid PK mobile';
                  },
                ),
              SizedBox(height: _gap(context, 12)),

              // Address
              Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: _gap(context, 2)), child: Text('Address', style: TextStyle(fontSize: 13 * _scale(context), color: Colors.black87)))),
              SizedBox(height: _gap(context, 6)),
              TextFormField(controller: _addressC, decoration: _dec(context, 'Enter Your Address'), validator: (v)=> (v==null||v.length<5)?'Enter address':null),
              SizedBox(height: _gap(context, 12)),

              // Preferred Gender
              Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: _gap(context, 2)), child: Text('Preferred Gender', style: TextStyle(fontSize: 13 * _scale(context), color: Colors.black87)))),
              SizedBox(height: _gap(context, 6)),
              DropdownButtonFormField<String>(
                initialValue: _pref,
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'both', child: Text('Both')),
                ],
                onChanged: (v) => setState(() => _pref = v ?? 'both'),
                decoration: _dec(context, 'Enter Gender'),
              ),
              SizedBox(height: _gap(context, 18)),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF042D4A),
                    padding: EdgeInsets.symmetric(vertical: _gap(context, 14)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * _scale(context))),
                  ),
                  child: _loading
                      ? SizedBox(height: 22 * _scale(context), width: 22 * _scale(context), child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create an account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              SizedBox(height: _gap(context, 18)),
              Text('By submitting, you agree to the\nTerms and Privacy Policy.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12 * _scale(context), color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
