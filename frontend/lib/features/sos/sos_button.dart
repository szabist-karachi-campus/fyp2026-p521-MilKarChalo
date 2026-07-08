import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/api.dart';

const Color _sosRed = Color(0xFFD32F2F);
const Color _sosActiveOrange = Color(0xFFE65100);

/// Drop-in SOS widget. Pass the booking details; it handles the rest.
/// [bookingId] — the booking this SOS is associated with.
/// [rideStatus] — current ride status string (active / started / etc.).
/// [bookingStatus] — booking status string (accepted / etc.).
class SosButton extends StatefulWidget {
  final int bookingId;
  final String rideStatus;
  final String bookingStatus;

  const SosButton({
    super.key,
    required this.bookingId,
    required this.rideStatus,
    required this.bookingStatus,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> {
  bool _sosActive = false;
  int? _sosId;
  Timer? _locationTimer;
  bool _activating = false;
  bool _deactivating = false;

  static const _eligibleRideStatuses = ['active', 'started', 'driver_arrived'];

  bool get _isEligible =>
      widget.bookingStatus == 'accepted' &&
      _eligibleRideStatuses.contains(widget.rideStatus.toLowerCase());

  @override
  void initState() {
    super.initState();
    if (_isEligible) _checkExistingSos();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkExistingSos() async {
    try {
      final resp = await Api.getActiveSos(widget.bookingId);
      final data = resp['data'];
      if (data != null && data['status'] == 'active') {
        final id = data['id'];
        if (mounted) {
          setState(() {
            _sosActive = true;
            _sosId = id is int ? id : int.tryParse(id.toString());
          });
          _startLocationUpdates();
        }
      }
    } catch (_) {}
  }

  Future<Position?> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[SOS] Location services are disabled on device');
        return null;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      debugPrint('[SOS] Location permission status: $perm');
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        debugPrint('[SOS] After request: $perm');
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        debugPrint('[SOS] Location permission denied');
        return null;
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        debugPrint('[SOS] Got position: ${pos.latitude}, ${pos.longitude}');
        return pos;
      } catch (e) {
        debugPrint('[SOS] getCurrentPosition failed: $e — trying last known');
        final last = await Geolocator.getLastKnownPosition();
        debugPrint('[SOS] Last known: ${last?.latitude}, ${last?.longitude}');
        return last;
      }
    } catch (e) {
      debugPrint('[SOS] _getLocation error: $e');
      return null;
    }
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    // Send every 60 seconds — frequent enough to track, not SMS-spammy
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!_sosActive || _sosId == null) {
        _locationTimer?.cancel();
        return;
      }
      final pos = await _getLocation();
      if (pos != null && _sosId != null) {
        try {
          await Api.updateSosLocation(_sosId!, pos.latitude, pos.longitude);
        } catch (_) {}
      }
    });
  }

  Future<void> _activateSos() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: _sosRed, size: 28),
            SizedBox(width: 8),
            Text('Activate SOS?', style: TextStyle(color: _sosRed)),
          ],
        ),
        content: const Text(
          'This will immediately alert your emergency contacts and begin sharing your live location.\n\nOnly activate in a real emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _sosRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Activate SOS',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _activating = true);

    try {
      final pos = await _getLocation();
      debugPrint('[SOS] GPS result: ${pos?.latitude}, ${pos?.longitude}');

      final resp = await Api.activateSos(
        bookingId: widget.bookingId,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );

      final data = resp['data'];
      final id = data?['sos_id'];

      if (!mounted) return;
      setState(() {
        _sosActive = true;
        _sosId = id is int ? id : int.tryParse(id?.toString() ?? '');
        _activating = false;
      });

      _startLocationUpdates();

      final contactsNotified = data?['contacts_notified'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(contactsNotified > 0
              ? 'Emergency mode activated. $contactsNotified contact(s) notified. Sharing live location.'
              : 'Emergency mode activated. Sharing live location. (No emergency contacts configured.)'),
          backgroundColor: _sosRed,
          duration: const Duration(seconds: 5),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _activating = false);

      if (e.statusCode == 409) {
        // Already active — treat as resume
        await _checkExistingSos();
        return;
      }

      String msg = e.message;
      if (e.message.contains('no emergency contacts') ||
          e.message.contains('No emergency contacts')) {
        msg = 'SOS activated but you have no emergency contacts. Please add them in your profile.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _activating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not activate SOS. Check your connection.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deactivateSos() async {
    if (_sosId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Emergency Mode?'),
        content: const Text(
            'This will stop live location sharing and close the SOS session.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Active')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.grey),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End SOS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deactivating = true);
    try {
      await Api.deactivateSos(_sosId!);
      _locationTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _sosActive = false;
        _sosId = null;
        _deactivating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency mode ended.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deactivating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEligible) return const SizedBox.shrink();

    if (_sosActive) {
      return _SosActiveWidget(
        deactivating: _deactivating,
        onDeactivate: _deactivateSos,
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: _activating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sos_rounded, size: 22),
        label: Text(_activating ? 'Activating…' : 'SOS Emergency'),
        onPressed: _activating ? null : _activateSos,
        style: ElevatedButton.styleFrom(
          backgroundColor: _sosRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _SosActiveWidget extends StatelessWidget {
  final bool deactivating;
  final VoidCallback onDeactivate;

  const _SosActiveWidget({
    required this.deactivating,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _sosActiveOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _sosActiveOrange, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _sosActiveOrange,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.white),
                    SizedBox(width: 4),
                    Text('SOS ACTIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sharing live location with emergency contacts.',
            style: TextStyle(
                color: _sosActiveOrange,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: deactivating ? null : onDeactivate,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _sosActiveOrange),
                foregroundColor: _sosActiveOrange,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: deactivating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _sosActiveOrange))
                  : const Text('End Emergency Mode',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
