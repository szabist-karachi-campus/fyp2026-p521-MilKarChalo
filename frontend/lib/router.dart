import 'package:flutter/material.dart';
import 'features/auth/pages/welcome_page.dart';
import 'features/auth/pages/login_page.dart';
import 'features/auth/pages/signup_role_page.dart';
import 'features/auth/pages/signup_form_page.dart';
import 'features/auth/pages/verify_otp_page.dart';
import 'features/auth/pages/forgot_password_page.dart';
import 'features/auth/pages/reset_password_page.dart';
import 'features/dashboard/passenger_dashboard_page.dart';
import 'features/dashboard/driver_dashboard_page.dart';
import 'features/profile/pages/vehicle_page.dart';
import 'features/profile/pages/passenger_profile_page.dart';
import 'features/profile/pages/driver_profile_page.dart';
import 'features/profile/pages/profile_page.dart';
import 'features/edit_drv_profile/edit_drv_profile.dart';
import 'features/edit_pass_profile/edit_pass_profile.dart';
import 'features/edit_vehicle/edit_vehicle.dart';
import 'features/search_ride/search_ride.dart';
import 'features/post_ride/pages/post_ride.dart';
import 'features/search_ride/ride_detail_page.dart';
import 'features/Rides/booking_requests_page.dart';
import 'features/Rides/upcoming_rides_page.dart';
import 'features/Rides/ride_history_page.dart';
import 'features/Rides/drv_upcoming_ride.dart';
import 'features/Rides/my_bookings_page.dart';
import 'features/Rides/booking_detail_page.dart';
import 'features/reviews/review_history_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/chat/chat_page.dart';
import 'features/tracking/ride_tracking_page.dart';


