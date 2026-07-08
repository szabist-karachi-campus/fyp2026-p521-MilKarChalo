import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin/AdminLoginPage.dart';
import 'admin/admin_dashboard.dart';
import 'api.dart';

const String _apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:4000');

void main() async {
  // FIX: must call this before using SharedPreferences in main()
  WidgetsFlutterBinding.ensureInitialized();

  ApiConfig.setBase(_apiBase);

  // FIX: Restore saved token on every app start (including web page refresh).
  // Without this, Api._bearerToken is null and every protected endpoint
  // returns 401 Unauthorized even though the admin already logged in.
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString('token');
  if (savedToken != null && savedToken.isNotEmpty) {
    Api.setToken(savedToken);
  }

  runApp(MilKarChaloAdmin(isLoggedIn: savedToken != null && savedToken.isNotEmpty));
}

class MilKarChaloAdmin extends StatelessWidget {
  final bool isLoggedIn;
  const MilKarChaloAdmin({super.key, this.isLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MilKar Chalo Admin Portal',
      theme: ThemeData(
        primaryColor: const Color(0xFF0A2540),
        useMaterial3: true,
      ),
      // FIX: If token already exists (user previously logged in), go straight
      // to dashboard. Otherwise show the login page.
      initialRoute: isLoggedIn ? '/dashboard' : '/',
      routes: {
        '/': (context) => const AdminLoginPage(),
        '/dashboard': (context) => const AdminDashboard(),
      },
    );
  }
}
