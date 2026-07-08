import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'router.dart';
import 'core/api.dart';
import 'core/notification_service.dart';

final ValueNotifier<int> unreadCount = ValueNotifier(0);

/// Must be a top-level function — called by FCM when the app is terminated
/// or in the background. Runs in a separate isolate so it cannot touch UI.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final plugin = FlutterLocalNotificationsPlugin();
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await plugin.initialize(initSettings);
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'milkarchalo_fcm',
        'MilKarChalo Notifications',
        importance: Importance.high,
      ));

  final title = message.notification?.title ?? message.data['title'] ?? 'New notification';
  final body  = message.notification?.body  ?? message.data['body']  ?? '';

  // Encode FCM data so the tap handler can route correctly
  final payload = message.data.isNotEmpty
      ? Uri(queryParameters: message.data.map((k, v) => MapEntry(k, v.toString()))).query
      : null;

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'milkarchalo_fcm',
        'MilKarChalo Notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: payload,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Register background handler BEFORE runApp
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Check if the user is already logged in
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final role = prefs.getString('user_role');

  String initialRoute = AppRoutes.welcome;

  if (token != null && token.isNotEmpty && role != null && role.isNotEmpty) {
    Api.setToken(token);
    if (role == 'driver') {
      initialRoute = AppRoutes.driverDashboard;
    } else {
      initialRoute = AppRoutes.passengerDashboard;
    }

    Api.getUnreadCount()
        .then((count) => unreadCount.value = count)
        // ignore: return_of_invalid_type_from_catch_error
        .catchError((_) => 0);

    NotificationService().init();
  }

  runApp(MilKarChaloApp(initialRoute: initialRoute));
}

class MilKarChaloApp extends StatelessWidget {
  const MilKarChaloApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MilKar Chalo',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      onGenerateRoute: generateRoute,
      initialRoute: initialRoute,
    );
  }
}
