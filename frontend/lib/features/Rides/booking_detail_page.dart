import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../router.dart';

/// A thin loading page that resolves a booking by [bookingId] from the
/// passenger's booking list, then immediately pushes [AppRoutes.rideDetail]
/// with the ride data.  If the booking cannot be found it falls back to
/// [AppRoutes.myBookings].
///
/// This is used by notification deep-links so the user lands on the specific
/// ride detail rather than the generic booking list.
class BookingDetailPage extends StatefulWidget {
  const BookingDetailPage({super.key, required this.bookingId});

  final int bookingId;

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage> {
  @override
  void initState() {
    super.initState();
    // Resolve after the first frame so the page is in the tree before we push
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    try {
      final bookings = await Api.getMyBookings();
      final match = bookings.cast<Map>().firstWhere(
        (b) {
          final id = b['booking_id'];
          final parsed = id is int ? id : int.tryParse(id?.toString() ?? '');
          return parsed == widget.bookingId;
        },
        orElse: () => {},
      );

      if (!mounted) return;

      if (match.isEmpty) {
        debugPrint('[BookingDetail] booking ${widget.bookingId} not found, fallback');
        Navigator.pushReplacementNamed(context, AppRoutes.myBookings);
        return;
      }

      final rideArgs = {
        'id': match['ride_id'],
        'pickup_location': match['pickup_location'],
        'destination': match['destination'],
        'departure_time': match['departure_time'],
        'available_seats': null,
        'fare': match['fare'],
        'driver_name': match['driver_name'],
        'driver_image_url': match['driver_image_url'],
        'car_make': match['car_make'],
        'car_model': match['car_model'],
        'car_color': match['car_color'],
        'car_plate': match['car_plate'],
        'booking_status': match['booking_status'],
        'read_only': true,
      };

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.rideDetail,
        arguments: rideArgs,
      );
    } catch (e) {
      debugPrint('[BookingDetail] error: $e');
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.myBookings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
