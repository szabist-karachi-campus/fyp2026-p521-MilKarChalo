import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api.dart';

const Color _navy = Color(0xFF0A2540);

class RideHistoryPage extends StatefulWidget {
  const RideHistoryPage({super.key});

  @override
  State<RideHistoryPage> createState() => _RideHistoryPageState();
}

class _RideHistoryPageState extends State<RideHistoryPage> {
  bool _loading = true;
  String _role = 'passenger';
  List<dynamic> _rides = [];
  Map<int, List<dynamic>> _recurringOccurrences = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = (prefs.getString('user_role') ?? 'passenger').toLowerCase();
      final history = <Map<String, dynamic>>[];

      if (role == 'driver') {
        final rides = await Api.getMyRides();
        for (final item in rides) {
          final ride = item as Map;
          final status = ride['status']?.toString().toLowerCase() ?? '';
          final occurrenceStatus = ride['occurrence_status']?.toString().toLowerCase();

          // For recurring rides: use occurrence_status; for non-recurring: use status
          final effectiveStatus = occurrenceStatus ?? status;

          if (effectiveStatus == 'completed' ||
              effectiveStatus == 'cancelled' ||
              effectiveStatus == 'canceled') {
            history.add(Map<String, dynamic>.from(ride));
          }
        }
      } else {
        final bookings = await Api.getMyBookings();
        for (final item in bookings) {
          final booking = item as Map;
          final rideStatus    = booking['ride_status']?.toString().toLowerCase() ?? '';
          final bookingStatus = booking['booking_status']?.toString().toLowerCase() ?? '';

          // Only terminal booking states belong in history.
          // Pending bookings are excluded — they live in My Bookings.
          final isTerminalBooking = bookingStatus == 'completed' ||
              bookingStatus == 'cancelled' ||
              bookingStatus == 'canceled' ||
              bookingStatus == 'rejected';

          // A completed/cancelled ride also qualifies even if booking status lags
          final isTerminalRide = rideStatus == 'completed' ||
              rideStatus == 'cancelled' ||
              rideStatus == 'canceled';

          if (isTerminalBooking || (isTerminalRide && bookingStatus != 'pending')) {
            history.add(Map<String, dynamic>.from(booking));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _rides = history;
        _loading = false;
      });
      // Load occurrences for recurring rides
      await _loadRecurringOccurrences(history);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('⚠️ RideHistoryPage load failed: $e');
    }
  }

  Future<void> _loadRecurringOccurrences(List<dynamic> rides) async {
    for (final ride in rides) {
      final r = ride as Map;
      final isRecurring = r['is_recurring'] == true || 
                         r['is_recurring'] == 1 || 
                         r['is_recurring'] == '1';
      
      if (isRecurring) {
        final rideId = r['ride_id'] is int 
            ? r['ride_id'] as int
            : int.tryParse(r['ride_id']?.toString() ?? '');
        
        if (rideId != null && !_recurringOccurrences.containsKey(rideId)) {
          try {
            final occurrences = await Api.getRideOccurrences(rideId);
            if (!mounted) return;
            setState(() {
              _recurringOccurrences[rideId] = occurrences;
            });
          } catch (e) {
            debugPrint('⚠️ Failed to load occurrences for ride $rideId: $e');
          }
        }
      }
    }
  }

  String _formatTime(String? raw) {
    try {
      return DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(raw ?? '').toLocal());
    } catch (_) {
      return raw ?? '-';
    }
  }

  String _getDepartureDisplay(Map ride) {
    final isRecurring = ride['is_recurring'] == true || 
                       ride['is_recurring'] == 1 || 
                       ride['is_recurring'] == '1';
    
    // For recurring rides, try to use occurrence_date/departure_datetime if available
    if (isRecurring && ride['occurrence_date'] != null && ride['departure_datetime'] != null) {
      try {
        // departure_datetime is already in local/server time, don't call toLocal()
        final dt = DateTime.parse(ride['departure_datetime']?.toString() ?? '');
        return DateFormat('MMM d, yyyy • h:mm a').format(dt);
      } catch (_) {}
    }
    
    // Otherwise, use template departure_time
    return _formatTime(ride['departure_time']?.toString());
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'accepted':
      case 'active':
        return Colors.green;
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'accepted':
        return 'Accepted';
      case 'active':
        return 'Active';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
      case 'canceled':
        return 'Canceled';
      case 'completed':
        return 'Completed';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = _role == 'driver';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Ride History', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_outlined, size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No ride history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        isDriver
                            ? 'Completed and past rides will appear here.'
                            : 'Cancelled, rejected, and past bookings will appear here.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rides.length,
                    itemBuilder: (_, i) {
                      final ride = _rides[i] as Map;
                      final occurrenceStatus = ride['occurrence_status']?.toString();
                      final status = isDriver
                          ? (occurrenceStatus ?? ride['status']?.toString())
                          : ride['ride_status']?.toString();
                      final color = _statusColor(status);
                      final fare = double.tryParse(ride['fare']?.toString() ?? '')?.toStringAsFixed(0) ?? '-';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(children: [
                                Icon(isDriver ? Icons.directions_car : Icons.receipt_long, size: 16, color: color),
                                const SizedBox(width: 6),
                                Text(_statusLabel(status), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text(_getDepartureDisplay(ride), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ]),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.my_location, size: 15, color: Colors.green),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(ride['pickup_location']?.toString() ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                                  ]),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.location_on, size: 15, color: Colors.red),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(ride['destination']?.toString() ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                                  ]),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    const Icon(Icons.person, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        isDriver
                                            ? 'Bookings: ${ride['booking_count'] ?? 0}'
                                            : 'Driver: ${ride['driver_name']?.toString() ?? '-'}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Rs $fare', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(
                                    isDriver
                                        ? 'Available seats: ${ride['available_seats'] ?? '-'} / ${ride['total_seats'] ?? '-'}'
                                        : '${ride['car_make'] ?? ''} ${ride['car_model'] ?? ''}'.trim(),
                                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
