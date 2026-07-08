import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api.dart';
import '../../router.dart';

const Color _navy = Color(0xFF0A2540);

class UpcomingRidesPage extends StatefulWidget {
  const UpcomingRidesPage({super.key});

  @override
  State<UpcomingRidesPage> createState() => _UpcomingRidesPageState();
}

class _UpcomingRidesPageState extends State<UpcomingRidesPage> {
  bool _loading = true;
  String _role = 'passenger';
  List<dynamic> _rides = [];

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
      final upcoming = <Map<String, dynamic>>[];

      if (role == 'driver') {
        final rides = await Api.getMyRides();
        for (final item in rides) {
          final ride = item as Map;
          final status = ride['status']?.toString().toLowerCase() ?? '';
          final occurrenceStatus = ride['occurrence_status']?.toString().toLowerCase();

          // For recurring: active occurrence; for non-recurring: active ride
          final effectiveStatus = occurrenceStatus ?? status;
          if (effectiveStatus == 'active') {
            upcoming.add(Map<String, dynamic>.from(ride));
          }
        }
      } else {
        final bookings = await Api.getMyBookings();
        for (final item in bookings) {
          final booking = item as Map;
          final rideStatus = booking['ride_status']?.toString().toLowerCase() ?? '';
          final bookingStatus = booking['booking_status']?.toString().toLowerCase() ?? '';
          if (rideStatus == 'active' || rideStatus == 'started' || (rideStatus.isEmpty && bookingStatus == 'accepted')) {
            upcoming.add(Map<String, dynamic>.from(booking));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _rides = upcoming;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('⚠️ UpcomingRidesPage load failed: $e');
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

    // Recurring: use departure_datetime from the occurrence (plain local string from backend)
    if (isRecurring && ride['departure_datetime'] != null) {
      try {
        final dt = DateTime.parse(
          ride['departure_datetime']!.toString().replaceFirst(' ', 'T')
        );
        return DateFormat('EEE, MMM d • h:mm a').format(dt);
      } catch (_) {}
    }

    // Non-recurring: ISO timestamp — convert to local
    return _formatTime(ride['departure_time']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = _role == 'driver';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Upcoming Rides', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available_outlined, size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No upcoming rides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        isDriver
                            ? 'Your active future rides will appear here.'
                            : 'Your active rides will appear here.',
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
                      final rideId = ride['ride_id'] is int
                          ? ride['ride_id'] as int
                          : int.tryParse(ride['ride_id']?.toString() ?? '') ?? 0;
                      final occurrenceId = ride['occurrence_id'] is int
                          ? ride['occurrence_id'] as int
                          : int.tryParse(ride['occurrence_id']?.toString() ?? '');
                      final isRecurring = ride['is_recurring'] == true ||
                          ride['is_recurring'] == 1 ||
                          ride['is_recurring'] == '1';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: isDriver
                              ? () async {
                                  final changed = await Navigator.pushNamed(
                                    context,
                                    AppRoutes.driverRideDetail,
                                    arguments: {
                                      'rideId': rideId,
                                      'occurrenceId': occurrenceId,
                                    },
                                  );
                                  if (changed == true && mounted) {
                                    _load();
                                  }
                                }
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: _navy.withOpacity(0.1),
                                      child: const Icon(Icons.directions_car, color: _navy),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isDriver
                                                ? '${ride['pickup_location'] ?? '-'} → ${ride['destination'] ?? '-'}'
                                                : '${ride['driver_name']?.toString() ?? 'Driver'}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          Text(
                                            isDriver
                                                ? (isRecurring ? '🔁 Recurring Ride' : '${ride['available_seats'] ?? '-'} seats left')
                                                : '${ride['car_make'] ?? ''} ${ride['car_model'] ?? ''}'.trim(),
                                            style: TextStyle(
                                              color: isDriver && isRecurring ? Colors.amber : Colors.grey,
                                              fontSize: 13,
                                              fontWeight: isDriver && isRecurring ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDriver
                                            ? Colors.green.shade50
                                            : (ride['ride_status']?.toString().toLowerCase() == 'started'
                                                ? Colors.orange.shade50
                                                : Colors.green.shade50),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isDriver
                                              ? Colors.green.shade200
                                              : (ride['ride_status']?.toString().toLowerCase() == 'started'
                                                  ? Colors.orange.shade200
                                                  : Colors.green.shade200),
                                        ),
                                      ),
                                      child: Text(
                                        isDriver
                                            ? 'Upcoming'
                                            : (ride['ride_status']?.toString().toLowerCase() == 'started'
                                                ? 'In Progress'
                                                : 'Upcoming'),
                                        style: TextStyle(
                                          color: isDriver
                                              ? Colors.green
                                              : (ride['ride_status']?.toString().toLowerCase() == 'started'
                                                  ? Colors.orange
                                                  : Colors.green),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Divider(height: 1),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(_getDepartureDisplay(ride), style: const TextStyle(fontSize: 13, color: Colors.grey))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 14, color: Colors.red),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        isDriver
                                            ? 'Booked: ${ride['booked_seats'] ?? 0} • Pending: ${ride['pending_seats'] ?? 0}'
                                            : '${ride['pickup_location'] ?? '-'} → ${ride['destination'] ?? '-'}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.payments_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text('Rs ${double.tryParse(ride['fare']?.toString() ?? '')?.toStringAsFixed(0) ?? '-'}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                ),
                                if ((ride['return_ride_id'] != null || ride['is_round_trip'] == true || ride['is_round_trip'] == 1)) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _navy.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.loop, size: 14, color: _navy),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '🔄 Round Trip',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: _navy,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (isRecurring) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.repeat, size: 14, color: Colors.amber),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '🔁 Recurring',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.amber,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (isDriver) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Tap to view passengers and ride actions',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ],
                          ),
                        ),
                      ),
                      );
                    },
                  ),
                ),
    );
  }
}
