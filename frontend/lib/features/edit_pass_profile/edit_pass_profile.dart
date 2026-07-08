import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api.dart';

const Color kNavy = Color(0xFF0A2540);
const Color kLightGrey = Color(0xFFF7F8F9);
const Color kGreyText = Color(0xFF6C757D);

class EditPassengerProfilePage extends StatefulWidget {
  const EditPassengerProfilePage({super.key});

  @override
  State<EditPassengerProfilePage> createState() => _EditPassengerProfilePageState();
}

class _EditPassengerProfilePageState extends State<EditPassengerProfilePage> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  File? _pickedImage;
  final ImagePicker _picker = ImagePicker();

  final _emgNameC = TextEditingController();
  final _emgPhoneC = TextEditingController();
  final _addressC = TextEditingController();
  String _genderPreference = 'Both';
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _emgNameC.dispose();
    _emgPhoneC.dispose();
    _addressC.dispose();
    super.dispose();
  }

  void _loadUser() async {
    final prefs = await SharedPreferences.getInstance();

    String genderPref = prefs.getString('user_gender_pref')?.toLowerCase() ?? 'both';
    String displayGender;
    if (genderPref == 'male') {
      displayGender = 'Male';
    } else if (genderPref == 'female') {
      displayGender = 'Female';
    } else {
      displayGender = 'Both';
    }

    setState(() {
      _emgNameC.text = prefs.getString('user_emg_name') ?? '';
      _emgPhoneC.text = prefs.getString('user_emg_phone') ?? '';
      _addressC.text = prefs.getString('user_address') ?? '';
      _genderPreference = displayGender;
      _avatarUrl = prefs.getString('user_avatar');
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      if (xfile == null) return;
      setState(() => _pickedImage = File(xfile.path));
    } catch (e) {
      // ignore
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
      String normalizePhone(String input) {
        final s = input.trim();
        final digits = s.replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) return s;
        if (digits.length == 10 && digits.startsWith('3')) return '+92$digits';
        if (digits.length == 11 && digits.startsWith('03')) return '+92${digits.substring(1)}';
        if (digits.length == 12 && digits.startsWith('92')) return '+$digits';
        if (digits.length == 13 && digits.startsWith('0092')) return '+${digits.substring(2)}';
        return s;
      }

      final Map<String, String> data = {
        'emergency_contact_name': _emgNameC.text.trim(),
        'emergency_contact_phone': normalizePhone(_emgPhoneC.text),
        'address': _addressC.text.trim(),
        'gender_preference': _genderPreference.toLowerCase(),
      };

      final resp = await Api.savePassengerProfile(data, _pickedImage);

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_emg_name', data['emergency_contact_name']!);
      await prefs.setString('user_emg_phone', data['emergency_contact_phone']!);
      await prefs.setString('user_address', data['address']!);
      await prefs.setString('user_gender_pref', data['gender_preference']!);

      if (resp is Map && resp['image_url'] is String) {
        await prefs.setString('user_avatar', resp['image_url'] as String);
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? fullAvatarUrl;
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      if (_avatarUrl!.startsWith('http')) {
        fullAvatarUrl = _avatarUrl;
      } else {
        final baseUrl = ApiConfig.base;
        final avatarPath = _avatarUrl!.startsWith('/') ? _avatarUrl!.substring(1) : _avatarUrl;
        fullAvatarUrl = '$baseUrl/$avatarPath';
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kNavy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _showImageSourceActionSheet,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: kLightGrey,
                              backgroundImage: _pickedImage != null
                                  ? FileImage(_pickedImage!)
                                  : (fullAvatarUrl != null ? CachedNetworkImageProvider(fullAvatarUrl) : null) as ImageProvider?,
                              child: _pickedImage == null && fullAvatarUrl == null
                                  ? const Icon(Icons.person, size: 50, color: kNavy)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: kNavy,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, color: Colors.white, size: 20),
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildTextField(
                      label: 'EMERGENCY CONTACT NAME',
                      controller: _emgNameC,
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      label: 'EMERGENCY CONTACT PHONE',
                      controller: _emgPhoneC,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      label: 'ADDRESS',
                      controller: _addressC,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    _buildDropdownField(),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kNavy,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white))
                          : const Text(
                              'Save Changes',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: kGreyText, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'This field cannot be empty';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GENDER PREFERENCE',
          style: TextStyle(color: kGreyText, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _genderPreference,
          items: ['Both', 'Male', 'Female'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _genderPreference = newValue!;
            });
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }
}
