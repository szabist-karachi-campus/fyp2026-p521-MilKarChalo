import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../core/api.dart';
import '../../core/widgets/user_avatar.dart';
import '../../router.dart';
import '../reviews/review_sheet.dart';
import '../sos/sos_button.dart';

const Color _navy = Color(0xFF0A2540);

class DriverRideDetailPage extends StatefulWidget {
  const DriverRideDetailPage({super.key, required this.rideId, this.occurrenceId});

  final int rideId;
  final int? occurrenceId;

  @override
  State<DriverRideDetailPage> createState() => _DriverRideDetailPageState();
}

class _DriverRideDetailPageState extends State<DriverRideDetailPage> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _summary;
  List<dynamic> _passengers = [];
  List<dynamic> _occurrences = [];

  // Live location broadcasting
  IO.Socket? _socket;
  Timer? _locationTimer;
  bool _broadcastingLocation = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stopLocationBroadcast();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  void _startLocationBroadcast(int rideId) {
    if (_broadcastingLocation) return;
    _broadcastingLocation = true;

    final token = Api.bearerToken;
    _socket = IO.io(
      ApiConfig.base,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket!.connect();
    _socket!.onConnect((_) {
      _socket!.emit('join_tracking', {'rideId': rideId});
    });

    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) return;
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
        _socket?.emit('driver_location', {
          'rideId': rideId,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        });
      } catch (_) {}
    });
  }

  void _stopLocationBroadcast() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _broadcastingLocation = false;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await Api.getDriverRideDetails(widget.rideId, occurrenceId: widget.occurrenceId);
      final data = (resp['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _ride = (data['ride'] as Map?)?.cast<String, dynamic>();
        _summary = (data['summary'] as Map?)?.cast<String, dynamic>();
        _passengers = (data['passengers'] as List?) ?? [];
        _occurrences = (data['occurrences'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load ride details: $e')),
      );
    }
  }

  // For departure_time from rides table (ISO with timezone) — convert to local
  String _formatTime(String? raw) {
    try {
      return DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(raw ?? '').toLocal());
    } catch (_) {
      return raw ?? '-';
    }
  }

  // For departure_datetime from ride_occurrences (already local string "YYYY-MM-DD HH:MM:SS")
  String _formatOccurrenceTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw.replaceFirst(' ', 'T'));
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatOccurrenceDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final parts = raw.substring(0, 10).split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      return DateFormat('EEE, MMM d yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _startRide() async {
    setState(() => _saving = true);
    try {
      await Api.startDriverRide(widget.rideId);
      await _load();
      if (!mounted) return;
      // Start broadcasting GPS location to passengers
      _startLocationBroadcast(widget.rideId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride started. Sharing live location with passengers.'),
          backgroundColor: Colors.green,
        ),
      );
      // Navigate to driver tracking page
      final ride = _ride;
      if (ride != null && mounted) {
        final firstPassenger = _passengers.isNotEmpty
            ? _passengers.firstWhere(
                (p) => p['booking_status']?.toString() == 'accepted',
                orElse: () => _passengers.first,
              )
            : null;
        final bookingId = firstPassenger != null
            ? (firstPassenger['booking_id'] is int
                ? firstPassenger['booking_id'] as int
                : int.tryParse(firstPassenger['booking_id']?.toString() ?? '') ?? 0)
            : 0;
        Navigator.pushNamed(
          context,
          AppRoutes.rideTracking,
          arguments: {
            'bookingId': bookingId,
            'rideId': widget.rideId,
            'isDriver': true,
            'bookingData': {
              'driver_name': ride['driver_name'],
              'driver_image_url': ride['driver_image_url'],
              'car_make': ride['car_make'],
              'car_model': ride['car_model'],
              'car_color': ride['car_color'],
              'car_plate': ride['car_plate'],
              'driver_rating': ride['driver_rating'],
              'pickup_location': ride['pickup_location'],
              'destination': ride['destination'],
              'fare': ride['fare'],
              'departure_time': ride['departure_time'],
              'destination_lat': ride['destination_lat'],
              'destination_lng': ride['destination_lng'],
            },
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start ride: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text('This will cancel this ride and all its bookings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await Api.cancelDriverRide(widget.rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Ride cancelled successfully'),
          backgroundColor: Colors.green,
        ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel ride: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelAllRecurring() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel all recurring rides?'),
        content: const Text(
          'This will cancel ALL future occurrences of this recurring ride and all their bookings. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, cancel all', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await Api.cancelRecurringSeries(widget.rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('All recurring rides cancelled successfully'),
          backgroundColor: Colors.green,
        ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not cancel recurring rides: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelRoundTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel round trip?'),
        content: const Text('This will cancel BOTH departure and return legs, and all their bookings. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, cancel both', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await Api.cancelDriverRoundTrip(widget.rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Round trip cancelled successfully'),
          backgroundColor: Colors.green,
        ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel round trip: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _respondToBooking(int bookingId, String action) async {
    setState(() => _saving = true);
    try {
      await Api.respondToBooking(bookingId, action);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(action == 'accepted' ? 'Booking accepted ✅' : 'Booking rejected ❌'),
          backgroundColor: action == 'accepted' ? Colors.green : Colors.red,
        ));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'active':
        return Colors.green;
        case 'started':
          return Colors.orange;
        case 'cancelled':
        case 'canceled':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

    Future<void> _endRide() async {
      setState(() => _saving = true);
      try {
        await Api.endDriverRide(widget.rideId);
        if (!mounted) return;
        // Stop GPS broadcasting
        _stopLocationBroadcast();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride ended successfully')),
        );
        // Reload to get updated passenger list, then prompt for reviews
        await _load();
        if (!mounted) return;
        await _promptPendingReviews();
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not end ride: $e')),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    /// After a ride ends, auto-show review sheet for each accepted passenger not yet reviewed.
    Future<void> _promptPendingReviews() async {
      for (final p in _passengers) {
        final bookingStatus = p['booking_status']?.toString();
        final bookingId = p['booking_id'] is int
            ? p['booking_id'] as int
            : int.tryParse(p['booking_id']?.toString() ?? '');
        final reviewExists = p['review_id'] != null;

        if (bookingId != null && bookingStatus == 'completed' && !reviewExists) {
          if (!mounted) return;
          final submitted = await showReviewSheet(
            context,
            bookingId: bookingId,
            title: 'Rate ${p['passenger_name']?.toString() ?? 'passenger'}',
            subtitle: '${_ride?['pickup_location']?.toString() ?? '-'} → ${_ride?['destination']?.toString() ?? '-'}',
          );
          if (submitted == true && mounted) {
            await _load(); // refresh so next iteration has updated review_id
          }
          return; // show one at a time — user can review others from the page
        }
      }
    }
  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final rideStatus = (ride?['status']?.toString() ?? '').toLowerCase();
    final startedAt = ride?['started_at']?.toString();
    final isStarted = startedAt != null && startedAt.isNotEmpty;
    final isRecurring = ride?['is_recurring'] == true || ride?['is_recurring'] == 1 || ride?['is_recurring'] == '1';
    final recurrenceType = ride?['recurrence_type']?.toString() ?? '';
    final bookedSeats = _summary?['bookedSeats']?.toString() ?? '0';
    final pendingSeats = _summary?['pendingSeats']?.toString() ?? '0';
    final totalSeats = ride?['total_seats']?.toString() ?? '-';
    final availableSeats = ride?['available_seats']?.toString() ?? '-';
    final rideStatusColor = _statusColor(rideStatus);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Ride Details', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ride == null
              ? const Center(child: Text('Ride not found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: _navy.withValues(alpha: 0.1),
                                    child: const Icon(Icons.directions_car, color: _navy),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${ride['pickup_location'] ?? '-'} → ${ride['destination'] ?? '-'}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                        ),
                                        const SizedBox(height: 4),
                                        // For recurring rides: show recurrence label instead of template time
                                        if (isRecurring && widget.occurrenceId != null)
                                          Row(children: [
                                            const Icon(Icons.calendar_today, size: 14, color: Colors.amber),
                                            const SizedBox(width: 4),
                                            Text(
                                              _formatOccurrenceDate(_occurrences
                                                .where((o) {
                                                  final oid = o['id'] is int ? o['id'] as int : int.tryParse(o['id']?.toString() ?? '');
                                                  return oid == widget.occurrenceId;
                                                })
                                                .map((o) => o['occurrence_date']?.toString())
                                                .firstOrNull),
                                              style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                          ])
                                        else if (isRecurring)
                                          Row(children: [
                                            const Icon(Icons.repeat, size: 14, color: Colors.amber),
                                            const SizedBox(width: 4),
                                            Text(
                                              recurrenceType == 'daily' ? '🔁 Recurring Daily' : '🔁 Recurring Ride',
                                              style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                          ])
                                        else
                                          Text(
                                            _formatTime(ride['departure_time']?.toString()),
                                            style: const TextStyle(color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: rideStatusColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: rideStatusColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      (rideStatus.isEmpty ? 'active' : rideStatus).toUpperCase(),
                                      style: TextStyle(
                                        color: rideStatusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              // Round trip badge for driver
                              if ((ride['return_ride_id'] != null || ride['is_round_trip'] == true || ride['is_round_trip'] == 1)) ...[
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
                                const SizedBox(height: 16),
                              ],
                              Row(
                                children: [
                                  Expanded(child: _StatBox(label: 'Total Seats', value: totalSeats)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _StatBox(label: 'Booked Seats', value: bookedSeats)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _StatBox(label: 'Pending Seats', value: pendingSeats)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _StatBox(label: 'Available Seats', value: availableSeats)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _StatBox(label: 'Fare', value: 'Rs ${ride['fare'] ?? '-'}')),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _StatBox(
                                      label: 'Started',
                                      value: isStarted ? 'Yes' : 'No',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Occurrences section (recurring rides only) ────────
                      if (isRecurring && _occurrences.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'All Occurrences (${_occurrences.length})',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        ..._occurrences.map((occ) {
                          final occStatus = occ['status']?.toString() ?? 'active';
                          final occSeats = occ['available_seats']?.toString() ?? '-';
                          final occDate = _formatOccurrenceDate(occ['occurrence_date']?.toString());
                          final occTime = _formatOccurrenceTime(occ['departure_datetime']?.toString());
                          final isPast = () {
                            try {
                              final d = occ['occurrence_date']?.toString() ?? '';
                              return DateTime.parse(d).isBefore(DateTime.now().subtract(const Duration(days: 1)));
                            } catch (_) { return false; }
                          }();

                          Color occColor;
                          switch (occStatus) {
                            case 'cancelled': occColor = Colors.red; break;
                            case 'completed': occColor = Colors.blue; break;
                            default: occColor = isPast ? Colors.grey : Colors.green;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: occColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.calendar_today, color: occColor, size: 18),
                              ),
                              title: Text(occDate, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Text(occTime, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    occStatus.toUpperCase(),
                                    style: TextStyle(color: occColor, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                  Text('$occSeats seats', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],

                      const SizedBox(height: 16),
                      const Text('Passengers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (_passengers.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No passengers have booked this ride yet.'),
                          ),
                        )
                      else
                        ..._passengers.map((p) {
                          final bookingStatus = p['booking_status']?.toString();
                          final bookingColor = _statusColor(bookingStatus);
                          final canReviewPassenger = bookingStatus == 'completed' && p['review_id'] == null;
                          final reviewExists = p['review_id'] != null;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      UserAvatar(
                                        imageUrl: p['passenger_image_url']?.toString(),
                                        radius: 22,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p['passenger_name']?.toString() ?? 'Passenger',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              p['passenger_phone']?.toString() ?? '-',
                                              style: const TextStyle(color: Colors.grey),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Seats: ${p['seats_booked'] ?? '-'}',
                                              style: const TextStyle(color: Colors.grey),
                                            ),
                                            // Show occurrence date for recurring ride bookings
                                            if (p['occurrence_date'] != null) ...[
                                              const SizedBox(height: 4),
                                              Row(children: [
                                                const Icon(Icons.calendar_today, size: 12, color: Colors.amber),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatOccurrenceDate(p['occurrence_date']?.toString()),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.amber,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ]),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: bookingColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: bookingColor.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          (bookingStatus ?? 'pending').toUpperCase(),
                                          style: TextStyle(
                                            color: bookingColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (reviewExists) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.shade100),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.verified_rounded, size: 18, color: Colors.green.shade700),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'You already reviewed this passenger',
                                              style: TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  // ── Accept / Reject for pending bookings ──
                                  if (bookingStatus == 'pending') ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _saving ? null : () {
                                              final bookingId = p['booking_id'] is int
                                                  ? p['booking_id'] as int
                                                  : int.tryParse(p['booking_id']?.toString() ?? '');
                                              if (bookingId != null) _respondToBooking(bookingId, 'rejected');
                                            },
                                            icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                            label: const Text('Reject', style: TextStyle(color: Colors.red)),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(color: Colors.red),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: _saving ? null : () {
                                              final bookingId = p['booking_id'] is int
                                                  ? p['booking_id'] as int
                                                  : int.tryParse(p['booking_id']?.toString() ?? '');
                                              if (bookingId != null) _respondToBooking(bookingId, 'accepted');
                                            },
                                            icon: const Icon(Icons.check, size: 16, color: Colors.white),
                                            label: const Text('Accept', style: TextStyle(color: Colors.white)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (canReviewPassenger) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          final bookingId = p['booking_id'] is int
                                              ? p['booking_id'] as int
                                              : int.tryParse(p['booking_id']?.toString() ?? '');
                                          if (bookingId == null) return;
                                          final submitted = await showReviewSheet(
                                            context,
                                            bookingId: bookingId,
                                            title: 'Rate ${p['passenger_name']?.toString() ?? 'passenger'}',
                                            subtitle: '${ride['pickup_location']?.toString() ?? '-'} → ${ride['destination']?.toString() ?? '-'}',
                                          );
                                          if (submitted == true) {
                                            await _load();
                                          }
                                        },
                                        icon: const Icon(Icons.star_rounded),
                                        label: const Text('Review Passenger'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _navy,
                                          side: const BorderSide(color: _navy),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],

                                  // Chat button for accepted bookings
                                  if (bookingStatus == 'accepted') ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                        label: const Text('Chat with Passenger'),
                                        onPressed: () {
                                          final bId = p['booking_id'] is int
                                              ? p['booking_id'] as int
                                              : int.tryParse(p['booking_id']?.toString() ?? '') ?? 0;
                                          Navigator.pushNamed(
                                            context,
                                            '/chat',
                                            arguments: {
                                              'bookingId': bId,
                                              'counterpartName': p['passenger_name']?.toString(),
                                            },
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _navy,
                                          side: const BorderSide(color: _navy),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 10),
                      if (rideStatus == 'active') ...[
                        const SizedBox(height: 10),
                        // Cancel buttons — stack vertically when multiple are needed
                        Builder(builder: (context) {
                          final isRoundTrip = ride['is_round_trip'] == true ||
                              ride['is_round_trip'] == 1 ||
                              ride['round_trip_group_id'] != null;
                          if (isRoundTrip && isRecurring) {
                            // Recurring round trip: 3 stacked buttons
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton(
                                  onPressed: _saving ? null : _cancelRide,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  child: const Text('Cancel This Ride', style: TextStyle(color: Colors.red)),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _saving ? null : _cancelRoundTrip,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade600,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  child: const Text('Cancel Round Trip', style: TextStyle(color: Colors.white)),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _saving ? null : _cancelAllRecurring,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade800,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  child: const Text('Cancel All Recurring', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            );
                          }
                          // Non-recurring or non-round-trip: side-by-side row
                          return Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving ? null : _cancelRide,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: const Text('Cancel Ride', style: TextStyle(color: Colors.red)),
                                ),
                              ),
                              if (isRoundTrip) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _saving ? null : _cancelRoundTrip,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade700,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text('Cancel Round Trip', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                              if (isRecurring && !isRoundTrip) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _saving ? null : _cancelAllRecurring,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade700,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text('Cancel All', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _saving ? null : _startRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _saving
                              ? const SizedBox(height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Start Ride', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                      if (rideStatus == 'started') ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.my_location, size: 18, color: Colors.white),
                          label: const Text('Resume Tracking', style: TextStyle(color: Colors.white)),
                          onPressed: () {
                            final ride = _ride;
                            if (ride == null) return;
                            final firstAccepted = _passengers.firstWhere(
                              (p) => (p as Map)['booking_status']?.toString() == 'accepted',
                              orElse: () => _passengers.isNotEmpty ? _passengers.first : null,
                            );
                            final bookingId = firstAccepted != null
                                ? (firstAccepted['booking_id'] is int
                                    ? firstAccepted['booking_id'] as int
                                    : int.tryParse(firstAccepted['booking_id']?.toString() ?? '') ?? 0)
                                : 0;
                            Navigator.pushNamed(
                              context,
                              AppRoutes.rideTracking,
                              arguments: {
                                'bookingId': bookingId,
                                'rideId': widget.rideId,
                                'isDriver': true,
                                'bookingData': {
                                  'driver_name': ride['driver_name'],
                                  'driver_image_url': ride['driver_image_url'],
                                  'car_make': ride['car_make'],
                                  'car_model': ride['car_model'],
                                  'car_color': ride['car_color'],
                                  'car_plate': ride['car_plate'],
                                  'driver_rating': ride['driver_rating'],
                                  'pickup_location': ride['pickup_location'],
                                  'destination': ride['destination'],
                                  'fare': ride['fare'],
                                  'departure_time': ride['departure_time'],
                                  'destination_lat': ride['destination_lat'],
                                  'destination_lng': ride['destination_lng'],
                                },
                              },
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _saving ? null : _endRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('End Ride', style: TextStyle(color: Colors.white)),
                        ),
                      ],

                      // SOS Emergency Button for driver
                      Builder(builder: (context) {
                        // Use the first accepted booking's ID for the driver's SOS
                        final acceptedBooking = _passengers.firstWhere(
                          (p) => (p as Map)['booking_status']?.toString() == 'accepted',
                          orElse: () => null,
                        );
                        if (acceptedBooking == null) return const SizedBox.shrink();
                        final bId = acceptedBooking['booking_id'] is int
                            ? acceptedBooking['booking_id'] as int
                            : int.tryParse(acceptedBooking['booking_id']?.toString() ?? '') ?? 0;
                        if (bId == 0) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 10),
                            SosButton(
                              bookingId: bId,
                              rideStatus: rideStatus,
                              bookingStatus: 'accepted',
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
