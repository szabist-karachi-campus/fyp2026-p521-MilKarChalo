import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api.dart';
import '../profile/pages/profile_page.dart';
import '../passenger_nav/pass_nav_bar.dart';
import '../../router.dart';
import '../notifications/appbar_notification_bell.dart';

const Color kNavy = Color(0xFF0A2540);

class PassengerDashboardPage extends StatefulWidget {
  const PassengerDashboardPage({super.key});

  @override
  State<PassengerDashboardPage> createState() => _PassengerDashboardPageState();
}

class _PassengerDashboardPageState extends State<PassengerDashboardPage>
    with RouteAware {
  int _tab = 0;
  String? _displayName;
  bool _loadingRides = true;
  List<dynamic> _upcomingRides = [];
  List<dynamic> _historyRides = [];

  // RouteObserver for auto-refresh when returning from a sub-page
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
    _loadRides();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Called when the user pops back to this page from a sub-route.
  @override
  void didPopNext() {
    _loadRides();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _displayName = prefs.getString('user_name');
      });
    } catch (e) {
      debugPrint('⚠️ Failed to load name: $e');
    }
  }

  Future<void> _loadRides() async {
    setState(() => _loadingRides = true);
    try {
      final bookings = await Api.getMyBookings();
      final upcoming = <Map<String, dynamic>>[];
      final history  = <Map<String, dynamic>>[];

      for (final item in bookings) {
        final booking = item as Map;
        final bookingStatus = booking['booking_status']?.toString().toLowerCase() ?? '';
        final rideStatus    = booking['ride_status']?.toString().toLowerCase() ?? '';

        final isUpcoming = bookingStatus == 'accepted' &&
            (rideStatus == 'active' || rideStatus == 'started');

        final isHistory = bookingStatus == 'completed' ||
            bookingStatus == 'cancelled' ||
            bookingStatus == 'canceled' ||
            bookingStatus == 'rejected' ||
            rideStatus == 'completed' ||
            rideStatus == 'cancelled' ||
            rideStatus == 'canceled';

        if (isUpcoming) {
          upcoming.add(Map<String, dynamic>.from(booking));
        } else if (isHistory) {
          history.add(Map<String, dynamic>.from(booking));
        }
      }

      if (!mounted) return;
      setState(() {
        _upcomingRides = upcoming;
        _historyRides  = history;
        _loadingRides  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRides = false);
      debugPrint('⚠️ Failed to load passenger rides: $e');
    }
  }

  // --------- Responsive helpers ----------
  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.85, 1.15);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(24, w * 0.06));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = _hPad(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: kNavy,
        elevation: 0,
        title: Text(
          'Good morning, ${_displayName ?? 'Passenger'}!',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        actions: const [
          AppBarNotificationBell(),
          SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _tab == 3
            ? const ProfilePage()
            : RefreshIndicator(
                onRefresh: _loadRides,
                child: ListView(
                padding: EdgeInsets.fromLTRB(pad, _gap(context, 14), pad, _gap(context, 24)),
                children: [
                  SizedBox(height: _gap(context, 12)),

                  // Search bar
                  TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Where are you going?',
                      prefixIcon: const Icon(Icons.search_rounded, color: kNavy),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.search);
                    },
                  ),

                  SizedBox(height: _gap(context, 18)),

                  // Upcoming rides header (no trailing avatars)
                  Row(
                    children: [
                      Text(
                        'Upcoming Rides',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, AppRoutes.upcomingRides);
                        },
                        child: const Text('See All'),
                      ),
                    ],
                  ),
                  SizedBox(height: _gap(context, 10)),

                  if (_loadingRides)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_upcomingRides.isEmpty)
                    _EmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No upcoming rides',
                      subtitle: 'Accepted rides with future departure times will show here.',
                    )
                  else
                    SizedBox(
                      height: _gap(context, 240),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _upcomingRides.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final ride = _upcomingRides[i] as Map;
                          final isRecurring = ride['is_recurring'] == true || 
                                             ride['is_recurring'] == 1 || 
                                             ride['is_recurring'] == '1';

                          // For recurring rides: use departure_datetime from the booked occurrence
                          // For non-recurring: use departure_time from the ride template
                          final displayTime = isRecurring && ride['departure_datetime'] != null
                              ? _formatOccurrenceDeparture(ride['departure_datetime']?.toString())
                              : _formatDeparture(ride['departure_time']?.toString());
                          
                          return _UpcomingCard(
                            name: ride['driver_name']?.toString() ?? 'Driver',
                            car: '${ride['car_make'] ?? ''} ${ride['car_model'] ?? ''}'.trim(),
                            time: displayTime,
                            address: '${ride['pickup_location'] ?? '-'} → ${ride['destination'] ?? '-'}',
                            rideStatus: ride['ride_status']?.toString().toLowerCase() ?? '',
                            hasRoundTrip: ride['return_ride_id'] != null || ride['is_round_trip'] == true || ride['is_round_trip'] == 1,
                            isRecurring: isRecurring,
                            onDetails: () {
                              final rideStatus = ride['ride_status']?.toString().toLowerCase() ?? '';
                              // If the ride is already started, go directly to live tracking
                              if (rideStatus == 'started') {
                                final rideId = ride['ride_id'] is int
                                    ? ride['ride_id'] as int
                                    : int.tryParse(ride['ride_id']?.toString() ?? '') ?? 0;
                                final bookingId = ride['booking_id'] is int
                                    ? ride['booking_id'] as int
                                    : int.tryParse(ride['booking_id']?.toString() ?? '') ?? 0;
                                if (rideId != 0 && bookingId != 0) {
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.rideTracking,
                                    arguments: {
                                      'bookingId': bookingId,
                                      'rideId': rideId,
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
                                  return;
                                }
                              }
                              Navigator.pushNamed(
                                context,
                                AppRoutes.rideDetail,
                                arguments: {
                                  'id': ride['ride_id'],
                                  'pickup_location': ride['pickup_location'],
                                  'destination': ride['destination'],
                                  'departure_time': ride['departure_time'],
                                  'fare': ride['fare'],
                                  'driver_name': ride['driver_name'],
                                  'driver_image_url': ride['driver_image_url'],
                                  'car_make': ride['car_make'],
                                  'car_model': ride['car_model'],
                                  'car_color': ride['car_color'],
                                  'car_plate': ride['car_plate'],
                                  'booking_status': ride['booking_status'],
                                  'read_only': true,
                                },
                              );
                            },
                            scale: _scale(context),
                          );
                        },
                      ),
                    ),

                  SizedBox(height: _gap(context, 20)),

                  // Ride History header
                  Row(
                    children: [
                      Text(
                        'Ride History',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, AppRoutes.rideHistory);
                        },
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                  SizedBox(height: _gap(context, 8)),

                  if (_loadingRides)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_historyRides.isEmpty)
                    _EmptyState(
                      icon: Icons.history_outlined,
                      title: 'No ride history',
                      subtitle: 'Completed, cancelled, rejected, and past accepted rides appear here.',
                    )
                  else
                    ..._historyRides.map((h) => _HistoryTile(
                          title: h['destination']?.toString() ?? '-',
                          subtitle:
                              '${_statusLabel(h['booking_status']?.toString(), rideStatus: h['ride_status']?.toString())} • ${_formatDeparture(h['departure_time']?.toString())}',
                          price: 'Rs ${double.tryParse(h['fare']?.toString() ?? '')?.toStringAsFixed(0) ?? '-'}',
                        )),
                ],
              ),
            ),
      ),

      // Bottom navigation
      bottomNavigationBar: PassengerNavBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == 1) {
            Navigator.pushNamed(context, AppRoutes.search);
          } else if (i == 2) {
            Navigator.pushNamed(context, AppRoutes.myBookings);
          } else if (i == 3) {
            Navigator.pushNamed(context, AppRoutes.profile);
          } else if (i == 4) {
            Navigator.pushNamed(context, AppRoutes.notifications);
          } else {
            setState(() => _tab = i);
          }
        },
      ),
    );
  }

}

