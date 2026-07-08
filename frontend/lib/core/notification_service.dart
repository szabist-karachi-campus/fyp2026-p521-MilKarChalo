import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:frontend/core/api.dart';
import 'package:frontend/main.dart';

// ── Shared channel definition (must match AndroidManifest meta-data) ────────
const String _channelId   = 'milkarchalo_fcm';
const String _channelName = 'MilKarChalo Notifications';
const String _channelDesc = 'Ride and booking notifications from MilKarChalo';

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  _channelId,
  _channelName,
  description: _channelDesc,
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

// ── Local notifications plugin (singleton) ──────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// ---------------------------------------------------------------------------
// Route resolution — maps notification type + payload → route + arguments
// ---------------------------------------------------------------------------

/// Returns `{ route, arguments }` for any incoming FCM message.
/// Falls back to `/notifications` for unknown types or missing IDs.
Map<String, dynamic> resolveNotificationRoute(Map<String, dynamic> data) {
  final type      = data['type']       as String? ?? '';
  final rideId    = int.tryParse(data['ride_id']?.toString()    ?? '');
  final bookingId = int.tryParse(data['booking_id']?.toString() ?? '');

  debugPrint('[NotifNav] type=$type ride_id=$rideId booking_id=$bookingId');

  switch (type) {
    // ── Passenger: booking status changed → open that specific booking ────────
    case 'booking_accepted':
    case 'booking_rejected':
      if (bookingId != null) {
        return {
          'route': '/booking-detail',
          'arguments': {'bookingId': bookingId},
        };
      }
      return {'route': '/my-bookings', 'arguments': null};

    // ── Passenger: ride event → open specific ride detail ────────────────────
    case 'ride_started':
    case 'ride_completed':
    case 'ride_cancelled':
      if (bookingId != null) {
        return {
          'route': '/booking-detail',
          'arguments': {'bookingId': bookingId},
        };
      }
      return {'route': '/my-bookings', 'arguments': null};

    // ── Driver: new booking request or passenger cancelled → ride detail ──────
    case 'booking_request':
    case 'booking_cancelled':
      if (rideId != null) {
        return {
          'route': '/driver-ride-detail',
          'arguments': {'rideId': rideId},
        };
      }
      return {'route': '/booking-requests', 'arguments': null};

    // ── Driver: account status → notifications inbox ──────────────────────────
    case 'driver_approved':
    case 'driver_rejected':
    case 'driver_suspended':
      return {'route': '/notifications', 'arguments': null};

    default:
      return {'route': '/notifications', 'arguments': null};
  }
}

/// Navigates using [navigatorKey] based on the FCM message data.
/// Safe to call from any context — guards against null navigator.
void navigateFromMessage(
  GlobalKey<NavigatorState> navigatorKey,
  Map<String, dynamic> data,
) {
  final resolved  = resolveNotificationRoute(data);
  final route     = resolved['route']     as String;
  final arguments = resolved['arguments'];

  debugPrint('[NotifNav] navigating to $route args=$arguments');

  final state = navigatorKey.currentState;
  if (state == null) {
    debugPrint('[NotifNav] navigatorKey not ready — navigation skipped');
    return;
  }
  state.pushNamed(route, arguments: arguments);
}

// ---------------------------------------------------------------------------
// NotificationService
// ---------------------------------------------------------------------------

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Future<void> init() async {
    // ── 1. Set up local notifications + Android channel ──────────────────────
    await _setupLocalNotifications();

    // ── 2. Permissions ───────────────────────────────────────────────────────
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] permission: ${settings.authorizationStatus}');

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // ── 3. iOS foreground presentation ───────────────────────────────────────
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── 4. FCM token registration ─────────────────────────────────────────────
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] token: $token');
      if (token != null && token.isNotEmpty) {
        await Api.registerFcmToken(token);
      }
    } catch (e) {
      debugPrint('[FCM] token registration failed: $e');
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      Api.registerFcmToken(newToken).catchError((e) {
        debugPrint('[FCM] token refresh failed: $e');
        return <String, dynamic>{};
      });
    });

    // ── 5. Foreground messages ────────────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unreadCount.value += 1;
      debugPrint('[FCM] foreground message type=${message.data['type']}');

      final title = message.notification?.title
          ?? message.data['title']
          ?? 'New notification';
      final body = message.notification?.body
          ?? message.data['body']
          ?? '';

      if (Platform.isAndroid) {
        _showLocalNotification(title, body, message.data);
      }
    });

    // ── 6. Background tap (app was backgrounded, user taps notification) ──────
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] background tap type=${message.data['type']}');
      navigateFromMessage(navigatorKey, Map<String, dynamic>.from(message.data));
    });

    // ── 7. Terminated-app tap ─────────────────────────────────────────────────
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] cold-start tap type=${initialMessage.data['type']}');
      // Delay until after the first frame so the navigator is mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateFromMessage(
          navigatorKey,
          Map<String, dynamic>.from(initialMessage.data),
        );
      });
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<void> _setupLocalNotifications() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _localNotifications.initialize(
      initSettings,
      // Foreground local-notification tap (Android only)
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[LocalNotif] tap payload=${response.payload}');
        // Payload is the JSON-encoded FCM data map stored by _showLocalNotification
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            // payload is "type=booking_request&ride_id=5&booking_id=3" style
            final data = Uri.splitQueryString(response.payload!);
            navigateFromMessage(navigatorKey, data);
          } catch (e) {
            debugPrint('[LocalNotif] failed to parse payload: $e');
            navigatorKey.currentState?.pushNamed('/notifications');
          }
        } else {
          navigatorKey.currentState?.pushNamed('/notifications');
        }
      },
    );
  }

  /// Shows a local notification on Android foreground.
  /// Encodes the FCM data map as query string in [payload] so the tap handler
  /// can reconstruct it and route correctly.
  void _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    // Encode data as query string so it survives the payload string limit
    final payload = Uri(queryParameters: data.map((k, v) => MapEntry(k, v.toString()))).query;

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }
}
