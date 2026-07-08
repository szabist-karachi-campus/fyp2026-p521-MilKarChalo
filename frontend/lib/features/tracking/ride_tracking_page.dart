import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../core/api.dart';
import '../../core/widgets/user_avatar.dart';
import '../../router.dart';
import '../chat/chat_page.dart';
import '../sos/sos_button.dart';

const Color _navy = Color(0xFF0A2540);

class RideTrackingPage extends StatefulWidget {
  final int bookingId;
  final int rideId;

  /// When true, this is the driver's view — broadcasts location instead of
  /// receiving it, and shows End Ride instead of SOS.
  final bool isDriver;

  /// Pre-loaded booking data (driver info, vehicle, locations, coords, etc.)
  final Map<String, dynamic> bookingData;

  const RideTrackingPage({
    super.key,
    required this.bookingId,
    required this.rideId,
    this.isDriver = false,
    required this.bookingData,
  });

  @override
  State<RideTrackingPage> createState() => _RideTrackingPageState();
}

class _RideTrackingPageState extends State<RideTrackingPage> {
  io.Socket? _socket;
  final MapController _mapController = MapController();

  LatLng? _driverLocation;   // live driver position
  LatLng? _myLocation;       // current user's position (used for passenger marker)
  LatLng? _destLatLng;

  List<LatLng> _routePoints = [];

  String _rideStatus = 'started';
  String _statusLabel = 'Ride in Progress';
  String _eta = '—';
  String _distance = '—';

  bool _locationLoaded = false;
  bool _etaInProgress = false;
  bool _endingRide = false;

  Timer? _etaTimer;
  Timer? _driverBroadcastTimer; // driver-only: sends GPS every 5 s