class AppRoutes {
  static const welcome = '/';
  static const login = '/login';
  static const signupRole = '/signup-role';
  static const signupForm = '/signup-form';
  static const verifySignupOtp = '/verify-signup-otp';
  static const verifyLoginOtp = '/verify-login-otp';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const passengerDashboard = '/passenger-dashboard';
  static const driverDashboard = '/driver-dashboard';
  static const vehicle = '/vehicle';
  static const passengerProfile = '/passenger-profile';
  static const driverProfile = '/driver-profile';
  static const profile = '/profile';
  static const editDriverProfile = '/edit-driver-profile';
  static const editPassengerProfile = '/edit-passenger-profile';
  static const editVehicle = '/edit-vehicle';
  static const searchRide = '/search-ride';
  static const search = '/search-ride';
  static const postRide = '/post-ride';
  static const post = '/post-ride';
  static const rideDetail       = '/ride-detail';
  static const bookingRequests  = '/booking-requests';
  static const upcomingRides    = '/upcoming-rides';
  static const rideHistory      = '/ride-history';
  static const driverRideDetail = '/driver-ride-detail';
  static const myBookings        = '/my-bookings';
  static const bookingDetail     = '/booking-detail';
  static const reviewHistory     = '/review-history';
  static const notifications     = '/notifications';
  static const chat = '/chat';
  static const emergencyContacts = '/emergency-contacts';
  static const rideTracking = '/ride-tracking';
}

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.welcome:
      return MaterialPageRoute(builder: (_) => const WelcomePage());

    case AppRoutes.login:
      return MaterialPageRoute(builder: (_) => const LoginPage());

    case AppRoutes.signupRole:
      return MaterialPageRoute(builder: (_) => const SignupRolePage());

    case AppRoutes.signupForm: {
      final args = settings.arguments;
      String role = 'passenger'; // default

      if (args is Map && args['role'] is String) {
        role = args['role'];
      } else if (args is String) {
        role = args;
      }

      return MaterialPageRoute(
        builder: (_) => SignupFormPage(role: role),
        settings: settings,
      );
    }

    case AppRoutes.verifySignupOtp: {
      final a = settings.arguments as Map<String, dynamic>? ?? {};
      final email = a['email'] as String? ?? '';
      final role  = a['role']  as String? ?? 'passenger';
      return MaterialPageRoute(
        builder: (_) => VerifyOtpPage(
          purpose: 'signup',
          email: email,
          role: role,
        ),
        settings: settings,
      );
    }

    case AppRoutes.verifyLoginOtp: {
      final a = settings.arguments as Map<String, dynamic>? ?? {};
      final email = a['email'] as String? ?? '';
      final role  = a['role']  as String? ?? 'passenger';
      return MaterialPageRoute(
        builder: (_) => VerifyOtpPage(
          purpose: 'login',
          email: email,
          role: role,
        ),
        settings: settings,
      );
    }

    case AppRoutes.vehicle:
      return MaterialPageRoute(builder: (_) => const VehiclePage());

    case AppRoutes.driverProfile:
      return MaterialPageRoute(
        builder: (_) => const DriverProfilePage(),
        settings: settings,
      );

    case AppRoutes.passengerProfile:
      return MaterialPageRoute(
        builder: (_) => const PassengerProfilePage(),
        settings: settings,
      );

    case AppRoutes.profile:
      return MaterialPageRoute(
        builder: (_) => const ProfilePage(),
        settings: settings,
      );

    case AppRoutes.editDriverProfile:
      return MaterialPageRoute(
        builder: (_) => const EditDriverProfilePage(),
        settings: settings,
      );

    case AppRoutes.editPassengerProfile:
      return MaterialPageRoute(
        builder: (_) => const EditPassengerProfilePage(),
        settings: settings,
      );
      
    case AppRoutes.editVehicle:
      return MaterialPageRoute(
        builder: (_) => const EditVehiclePage(),
        settings: settings,
      );

    case AppRoutes.forgotPassword:
      return MaterialPageRoute(builder: (_) => const ForgotPasswordPage());

    case AppRoutes.resetPassword: {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      final email = args['email'] as String?;
      return MaterialPageRoute(
        builder: (_) => ResetPasswordPage(email: email), // Pass the email here
        settings: settings,
      );
    }

    case AppRoutes.passengerDashboard:
      return MaterialPageRoute(builder: (_) => const PassengerDashboardPage(), settings: settings);

    case AppRoutes.driverDashboard:
      return MaterialPageRoute(builder: (_) => const DriverDashboardPage(), settings: settings);

    case AppRoutes.searchRide:
      return MaterialPageRoute(builder: (_) => const SearchRidePage(), settings: settings);

    case AppRoutes.postRide:
      return MaterialPageRoute(builder: (_) => const PostRidePage(), settings: settings);

    case AppRoutes.bookingRequests:
      return MaterialPageRoute(builder: (_) => const BookingRequestsPage(), settings: settings);
    case AppRoutes.upcomingRides:
      return MaterialPageRoute(builder: (_) => const UpcomingRidesPage(), settings: settings);
    case AppRoutes.rideHistory:
      return MaterialPageRoute(builder: (_) => const RideHistoryPage(), settings: settings);
    case AppRoutes.driverRideDetail: {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      final rideId = args['rideId'] is int
          ? args['rideId'] as int
          : int.tryParse(args['rideId']?.toString() ?? '') ?? 0;
      final occurrenceId = args['occurrenceId'] is int
          ? args['occurrenceId'] as int
          : int.tryParse(args['occurrenceId']?.toString() ?? '');
      return MaterialPageRoute(
        builder: (_) => DriverRideDetailPage(rideId: rideId, occurrenceId: occurrenceId),
        settings: settings,
      );
    }
    case AppRoutes.myBookings:
      return MaterialPageRoute(builder: (_) => const MyBookingsPage(), settings: settings);
    case AppRoutes.bookingDetail: {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      final bookingId = args['bookingId'] as int?
          ?? int.tryParse(args['bookingId']?.toString() ?? '')
          ?? 0;
      return MaterialPageRoute(
        builder: (_) => BookingDetailPage(bookingId: bookingId),
        settings: settings,
      );
    }
    case AppRoutes.reviewHistory:
      return MaterialPageRoute(builder: (_) => const ReviewHistoryPage(), settings: settings);
    case AppRoutes.notifications:
      return MaterialPageRoute(builder: (_) => const NotificationsPage(), settings: settings);
    case AppRoutes.rideDetail:
      return MaterialPageRoute(
        builder: (_) => const RideDetailPage(),
        settings: settings,
      );

    case AppRoutes.chat: {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      final bookingId = args['bookingId'] is int
          ? args['bookingId'] as int
          : int.tryParse(args['bookingId']?.toString() ?? '') ?? 0;
      final counterpartName = args['counterpartName'] as String?;
      return MaterialPageRoute(
        builder: (_) => ChatPage(bookingId: bookingId, counterpartName: counterpartName),
        settings: settings,
      );
    }

    case AppRoutes.rideTracking: {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      final bookingId = args['bookingId'] is int
          ? args['bookingId'] as int
          : int.tryParse(args['bookingId']?.toString() ?? '') ?? 0;
      final rideId = args['rideId'] is int
          ? args['rideId'] as int
          : int.tryParse(args['rideId']?.toString() ?? '') ?? 0;
      final bookingData = (args['bookingData'] as Map<String, dynamic>?) ?? {};
      final isDriver = args['isDriver'] == true;
      return MaterialPageRoute(
        builder: (_) => RideTrackingPage(
          bookingId: bookingId,
          rideId: rideId,
          isDriver: isDriver,
          bookingData: bookingData,
        ),
        settings: settings,
      );
    }

    default:
      return MaterialPageRoute(builder: (_) => const WelcomePage());
  }
}
