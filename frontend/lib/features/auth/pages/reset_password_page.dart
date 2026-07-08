import 'package:flutter/material.dart';

class ResetPasswordPage extends StatefulWidget {
  final String? email; // The email passed from the previous page

  const ResetPasswordPage({Key? key, this.email}) : super(key: key);

  @override
  _ResetPasswordPageState createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  // Controllers for OTP and password fields
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Focus nodes for password and OTP fields
  final _otpFocus = FocusNode();
  final _newPasswordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _isPasswordHidden = true; // Toggle for hiding password

  @override
  void dispose() {
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpFocus.dispose();
    _newPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  // Function to handle password reset
  void _resetPassword() {
    String otp = _otpController.text.trim();
    String newPassword = _newPasswordController.text.trim();
    String confirmPassword = _confirmPasswordController.text.trim();

    if (otp.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      _showErrorDialog('Please fill in all fields.');
      return;
    }

    if (newPassword != confirmPassword) {
      _showErrorDialog('Passwords do not match.');
      return;
    }

    // Assuming an OTP validation and password reset API call here
    print('Verifying OTP: $otp');
    print('Resetting password for: ${widget.email}');
    print('New Password: $newPassword');

    // If OTP is valid, proceed with resetting the password
    _showSuccessDialog('Password reset successful!');
  }

  // Function to show error dialogs
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the dialog
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Function to show success dialogs
  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Success'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.email != null)
              Text(
                'Resetting password for: ${widget.email}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            SizedBox(height: 16),

            // OTP field
            TextFormField(
              controller: _otpController,
              focusNode: _otpFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Enter OTP',
                hintText: 'Enter the OTP sent to your email',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey), // Gray outline
                ),
              ),
              onFieldSubmitted: (_) {
                FocusScope.of(context).requestFocus(_newPasswordFocus);
              },
            ),
            SizedBox(height: 16),

            // New password field
            TextFormField(
              controller: _newPasswordController,
              obscureText: _isPasswordHidden,
              focusNode: _newPasswordFocus,
              decoration: InputDecoration(
                labelText: 'New Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordHidden
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordHidden = !_isPasswordHidden;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey), // Gray outline
                ),
              ),
              onFieldSubmitted: (_) {
                FocusScope.of(context).requestFocus(_confirmPasswordFocus);
              },
            ),
            SizedBox(height: 16),

            // Confirm password field
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _isPasswordHidden,
              focusNode: _confirmPasswordFocus,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey), // Gray outline
                ),
              ),
            ),
            SizedBox(height: 32),

            // Reset password button
            ElevatedButton(
              onPressed: _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF0A2540), // Navy blue color
              ),
              child: Text('Reset Password'),
            ),
          ],
        ),
      ),
    );
  }
}