  @override
  void initState() {
    super.initState();

    _destLatLng = _parseLatLng(
      widget.bookingData['destination_lat'],
      widget.bookingData['destination_lng'],
    );

    _connectSocket();
    _getMyLocation();

    if (widget.isDriver) {
      // Driver broadcasts their location every 5 s
      _driverBroadcastTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _broadcastDriverLocation());
    } else {
      // Passenger refreshes ETA every 30 s
      _etaTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) { if (_driverLocation != null && mounted) _recalcEta(); });
    }
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _mapController.dispose();
    _etaTimer?.cancel();
    _driverBroadcastTimer?.cancel();
    super.dispose();
  }

  // ── Socket ─────────────────────────────────────────────────────────────────

  void _connectSocket() {
    final token = Api.bearerToken;
    _socket = io.io(
      ApiConfig.base,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('join_tracking', {'rideId': widget.rideId});
      // Driver: broadcast position immediately on connect
      if (widget.isDriver) _broadcastDriverLocation();
    });

    // Both driver and passenger receive location_update so driver sees their
    // own position reflected on map too
    _socket!.on('location_update', (data) {
      if (!mounted) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      final newLoc = LatLng(lat, lng);
      setState(() {
        _driverLocation = newLoc;
        _locationLoaded = true;
      });

      _mapController.move(newLoc, _mapController.camera.zoom);

      if (!widget.isDriver) {
        _recalcEta();
        _updateStatusFromDistance();
      } else {
        // Driver: update status from their own position
        _updateStatusFromDistance();
      }
    });

    _socket!.on('ride_ended', (_) {
      if (!mounted) return;
      if (!widget.isDriver) {
        setState(() {
          _rideStatus = 'completed';
          _statusLabel = 'Ride Completed';
        });
        _showRideEndedBanner();
      }
    });

    _socket!.onReconnect((_) {
      _socket!.emit('join_tracking', {'rideId': widget.rideId});
    });
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<void> _getMyLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) {
        setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
        // If driver, also set initial driver location on map
        if (widget.isDriver) {
          setState(() {
            _driverLocation = _myLocation;
            _locationLoaded = true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _broadcastDriverLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      // Update own map position immediately — don't wait for socket echo
      if (mounted) {
        final newLoc = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _driverLocation = newLoc;
          _locationLoaded = true;
        });
        _mapController.move(newLoc, _mapController.camera.zoom);
        _updateStatusFromDistance();
      }
      _socket?.emit('driver_location', {
        'rideId': widget.rideId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      });
    } catch (_) {}
  }

  Future<void> _recalcEta() async {
    if (_driverLocation == null || _destLatLng == null) return;
    if (_etaInProgress) return;
    _etaInProgress = true;

    try {
      final resp = await Api.getEta(
        originLat: _driverLocation!.latitude,
        originLng: _driverLocation!.longitude,
        destLat: _destLatLng!.latitude,
        destLng: _destLatLng!.longitude,
      );
      if (!mounted) return;

      final data = resp['data'] as Map?;
      if (data == null) return;

      final durationText = data['duration_text']?.toString() ?? '—';
      final distanceText = data['distance_text']?.toString() ?? '—';
      final encodedPolyline = data['polyline']?.toString() ?? '';

      List<LatLng> points = [];
      if (encodedPolyline.isNotEmpty) {
        final result = PolylinePoints().decodePolyline(encodedPolyline);
        points = result.map((p) => LatLng(p.latitude, p.longitude)).toList();
      }

      setState(() {
        _eta = durationText;
        _distance = distanceText;
        _routePoints = points;
      });
    } catch (_) {
    } finally {
      _etaInProgress = false;
    }
  }

  void _updateStatusFromDistance() {
    if (_driverLocation == null || _destLatLng == null) return;
    final distMeters = const Distance().as(
        LengthUnit.Meter, _driverLocation!, _destLatLng!);
    final newLabel =
        distMeters < 300 ? 'Approaching Destination' : 'Ride in Progress';
    if (newLabel != _statusLabel && mounted) {
      setState(() => _statusLabel = newLabel);
      if (newLabel == 'Approaching Destination') {
        _showMilestoneSnackBar(widget.isDriver
            ? 'You are approaching the destination!'
            : 'Driver is approaching your destination!');
      }
    }
  }

  LatLng? _parseLatLng(dynamic lat, dynamic lng) {
    final la = (lat is num) ? lat.toDouble() : double.tryParse(lat?.toString() ?? '');
    final lo = (lng is num) ? lng.toDouble() : double.tryParse(lng?.toString() ?? '');
    if (la == null || lo == null) return null;
    return LatLng(la, lo);
  }

  // ── Driver: end ride ───────────────────────────────────────────────────────

  /// Intercept back navigation — ask the user to confirm before leaving an
  /// active ride. The ride keeps running on the server either way.
  Future<bool> _onWillPop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isDriver ? 'Leave ride screen?' : 'Leave tracking?'),
        content: Text(widget.isDriver
            ? 'The ride is still in progress. You can return to this screen from your upcoming rides. Do you want to leave?'
            : 'The ride is still in progress. You can return to tracking from your dashboard or My Bookings. Do you want to leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _endRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('End Ride?'),
        content: const Text('This will complete the ride for all passengers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Ride', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _endingRide = true);
    try {
      await Api.endDriverRide(widget.rideId);
      _driverBroadcastTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _rideStatus = 'completed';
        _statusLabel = 'Ride Completed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ride ended successfully'), backgroundColor: Colors.green),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.driverRideDetail,
        (r) => r.isFirst,
        arguments: {'rideId': widget.rideId},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not end ride: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _endingRide = false);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  void _showMilestoneSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _navy,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showRideEndedBanner() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 28),
          SizedBox(width: 8),
          Text('Ride Completed!'),
        ]),
        content: const Text(
            'Your ride has ended. View trip summary and rate your driver.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.myBookings,
                (r) => r.isFirst,
              );
            },
            child: const Text('View Summary',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _shareRide() {
    final pickup = widget.bookingData['pickup_location'] ?? '-';
    final dest = widget.bookingData['destination'] ?? '-';
    final driver = widget.bookingData['driver_name'] ?? 'Driver';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Share: $driver is driving from $pickup → $dest'),
      action: SnackBarAction(label: 'OK', onPressed: () {}),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final b = widget.bookingData;
    final driverName = b['driver_name']?.toString() ?? 'Driver';
    final driverImage = b['driver_image_url']?.toString();
    final carMake = b['car_make']?.toString() ?? '';
    final carModel = b['car_model']?.toString() ?? '';
    final carColor = b['car_color']?.toString() ?? '';
    final carPlate = b['car_plate']?.toString() ?? '';
    final rating = () {
      final raw = b['driver_rating'];
      if (raw == null) return '—';
      final n = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
      return n != null ? n.toStringAsFixed(1) : '—';
    }();
    final pickup = b['pickup_location']?.toString() ?? '-';
    final destination = b['destination']?.toString() ?? '-';

    final center = _driverLocation ??
        _myLocation ??
        const LatLng(33.6844, 73.0479);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.milkarchalo.app',
              ),
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.5,
                      color: _navy.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_driverLocation != null)
                    Marker(
                      point: _driverLocation!,
                      width: 48,
                      height: 48,
                      child: _DriverMarker(),
                    ),
                  // Passenger marker (only for passenger view)
                  if (!widget.isDriver && _myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 40,
                      height: 40,
                      child: _PassengerMarker(),
                    ),
                  if (_destLatLng != null)
                    Marker(
                      point: _destLatLng!,
                      width: 40,
                      height: 56,
                      child: const Icon(Icons.location_pin,
                          color: Colors.red, size: 40),
                    ),
                ],
              ),
            ],
          ),

          // ── Top status bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  16, MediaQuery.of(context).padding.top + 8, 16, 12),
              decoration: BoxDecoration(
                color: _navy,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () async {
                      final shouldPop = await _onWillPop();
                      if (shouldPop && mounted) Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (widget.isDriver) ...[
                              const Icon(Icons.broadcast_on_personal,
                                  color: Colors.greenAccent, size: 14),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _statusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          widget.isDriver
                              ? 'Broadcasting your location to passengers'
                              : 'ETA: $_eta  ·  $_distance',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.white),
                    onPressed: () {
                      final center = _driverLocation ?? _myLocation;
                      if (center != null) {
                        _mapController.move(
                            center, _mapController.camera.zoom);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom info card ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, -4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Driver row (shows in both views)
                        Row(
                          children: [
                            UserAvatar(imageUrl: driverImage, radius: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isDriver ? 'You are driving' : driverName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  Row(children: [
                                    const Icon(Icons.star_rounded,
                                        color: Colors.amber, size: 16),
                                    const SizedBox(width: 2),
                                    Text(rating,
                                        style:
                                            const TextStyle(fontSize: 13)),
                                    const SizedBox(width: 10),
                                    Text(
                                      '$carColor $carMake $carModel',
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 13),
                                    ),
                                  ]),
                                  Text(carPlate,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          letterSpacing: 1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RouteRow(pickup: pickup, destination: destination),
                        const SizedBox(height: 12),

                        // ── Driver view: End Ride button + SOS ───────────────────
                        if (widget.isDriver) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: _endingRide
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.stop_circle_outlined,
                                      size: 18),
                              label: Text(
                                  _endingRide ? 'Ending...' : 'End Ride'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _endingRide ? null : _endRide,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SosButton(
                            bookingId: widget.bookingId,
                            rideStatus: _rideStatus,
                            bookingStatus: 'accepted',
                          ),
                        ]

                        // ── Passenger view: Chat + Share + SOS ────────────
                        else ...[
                          Row(children: [
                            _ActionButton(
                              icon: Icons.chat_bubble_outline,
                              label: 'Chat',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    bookingId: widget.bookingId,
                                    counterpartName: driverName,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: _shareRide,
                            ),
                          ]),
                          const SizedBox(height: 10),
                          SosButton(
                            bookingId: widget.bookingId,
                            rideStatus: _rideStatus,
                            bookingStatus: 'accepted',
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Waiting for location placeholder ──────────────────────────────
          if (!_locationLoaded)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  const CircularProgressIndicator(color: _navy),
                  const SizedBox(height: 12),
                  Text(
                    widget.isDriver
                        ? 'Getting your location…'
                        : 'Waiting for driver location…',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        shadows: [
                          Shadow(
                              color: Colors.white.withValues(alpha: 0.9),
                              blurRadius: 4)
                        ]),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _DriverMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _navy,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)
        ],
      ),
      child: const Icon(Icons.directions_car, color: Colors.white, size: 24),
    );
  }
}

class _PassengerMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 20),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final String pickup;
  final String destination;
  const _RouteRow({required this.pickup, required this.destination});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: [
            const Icon(Icons.circle, size: 10, color: Colors.green),
            Container(width: 2, height: 20, color: Colors.grey.shade300),
            const Icon(Icons.location_pin, size: 18, color: Colors.red),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pickup,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text(destination,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          side: const BorderSide(color: _navy),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
