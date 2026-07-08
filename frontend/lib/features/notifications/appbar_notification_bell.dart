import 'package:flutter/material.dart';
import 'package:frontend/main.dart' show unreadCount;
import 'package:frontend/router.dart';

/// A reusable AppBar action widget that shows a notification bell icon with
/// a live unread-count badge, driven by the global [unreadCount] ValueNotifier.
///
/// Usage — add to any Scaffold's AppBar actions list:
///
/// ```dart
/// appBar: AppBar(
///   actions: const [AppBarNotificationBell()],
/// )
/// ```
class AppBarNotificationBell extends StatelessWidget {
  const AppBarNotificationBell({super.key, this.color});

  /// Icon colour. Defaults to white so it works on dark AppBars.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: unreadCount,
      builder: (context, count, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications_outlined,
                color: color ?? Colors.white,
              ),
              tooltip: 'Notifications',
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.notifications),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      count > 99 ? '99+' : count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
