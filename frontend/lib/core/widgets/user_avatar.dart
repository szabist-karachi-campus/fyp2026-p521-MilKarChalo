import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api.dart';

/// A circular avatar that loads a profile photo from the server when
/// [imageUrl] is non-null, falling back to an icon placeholder.
///
/// [imageUrl] should be a relative server path like `/uploads/foo.webp`.
/// The widget prepends [ApiConfig.base] automatically.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.imageUrl,
    this.radius = 22,
    this.backgroundColor,
    this.placeholderIcon = Icons.person,
    this.iconColor,
  });

  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final IconData placeholderIcon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? const Color(0xFF0A2540).withValues(alpha: 0.1);
    final ic = iconColor ?? const Color(0xFF0A2540);

    if (imageUrl == null || imageUrl!.isEmpty) {
      return _placeholder(bg, ic);
    }

    final fullUrl = '${ApiConfig.base}$imageUrl';

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: fullUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(bg, ic),
          errorWidget: (_, __, ___) => _placeholder(bg, ic),
        ),
      ),
    );
  }

  Widget _placeholder(Color bg, Color ic) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Icon(placeholderIcon, color: ic, size: radius),
    );
  }
}
