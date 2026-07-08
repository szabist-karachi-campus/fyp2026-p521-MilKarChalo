import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api.dart';
import '../../router.dart';
import '../driver_nav/drv_nav_bar.dart';
import '../notifications/appbar_notification_bell.dart';

const Color kNavy = Color(0xFF0A2540);

class DriverDashboardPage extends StatefulWidget {
  const DriverDashboardPage({super.key});

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  int _tab = 0;
  String? _displayName;
  bool _loadingRides = true;
  List<dynamic> _upcomingRides = [];
  List<dynamic> _historyRides = [];
  int _bookingRequestCount = 0;
  Map<int, List<dynamic>> _recurringOccurrences = {};
  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
    _loadDriverData();
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

  Future<void> _loadDriverData() async {
    setState(() => _loadingRides = true);
    try {
      final rides = await Api.getMyRides();
      final requests = await Api.getBookingRequests();
      final upcoming = <Map<String, dynamic>>[];
      final history = <Map<String, dynamic>>[];

      for (final item in rides) {
        final ride = item as Map;
        final status = ride['status']?.toString().toLowerCase() ?? '';
        final occurrenceStatus = ride['occurrence_status']?.toString().toLowerCase();

        // For recurring rides use occurrence_status; for non-recurring use ride status
        final effectiveStatus = occurrenceStatus ?? status;

        if (effectiveStatus == 'active' || effectiveStatus == 'started') {
          upcoming.add(Map<String, dynamic>.from(ride));
        } else if (effectiveStatus == 'completed' ||
            effectiveStatus == 'canceled' ||
            effectiveStatus == 'cancelled') {
          history.add(Map<String, dynamic>.from(ride));
        }
      }

      if (!mounted) return;
      setState(() {
        _upcomingRides = upcoming;
        _historyRides = history;
        _bookingRequestCount = requests.length;
        _loadingRides = false;
      });
      // Load occurrences for recurring rides
      await _loadRecurringOccurrences([...upcoming, ...history]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRides = false);
      debugPrint('⚠️ Failed to load driver data: $e');
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

  // --------- Responsive helpers ----------
  double _scale(BuildContext c) => (MediaQuery.sizeOf(c).width / 375).clamp(0.85, 1.15);
  double _gap(BuildContext c, double base) => base * _scale(c);
  double _hPad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return math.max(16, math.min(24, w * 0.06));
  }

  // Height needed for each ride card list row (computed from card internals)
  double _rideListHeight(BuildContext c) {
    final s = _scale(c);
    final mapH = (92 * s).clamp(76, 104).toDouble(); // map box height inside card
    // padding (top+bottom 12+12) + gaps + two text lines + button (44) + badges (up to 40 for two badges)
    // add a small safety buffer so we never clip on larger text
    return mapH + 180; // increased to accommodate round trip and recurring badges
  }

  @override
  Widget build(BuildContext context) {
    final pad = _hPad(context);

    // Clamp text scale to keep layout stable on large accessibility fonts
    final media = MediaQuery.of(context);
    final clamped = media.copyWith(
      textScaler: media.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2),
    );

    return MediaQuery(
      data: clamped,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: kNavy,
          elevation: 0,
          title: Text(
            'Good morning, ${_displayName ?? 'Driver'}!',
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
          child: RefreshIndicator(
            onRefresh: _loadDriverData,
            child: ListView(
            padding: EdgeInsets.fromLTRB(pad, _gap(context, 14), pad, _gap(context, 24)),
            children: [
              SizedBox(height: _gap(context, 16)),

              // Booking requests shortcut
              _BookingRequestsCard(
                count: _bookingRequestCount,
                onTap: () async {
                  await Navigator.pushNamed(context, AppRoutes.bookingRequests);
                  if (!mounted) return;
                  _loadDriverData();
                },
              ),

              SizedBox(height: _gap(context, 16)),

              SizedBox(height: _gap(context, 18)),

              // Upcoming Rides + See All
              Row(
                children: [
                  Text(
                    'Upcoming Rides',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await Navigator.pushNamed(context, AppRoutes.upcomingRides);
                      if (!mounted) return;
                      _loadDriverData();
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
                const _RideEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No upcoming rides',
                  subtitle: 'Posted rides that are still active and in the future will appear here.',
                )
              else
                SizedBox(
                  height: _rideListHeight(context),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _upcomingRides.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final ride = _upcomingRides[i] as Map;
                      final rideId = ride['ride_id'] is int
                          ? ride['ride_id'] as int
                          : int.tryParse(ride['ride_id']?.toString() ?? '') ?? 0;
                      final occurrenceId = ride['occurrence_id'] is int
                          ? ride['occurrence_id'] as int
                          : int.tryParse(ride['occurrence_id']?.toString() ?? '');
                      final isRecurring = ride['is_recurring'] == true ||
                          ride['is_recurring'] == 1 ||
                          ride['is_recurring'] == '1';
                      return _RideCard(
                        mapLabel: '${ride['pickup_location'] ?? 'Ride'} → ${ride['destination'] ?? ''}'.trim(),
                        title: '${ride['available_seats'] ?? '-'} seats left • Rs ${ride['fare'] ?? '-'}',
                        pickup: _formatDepartureFromRide(ride),
                        hasRoundTrip: ride['return_ride_id'] != null || ride['is_round_trip'] == true || ride['is_round_trip'] == 1,
                        isRecurring: isRecurring,
                        isStarted: (ride['status']?.toString().toLowerCase() == 'started' ||
                            ride['occurrence_status']?.toString().toLowerCase() == 'started'),
                        onNavigate: () async {
                          final effectiveStatus = ride['occurrence_status']?.toString().toLowerCase()
                              ?? ride['status']?.toString().toLowerCase() ?? '';
                          if (effectiveStatus == 'started') {
                            // Go directly to live tracking
                            Navigator.pushNamed(
                              context,
                              AppRoutes.rideTracking,
                              arguments: {
                                'bookingId': 0, // driver view — bookingId is unused on driver side
                                'rideId': rideId,
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
                          } else {
                            await Navigator.pushNamed(
                              context,
                              AppRoutes.driverRideDetail,
                              arguments: {'rideId': rideId, 'occurrenceId': occurrenceId},
                            );
                            if (!mounted) return;
                            _loadDriverData();
                          }
                        },
                        scale: _scale(context),
                      );
                    },
                  ),
                ),

              SizedBox(height: _gap(context, 20)),

              // History + See All
              Row(
                children: [
                  Text(
                    'Ride History',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await Navigator.pushNamed(context, AppRoutes.rideHistory);
                      if (!mounted) return;
                      _loadDriverData();
                    },
                    child: const Text('See All'),
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
                const _RideEmptyState(
                  icon: Icons.history_outlined,
                  title: 'No ride history',
                  subtitle: 'Past, completed, cancelled, and inactive rides appear here.',
                )
              else
                ..._historyRides.map((ride) => _HistoryTile(
                  title: '${ride['pickup_location'] ?? '-'} → ${ride['destination'] ?? '-'}',
                  subtitle: '${_rideStatusLabel(ride['status']?.toString())} • ${_formatDepartureFromRide(ride)}',
                  price: 'Rs ${double.tryParse(ride['fare']?.toString() ?? '')?.toStringAsFixed(0) ?? '-'}',
                )),
            ],
          ),
        ),
      ),

        // Bottom navigation
        bottomNavigationBar: DriverNavBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            if (i == 1) {
              Navigator.pushNamed(context, AppRoutes.postRide);
            } else if (i == 2) {
              Navigator.pushNamed(context, AppRoutes.upcomingRides);
            } else if (i == 3) {
              Navigator.pushNamed(context, AppRoutes.profile);
            } else {
              setState(() => _tab = i);
            }
          },
        ),
      ),
    );
  }
}

// ------- Earnings Card -------
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = (14 * scale).clamp(12, 18).toDouble();

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Earning Dashboard',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              )),
          const SizedBox(height: 10),

