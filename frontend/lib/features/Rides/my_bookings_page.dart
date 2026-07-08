import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../core/api.dart';
import '../../core/widgets/user_avatar.dart';
import '../../router.dart';
import '../reviews/review_sheet.dart';
import '../sos/sos_button.dart';

const Color _navy = Color(0xFF0A2540);

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});
  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  List<dynamic> _bookings = [];
  bool _loading = true;
  final Map<int, List<dynamic>> _recurringOccurrences = {};

  // Tracking socket — listens for ride_started events
  IO.Socket? _trackingSocket;
  final Set<int> _joinedRideRooms = {};
  // Track bookings already reviewed this session to avoid re-prompting
  final Set<int> _reviewedThisSession = {};

  // Only show active bookings (pending / accepted) — completed/cancelled/rejected excluded
  List<dynamic> get _active => _bookings.where((b) {
        final s = (b as Map)['booking_status']?.toString() ?? '';
        return s == 'pending' || s == 'accepted';
      }).toList();

  /// Get the paired leg booking (if this is part of a round trip or recurring round trip)
  Map<String, dynamic>? _getPairedLeg(Map booking, List<dynamic> bookingsList) {
    final groupId = booking['booking_group_id']?.toString();
    if (groupId == null) return null;
    
    final occurrenceDate = booking['occurrence_date']?.toString();
    final legType = booking['leg_type']?.toString();
    
    if (occurrenceDate == null || legType == null) return null;
    
    // Find the booking with same group, same date, but opposite leg type
    final opposite = legType == 'departure' ? 'return' : 'departure';
    
    final paired = bookingsList.firstWhere(
      (item) {
        final b = item as Map;
        return b['booking_group_id']?.toString() == groupId &&
            b['occurrence_date']?.toString() == occurrenceDate &&
            b['leg_type']?.toString() == opposite;
      },
      orElse: () => null,
    );
    
    return paired is Map ? (paired as Map<String, dynamic>) : null;
  }

  /// Check if this booking has a paired leg in the same booking group
  bool _hasPairedLeg(Map booking) {
    final groupId = booking['booking_group_id']?.toString();
    final occurrenceDate = booking['occurrence_date']?.toString();
    final legType = booking['leg_type']?.toString();
    
    if (groupId == null || occurrenceDate == null || legType == null) {
      return false;
    }
    
    final opposite = legType == 'departure' ? 'return' : 'departure';
    
    return _bookings.any((item) {
      final b = item as Map;
      return b['booking_group_id']?.toString() == groupId &&
          b['occurrence_date']?.toString() == occurrenceDate &&
          b['leg_type']?.toString() == opposite;
    });
  }

  @override
  void initState() {
    super.initState();
    _load(checkReviews: true);
    _connectTrackingSocket();
  }

  @override
  void dispose() {
    _trackingSocket?.disconnect();
    _trackingSocket?.dispose();
    super.dispose();
  }

  void _connectTrackingSocket() {
    final token = Api.bearerToken;
    _trackingSocket = IO.io(
      ApiConfig.base,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _trackingSocket!.connect();

    _trackingSocket!.on('ride_started', (data) {
      if (!mounted) return;
      final rideId = (data['rideId'] as num?)?.toInt();
      if (rideId == null) return;

      // Find the matching accepted booking for this ride
      final booking = _bookings.firstWhere(
        (b) {
          final bMap = b as Map;
          return (bMap['ride_id']?.toString() == rideId.toString() ||
                  bMap['ride_id'] == rideId) &&
              bMap['booking_status']?.toString() == 'accepted';
        },
        orElse: () => null,
      );
      if (booking == null) return;

      final b = booking as Map;
      final bookingId = b['booking_id'] is int
          ? b['booking_id'] as int
          : int.tryParse(b['booking_id']?.toString() ?? '') ?? 0;
      if (bookingId == 0) return;

      // Navigate to tracking page
      Navigator.pushNamed(
        context,
        AppRoutes.rideTracking,
        arguments: {
          'bookingId': bookingId,
          'rideId': rideId,
          'bookingData': {
            'driver_name': b['driver_name'],
            'driver_image_url': b['driver_image_url'],
            'car_make': b['car_make'],
            'car_model': b['car_model'],
            'car_color': b['car_color'],
            'car_plate': b['car_plate'],
            'driver_rating': b['driver_rating'],
            'pickup_location': b['pickup_location'],
            'destination': b['destination'],
            'fare': b['fare'],
            'departure_time': b['departure_time'],
            'destination_lat': b['destination_lat'],
            'destination_lng': b['destination_lng'],
          },
        },
      );
    });

    // After loading bookings, join tracking rooms for all accepted rides
    _trackingSocket!.onConnect((_) => _joinAcceptedRideRooms());
  }

  void _joinAcceptedRideRooms() {
    for (final item in _bookings) {
      final b = item as Map;
      if (b['booking_status']?.toString() != 'accepted') continue;
      final rideId = b['ride_id'] is int
          ? b['ride_id'] as int
          : int.tryParse(b['ride_id']?.toString() ?? '') ?? 0;
      if (rideId == 0 || _joinedRideRooms.contains(rideId)) continue;
      _trackingSocket?.emit('join_tracking', {'rideId': rideId});
      _joinedRideRooms.add(rideId);
    }
  }

  Future<void> _load({bool checkReviews = false}) async {
    setState(() => _loading = true);
    try {
      final data = await Api.getMyBookings();
      setState(() {
        _bookings = data;
        _loading = false;
      });
      if (checkReviews && mounted) {
        _promptPendingReviews();
      }
      // Join tracking rooms for any accepted rides
      _joinAcceptedRideRooms();
      await _loadRecurringOccurrences(data);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRecurringOccurrences(List<dynamic> bookings) async {
    for (final booking in bookings) {
      final b = booking as Map;
      final isRecurring = b['is_recurring'] == true || 
                         b['is_recurring'] == 1 || 
                         b['is_recurring'] == '1';
      
      if (isRecurring) {
        final rideId = b['ride_id'] is int 
            ? b['ride_id'] as int
            : int.tryParse(b['ride_id']?.toString() ?? '');
        
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

  Future<void> _promptPendingReviews() async {
    // Load persisted reviewed booking IDs
    final prefs = await SharedPreferences.getInstance();
    final reviewed = prefs.getStringList('reviewed_booking_ids') ?? [];
    final reviewedIds = reviewed.map(int.tryParse).whereType<int>().toSet();
    // Merge with this-session set
    reviewedIds.addAll(_reviewedThisSession);

    for (final b in _bookings) {
      final booking = b as Map;
      final bookingStatus = booking['booking_status']?.toString() ?? '';
      final bookingId = booking['booking_id'] is int
          ? booking['booking_id'] as int
          : int.tryParse(booking['booking_id']?.toString() ?? '');
      final hasReview = booking['review_id'] != null;

      if (bookingId == null) continue;
      if (hasReview || reviewedIds.contains(bookingId)) continue;
      if (bookingStatus != 'completed') continue;

      if (!mounted) return;

      // Mark as handled before showing to prevent re-entry
      _reviewedThisSession.add(bookingId);
      reviewedIds.add(bookingId);
      await prefs.setStringList(
          'reviewed_booking_ids', reviewedIds.map((id) => id.toString()).toList());

      final submitted = await showReviewSheet(
        context,
        bookingId: bookingId,
        title: 'Rate ${booking['driver_name']?.toString() ?? 'your driver'}',
        subtitle:
            '${booking['pickup_location']?.toString() ?? '-'} → ${booking['destination']?.toString() ?? '-'}',
      );

      if (submitted == true && mounted) {
        // Reload silently — no re-prompt
        await _load(checkReviews: false);
      }
      // Only one prompt per load
      return;
    }
  }

  String _formatTime(String? raw) {
    try {
      return DateFormat('MMM d, yyyy  •  h:mm a')
          .format(DateTime.parse(raw ?? '').toLocal());
    } catch (_) {
      return raw ?? '-';
    }
  }

  String _formatDepartureTime({required Map booking, required int? rideId}) {
    final isRecurring = booking['is_recurring'] == true || 
                       booking['is_recurring'] == 1 || 
                       booking['is_recurring'] == '1';
    
    // For recurring rides, try to use the occurrence_date and departure_datetime
    if (isRecurring && booking['occurrence_date'] != null && booking['departure_datetime'] != null) {
      try {
        // departure_datetime is already in local/server time, don't call toLocal()
        final dt = DateTime.parse(booking['departure_datetime']?.toString() ?? '');
        return DateFormat('MMM d, yyyy  •  h:mm a').format(dt);
      } catch (_) {}
    }
    
    // Fallback to template departure_time
    return _formatTime(booking['departure_time']?.toString());
  }

  String _formatOccurrenceDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final datePart = raw.substring(0, 10);
      final parts = datePart.split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      return DateFormat('EEE, MMM d yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'accepted':  return Colors.green;
      case 'rejected':  return Colors.red;
      case 'cancelled': return Colors.grey;
      case 'completed': return Colors.blue;
      default:          return Colors.orange;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'accepted':  return Icons.check_circle;
      case 'rejected':  return Icons.cancel;
      case 'cancelled': return Icons.block;
      case 'completed': return Icons.task_alt;
      default:          return Icons.hourglass_top;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'accepted':  return 'Accepted';
      case 'rejected':  return 'Rejected';
      case 'cancelled': return 'Cancelled';
      case 'completed': return 'Completed';
      default:          return 'Pending';
    }
  }

  Future<void> _cancelBooking(int bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Api.cancelBooking(bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Booking cancelled successfully.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// For recurring round trips: cancel both the departure and return leg for the same occurrence date.
  Future<void> _cancelThisOccurrence(Map booking) async {
    final occurrenceDate = booking['occurrence_date']?.toString();
    final groupId = booking['booking_group_id']?.toString();

    // Collect booking IDs for both legs on this date
    final idsToCancel = <int>[];
    for (final item in _bookings) {
      final b = item as Map;
      final bStatus = b['booking_status']?.toString() ?? '';
      if (bStatus == 'cancelled' || bStatus == 'rejected') continue;
      final bGroupId = b['booking_group_id']?.toString();
      final bDate = b['occurrence_date']?.toString();
      if (bGroupId == groupId && bDate == occurrenceDate) {
        final id = b['booking_id'] is int
            ? b['booking_id'] as int
            : int.tryParse(b['booking_id']?.toString() ?? '');
        if (id != null) idsToCancel.add(id);
      }
    }

    final hasBothLegs = idsToCancel.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel This Date'),
        content: Text(hasBothLegs
            ? 'This will cancel both the departure and return leg for this date. Continue?'
            : 'Are you sure you want to cancel this booking? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (final id in idsToCancel) {
        await Api.cancelBooking(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(hasBothLegs
                  ? 'Both legs for this date cancelled.'
                  : 'Booking cancelled successfully.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _cancelBookingGroup(String groupId) async {
    // Determine if this group is a recurring multi-occurrence or a round trip
    final isRecurringGroup = _bookings.any((item) {
      final b = item as Map;
      return b['booking_group_id']?.toString() == groupId &&
          (b['is_recurring'] == true ||
              b['is_recurring'] == 1 ||
              b['is_recurring'] == '1');
    });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRecurringGroup ? 'Cancel All Occurrences' : 'Cancel Round Trip'),
        content: Text(
          isRecurringGroup
              ? 'Are you sure you want to cancel all booked occurrences? This cannot be undone.'
              : 'Are you sure you want to cancel both legs of this round trip? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Api.cancelBookingGroup(groupId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(isRecurringGroup
                  ? 'All booked occurrences cancelled successfully.'
                  : 'Round trip cancelled successfully.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _active;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('My Bookings', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(checkReviews: true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : bookings.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.directions_car_outlined,
                        size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    const Text('No active bookings',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Your pending and accepted rides will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(checkReviews: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: bookings.length,
                    itemBuilder: (_, i) {
                      final b = bookings[i] as Map;
                      final status = b['booking_status']?.toString();
                      final rideStatus =
                          b['ride_status']?.toString().toLowerCase();
                      final fare =
                          double.tryParse(b['fare']?.toString() ?? '')
                                  ?.toStringAsFixed(0) ??
                              '-';
                      final color = _statusColor(status);
                      final bookingId = b['booking_id'] is int
                          ? b['booking_id'] as int
                          : int.tryParse(b['booking_id']?.toString() ?? '');
                      final groupId = b['booking_group_id']?.toString();
                      final isRecurring = b['is_recurring'] == true ||
                          b['is_recurring'] == 1 ||
                          b['is_recurring'] == '1';
                      final groupCount = groupId == null
                          ? 1
                          : _bookings
                              .where((item) =>
                                  (item as Map)['booking_group_id']
                                      ?.toString() ==
                                  groupId)
                              .length;
                      
                      // Check if next booking is the paired leg
                      final isPairedLegNext = i + 1 < bookings.length &&
                          _getPairedLeg(b, bookings) ==
                              bookings[i + 1];
                      
                      // Check if this is a return leg and previous was departure
                      final isPairedLegPrev = i > 0 &&
                          _getPairedLeg(b, bookings) ==
                              bookings[i - 1];

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          // Build a ride-shaped map that RideDetailPage understands
                          final rideArgs = {
                            'id': b['ride_id'],
                            'pickup_location': b['pickup_location'],
                            'destination': b['destination'],
                            'departure_time': b['departure_time'],
                            'available_seats': null,
                            'fare': b['fare'],
                            'driver_name': b['driver_name'],
                            'driver_image_url': b['driver_image_url'],
                            'car_make': b['car_make'],
                            'car_model': b['car_model'],
                            'car_color': b['car_color'],
                            'car_plate': b['car_plate'],
                            'booking_status': b['booking_status'],
                            'read_only': true,
                          };
                          Navigator.pushNamed(
                            context,
                            AppRoutes.rideDetail,
                            arguments: rideArgs,
                          );
                        },
                        child: Card(
                        margin: EdgeInsets.only(
                          bottom: isPairedLegNext ? 2 : 14,
                          top: isPairedLegPrev ? 0 : 0,
                        ),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(isPairedLegPrev ? 0 : 16),
                              topRight: Radius.circular(isPairedLegPrev ? 0 : 16),
                              bottomLeft: Radius.circular(isPairedLegNext ? 0 : 16),
                              bottomRight: Radius.circular(isPairedLegNext ? 0 : 16),
                            )),
                        child: Column(
                          children: [
                            // Status banner
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(children: [
                                Icon(_statusIcon(status),
                                    size: 16, color: color),
                                const SizedBox(width: 6),
                                Text(_statusLabel(status),
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text(
                                    _formatTime(
                                        b['requested_at']?.toString()),
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ]),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Route
                                  Row(children: [
                                    const Icon(Icons.my_location,
                                        size: 15, color: Colors.green),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(
                                            b['pickup_location']
                                                    ?.toString() ??
                                                '-',
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w500))),
                                  ]),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.location_on,
                                        size: 15, color: Colors.red),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(
                                            b['destination']?.toString() ??
                                                '-',
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w500))),
                                  ]),

                                  if (b['leg_type'] != null) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _navy.withValues(
                                              alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${b['leg_type'] == 'return' ? '↩️ Return' : '➜ Departure'} leg',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _navy),
                                            ),
                                            if (_hasPairedLeg(b)) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.link,
                                                size: 12,
                                                color: _navy,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),

                                  // Driver & car — with profile photo
                                  Row(children: [
                                    UserAvatar(
                                      imageUrl: b['driver_image_url']?.toString(),
                                      radius: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        b['driver_name']?.toString() ?? '-',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const Icon(Icons.directions_car,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                        '${b['car_make'] ?? ''} ${b['car_model'] ?? ''}'
                                            .trim(),
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ]),
                                  const SizedBox(height: 6),
                                  // Occurrence date (recurring bookings)
                                  if (b['occurrence_date'] != null) ...[
                                    Row(children: [
                                      const Icon(Icons.repeat, size: 14, color: Colors.amber),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Date: ${_formatOccurrenceDate(b['occurrence_date']?.toString())}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.amber,
                                        ),
                                      ),
                                    ]),
                                    const SizedBox(height: 6),
                                  ],
                                  Row(children: [
                                    const Icon(Icons.access_time,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                        _formatDepartureTime(
                                          booking: b,
                                          rideId: b['ride_id'] is int 
                                              ? b['ride_id'] as int
                                              : int.tryParse(b['ride_id']?.toString() ?? ''),
                                        ),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey)),
                                    const Spacer(),
                                    Text('Rs $fare / seat',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: _navy)),
                                  ]),

                                  // Round trip badge
                                  if ((b['return_ride_id'] != null || b['is_round_trip'] == true || b['is_round_trip'] == 1)) ...[
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
                                          Text(
                                            isRecurring ? '🔄 Recurring Round Trip' : '🔄 Round Trip',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: _navy,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  if (groupCount > 1 &&
                                      groupId != null) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        isRecurring && (b['is_round_trip'] == true || b['is_round_trip'] == 1)
                                            ? 'This recurring round trip covers ${groupCount ~/ 2} round-trip pairs${groupCount % 2 != 0 ? ' (plus 1 unpaired leg)' : ''}. You can cancel this date or all booked occurrences.'
                                            : isRecurring
                                            ? 'This booking covers $groupCount occurrences. You can cancel this date or all booked occurrences.'
                                            : 'This booking is linked to a round trip. You can cancel this leg or the full trip.',
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.black54),
                                      ),
                                    ),
                                  ],

                                  // Cancel buttons
                                  if (bookingId != null &&
                                      status != 'cancelled' &&
                                      status != 'rejected') ...[
                                    const SizedBox(height: 14),
                                    Builder(builder: (context) {
                                      final isRecurringRoundTrip = isRecurring &&
                                          (b['is_round_trip'] == true || b['is_round_trip'] == 1);
                                      if (isRecurringRoundTrip && groupId != null) {
                                        // Three-button layout for recurring round trips
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            OutlinedButton(
                                              onPressed: () => _cancelBooking(bookingId),
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: Colors.red),
                                                foregroundColor: Colors.red,
                                                padding: const EdgeInsets.symmetric(vertical: 11),
                                              ),
                                              child: const Text('Cancel this leg'),
                                            ),
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: () => _cancelThisOccurrence(b),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: Colors.red.shade700),
                                                foregroundColor: Colors.red.shade700,
                                                padding: const EdgeInsets.symmetric(vertical: 11),
                                              ),
                                              child: const Text('Cancel this date'),
                                            ),
                                            const SizedBox(height: 8),
                                            ElevatedButton(
                                              onPressed: () => _cancelBookingGroup(groupId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red.shade700,
                                                padding: const EdgeInsets.symmetric(vertical: 11),
                                              ),
                                              child: const Text('Cancel all', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        );
                                      }
                                      // Default: one or two buttons for non-recurring-round-trip
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _cancelBooking(bookingId),
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: Colors.red),
                                                foregroundColor: Colors.red,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                              ),
                                              child: Text(isRecurring ? 'Cancel this date' : 'Cancel'),
                                            ),
                                          ),
                                          if (groupCount > 1 && groupId != null) ...[
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () => _cancelBookingGroup(groupId),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red.shade700,
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                ),
                                                child: Text(
                                                  isRecurring ? 'Cancel all' : 'Cancel round trip',
                                                  style: const TextStyle(color: Colors.white),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    }),
                                  ],

                                  // Ride in progress banner
                                  if (rideStatus == 'started') ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.orange.shade200),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(
                                              Icons.directions_car_rounded,
                                              color: Colors.orange,
                                              size: 18),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                                'Ride is in progress',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: Colors.orange)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        icon: const Icon(Icons.my_location, size: 16),
                                        label: const Text('Track Ride'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _navy,
                                          padding: const EdgeInsets.symmetric(vertical: 11),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () {
                                          final rideId = b['ride_id'] is int
                                              ? b['ride_id'] as int
                                              : int.tryParse(b['ride_id']?.toString() ?? '') ?? 0;
                                          if (rideId == 0 || bookingId == null) return;
                                          Navigator.pushNamed(
                                            context,
                                            AppRoutes.rideTracking,
                                            arguments: {
                                              'bookingId': bookingId,
                                              'rideId': rideId,
                                              'bookingData': {
                                                'driver_name': b['driver_name'],
                                                'driver_image_url': b['driver_image_url'],
                                                'car_make': b['car_make'],
                                                'car_model': b['car_model'],
                                                'car_color': b['car_color'],
                                                'car_plate': b['car_plate'],
                                                'driver_rating': b['driver_rating'],
                                                'pickup_location': b['pickup_location'],
                                                'destination': b['destination'],
                                                'fare': b['fare'],
                                                'departure_time': b['departure_time'],
                                                'destination_lat': b['destination_lat'],
                                                'destination_lng': b['destination_lng'],
                                              },
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],

                                  // Chat button for accepted bookings
                                  if (status == 'accepted' && bookingId != null) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                        label: const Text('Chat with Driver'),
                                        onPressed: () => Navigator.pushNamed(
                                          context,
                                          AppRoutes.chat,
                                          arguments: {
                                            'bookingId': bookingId,
                                            'counterpartName': b['driver_name']?.toString(),
                                          },
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _navy,
                                          side: const BorderSide(color: _navy),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                      ),
                                    ),
                                  ],

                                  // SOS Emergency Button — only when ride is actively started
                                  if (status == 'accepted' && rideStatus == 'started') ...[
                                    const SizedBox(height: 10),
                                    SosButton(
                                      bookingId: bookingId!,
                                      rideStatus: rideStatus ?? '',
                                      bookingStatus: status ?? '',
                                    ),
                                  ],

                                  // Visual connector for paired legs
                                  if (isPairedLegNext) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: 2,
                                      height: 12,
                                      color: Colors.amber.shade300,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ), // Card
                      ); // InkWell
                    },
                  ),
                ),
    );
  }
}
