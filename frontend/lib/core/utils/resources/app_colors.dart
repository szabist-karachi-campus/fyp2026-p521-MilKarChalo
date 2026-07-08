import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color splashColor = white;
  static const Color transparent = Colors.transparent;
  static const Color background = Color(0xffFFFFFF);

  static const Color primary = Color(0xFFC9A961);
  static const Color secondary = Color(0xFF042D4A);
  static const Color tertirary = Color(0xffFF6E40);
  static const Color bgColor = Color(0xFFF5F4F7); // Light bluish shade background
  static const Color primaryLight = Color(0xff9ACB48);
  static const Color secondaryLight = Color(0xffD2E9ED);
  static const Color appBarColor = Color(0xFFE4EFF4);
  static const Color headingColor = Color(0xFFffffff);
  static const Color white = Color(0xffffffff);
  static const Color black = Color(0xff000000);
  static const Color green = Color(0xff74C54C);
  static const Color yellow = Color(0xffFFCF00);
  static const Color orange = Color(0xffFF8200);
  static const Color lightOrange = Color(0xffF9AD2B);
  static const Color grey = Color(0xff27272A);
  static const Color lightGreyish = Color(0xffDEDBE9);
  static const Color red = Color(0xffFB2E30);
  static const Color peach = Color(0xffED9490);
  static const Color blue = Color(0xff0165FC);
  static const Color purple = Color(0xff5B64AF);

  static const Color primaryText = Color(0xFF020202);
  static const Color secondaryText = Color(0xffC5C5CF);
  static const Color tertiaryText = Color(0xff7a8c95);

  static const Color whiteGreyish = Color(0xffF5F5F5);
  static const Color darkGrey = Color(0xff7B7A7D);
  static const Color darkGreen = Color(0xff2C6E04);

  static const Color lightGrey = Color(0xffEEEEEF);
  static const Color lightPeach = Color(0xffFBEAE9);
  static const Color lightGreen = Color(0xffDEF0DA);

  static const Color cardGrey = Color(0xfff1f2f3);
  static const Color dividerColor = Color(0xffE7EBED);

  static const Color greyish = Color(0xffDCDCDC);
  
  // New colors for exploration design
  static const Color explorationGold = Color(0xFFC9A961); // Brownish-gold color (more accurate)
  static const Color explorationTeal = Color(0xFF1A4A47); // Dark teal/green color (more accurate)
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color selectedButtonBg = Color(0xFF000000);
  static const Color unselectedButtonBg = Color(0xFFFFFFFF);
  
  static RadialGradient primaryGrad = RadialGradient(
    radius: 60,
    center: Alignment.center,
    focalRadius: 50,
    colors: [Color(0xFFF7F3EF), Color(0xFFFECE8E40).withAlpha(120)],
  );
  static LinearGradient secondaryGrad = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFFCB85)],
  );
  static LinearGradient cardGrad = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFFEBE0)],
  );
  static LinearGradient invertedCardGrad = LinearGradient(
    colors: [Color(0xFFFFEBE0), Color(0xFFFFFFFF)],
  );
  
  // Light orange/peach gradient for home screen background (right center corner)
  static RadialGradient homeScreenGradient = RadialGradient(
    center: Alignment(0.85, 0.25), // Right center position
    radius: 1.2,
    colors: [
      Color(0xffECF2FA).withOpacity(0.5), // Soft peach/orange
      Color(0xFFECF2FA).withOpacity(0.35), // Lighter peach
      Color(0xFFECF2FA).withOpacity(0.2), // Very light peach
      Colors.transparent,
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
  );
}