          // Numbers + mini chart (no overflow)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Left numbers
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's Earnings",
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text('\$112.50',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        )),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Weekly total: \$345.60',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54)),
                        const SizedBox(width: 6),
                        Text('↑ 12%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

        ],
      ),
    );
  }
}

// ------- Upcoming Ride Card -------
class _RideCard extends StatelessWidget {
  const _RideCard({
    required this.mapLabel,
    required this.title,
    required this.pickup,
    required this.onNavigate,
    required this.scale,
    required this.hasRoundTrip,
    required this.isRecurring,
    this.isStarted = false,
  });

  final String mapLabel;
  final String title;
  final String pickup;
  final VoidCallback onNavigate;
  final double scale;
  final bool hasRoundTrip;
  final bool isRecurring;
  final bool isStarted;

  @override
  Widget build(BuildContext context) {
    final w = (280 * scale).clamp(240, 320).toDouble();

    return Container(
      width: w,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          // Map placeholder (slightly shorter to save space)
          Container(
            height: (80 * scale).clamp(64, 92).toDouble(),
            decoration: BoxDecoration(
              color: const Color(0xFFE8ECF7),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(mapLabel, style: const TextStyle(color: Colors.black54)),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (hasRoundTrip) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: kNavy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.loop, size: 12, color: kNavy),
                  const SizedBox(width: 4),
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
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.repeat, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
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
          const SizedBox(height: 2),
          Text(
            pickup,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54),
          ),
          const Spacer(),
          SizedBox(
            height: 44, // fixed height avoids vertical squeeze
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: isStarted ? Colors.orange.shade700 : kNavy),
              onPressed: onNavigate,
              icon: Icon(
                isStarted ? Icons.my_location : Icons.directions,
                size: 16,
                color: Colors.white,
              ),
              label: Text(
                isStarted ? 'Track Ride' : 'Navigate',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------- History List Item -------
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
          // Icon box
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_taxi_outlined, size: 20, color: Colors.black54),
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

String _rideStatusLabel(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'active':
      return 'Active';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Unknown';
  }
}

String _formatDeparture(String? raw) {
  try {
    final dt = DateTime.parse(raw ?? '').toLocal();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.month}/${dt.day}/${dt.year} • $hour:$minute $ampm';
  } catch (_) {
    return raw ?? '-';
  }
}

String _formatDepartureFromRide(Map ride) {
  final isRecurring = ride['is_recurring'] == true || 
                     ride['is_recurring'] == 1 || 
                     ride['is_recurring'] == '1';
  
  // For recurring rides, try to use occurrence_date/departure_datetime if available
  if (isRecurring && ride['occurrence_date'] != null && ride['departure_datetime'] != null) {
    try {
      // departure_datetime is already in local/server time, don't call toLocal()
      final dt = DateTime.parse(ride['departure_datetime']?.toString() ?? '');
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.month}/${dt.day}/${dt.year} • $hour:$minute $ampm';
    } catch (_) {}
  }
  
  // Otherwise, use template departure_time
  return _formatDeparture(ride['departure_time']?.toString());
}

class _BookingRequestsCard extends StatelessWidget {
  const _BookingRequestsCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kNavy,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.inbox, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Booking Requests', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$count pending request(s)', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _RideEmptyState extends StatelessWidget {
  const _RideEmptyState({required this.icon, required this.title, required this.subtitle});

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