extension on _PassengerDashboardPageState {
  String _formatDeparture(String? raw) {
    try {
      final dt = DateTime.parse(raw ?? '').toLocal();
      return '${dt.month}/${dt.day}/${dt.year} • ${TimeOfDay.fromDateTime(dt).format(context)}';
    } catch (_) {
      return raw ?? '-';
    }
  }

  String _formatOccurrenceDeparture(String? raw) {
    try {
      // "YYYY-MM-DD HH:MM:SS" — already local time from DATE_FORMAT in backend
      // replaceFirst ensures DateTime.parse works on all platforms
      final dt = DateTime.parse((raw ?? '').replaceFirst(' ', 'T'));
      return '${dt.month}/${dt.day}/${dt.year} • ${TimeOfDay.fromDateTime(dt).format(context)}';
    } catch (_) {
      return raw ?? '-';
    }
  }

  String _statusLabel(String? status, {String? rideStatus}) {
    // If the ride itself was cancelled (e.g. driver cancelled), show Cancelled
    // regardless of the booking status value
    if ((rideStatus ?? '').toLowerCase() == 'cancelled') return 'Cancelled';

    switch ((status ?? '').toLowerCase()) {
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      case 'completed':
        return 'Completed';
      case 'pending':
        return 'Pending';
      default:
        return status ?? 'Unknown';
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ------- Widgets -------
class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.name,
    required this.car,
    required this.time,
    required this.address,
    required this.rideStatus,
    required this.onDetails,
    required this.scale,
    required this.hasRoundTrip,
    required this.isRecurring,
  });

  final String name;
  final String car;
  final String time;
  final String address;
  final String rideStatus;
  final VoidCallback onDetails;
  final double scale;
  final bool hasRoundTrip;
  final bool isRecurring;

  @override
  Widget build(BuildContext context) {
    final w = (280 * scale).clamp(240, 320).toDouble();
    final inProgress = rideStatus == 'started';

    return Container(
      width: w,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          // Status chip
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: inProgress ? Colors.orange.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: inProgress ? Colors.orange.shade200 : Colors.green.shade200,
                  ),
                ),
                child: Text(
                  inProgress ? 'In Progress' : 'Upcoming',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: inProgress ? Colors.orange : Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Driver name
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(car, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 4),
          Text(time, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Text(address,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (hasRoundTrip) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: kNavy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.loop, size: 12, color: kNavy),
                  const SizedBox(width: 5),
                  const Text(
                    '🔄 Round Trip',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: kNavy,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isRecurring) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.repeat, size: 12, color: Colors.amber),
                  const SizedBox(width: 5),
                  const Text(
                    '🔁 Recurring',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kNavy),
              onPressed: onDetails,
              icon: Icon(
                inProgress ? Icons.my_location : Icons.info_outline,
                size: 16,
                color: Colors.white,
              ),
              label: Text(
                inProgress ? 'Track Ride' : 'View Details',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.title,
    required this.subtitle,
    required this.price,
  });

  final String title;
  final String subtitle;
  final String price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // This is an icon box (not an avatar)
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_outlined, size: 20, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(price, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
