import 'package:flutter/material.dart';
import 'package:frontend/main.dart' show unreadCount;

/// A widget that wraps [child] with Flutter's [Badge] widget, driven by the
/// global [unreadCount] [ValueNotifier].
///
/// The badge is visible only when [unreadCount.value] > 0.
///
/// Requirement 12.5 — All decrements to [unreadCount] elsewhere in the app
/// MUST be floored at 0 (never go negative). Use:
///   unreadCount.value = (unreadCount.value - 1).clamp(0, unreadCount.value);
/// or equivalently:
///   if (unreadCount.value > 0) unreadCount.value--;
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({
    super.key,
    required this.child,
    this.badgeColor,
  });

  /// The widget to wrap — typically an [Icon].
  final Widget child;

  /// Background colour for the badge label. Defaults to [Colors.red].
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: unreadCount,
      builder: (context, count, _) {
        if (count <= 0) {
          // Badge hidden — return the child unwrapped to keep layout clean.
          return Badge(isLabelVisible: false, child: child);
        }
        return Badge(
          backgroundColor: badgeColor ?? Colors.red,
          label: Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          isLabelVisible: true,
          child: child,
        );
      },
    );
  }
}
