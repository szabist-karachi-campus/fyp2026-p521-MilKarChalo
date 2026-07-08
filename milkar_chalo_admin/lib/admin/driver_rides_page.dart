import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';

class DriverRidesPage extends StatefulWidget {
  final int driverId;
  const DriverRidesPage({super.key, required this.driverId});

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _rides = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await Api.getDriverRides(widget.driverId);
      final data = resp['data'];
      setState(() { _rides = (data is List) ? data : []; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Failed to load rides'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: const Color(0xFF18283D),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7F8FC), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF18283D), Color(0xFF2B4C7E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.route_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Driver rides',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Review every trip, request, and ride state in one place.',
                            style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 13, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _rides.isEmpty
                            ? const Center(child: Text('No rides found'))
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                itemCount: _rides.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final r = _rides[i] as Map;
                                  final rideId = r['ride_id']?.toString() ?? r['id']?.toString() ?? '';
                                  final status = r['status']?.toString() ?? '-';
                                  final when = r['departure_time']?.toString() ?? '-';
                                  final pickup = r['pickup_location']?.toString() ?? '-';
                                  final dest = r['destination']?.toString() ?? '-';
                                  final booked = r['booked_seats']?.toString() ?? '0';
                                  final pending = r['pending_seats']?.toString() ?? '0';

                                  return InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RideDetailsPage(rideId: int.tryParse(rideId) ?? 0),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: Colors.black.withOpacity(0.05)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.06),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [_statusColor(status), _statusColor(status).withOpacity(0.7)],
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                    ),
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  child: Icon(
                                                    _rideIcon(status),
                                                    color: Colors.white,
                                                    size: 24,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '$pickup → $dest',
                                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        when,
                                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 88,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: _statusColor(status).withOpacity(0.12),
                                                          borderRadius: BorderRadius.circular(999),
                                                        ),
                                                        child: Text(
                                                          status.toUpperCase(),
                                                          style: TextStyle(
                                                            color: _statusColor(status),
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            letterSpacing: 0.4,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Container(
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFF2F4F8),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: IconButton(
                                                          onPressed: () {
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder: (_) => RideDetailsPage(rideId: int.tryParse(rideId) ?? 0),
                                                              ),
                                                            );
                                                          },
                                                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                                          visualDensity: VisualDensity.compact,
                                                          padding: EdgeInsets.zero,
                                                          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              children: [
                                                _InfoPill(label: 'Booked', value: booked, accent: const Color(0xFF2B4C7E)),
                                                const SizedBox(width: 8),
                                                _InfoPill(label: 'Pending', value: pending, accent: const Color(0xFFB7791F)),
                                                const Spacer(),
                                                Text(
                                                  'Tap to inspect',
                                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _InfoPill({required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label ', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          Text(value, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

Color _statusColor(String? status) {
  final s = (status ?? '').toLowerCase();
  switch (s) {
    case 'active': return Colors.green;
    case 'started': return Colors.orange;
    case 'completed': return Colors.blue;
    case 'canceled':
    case 'cancelled': return Colors.red;
    case 'pending': return Colors.amber;
    default: return Colors.grey;
  }
}

IconData _rideIcon(String? status) {
  final s = (status ?? '').toLowerCase();
  switch (s) {
    case 'active':
      return Icons.directions_car_rounded;
    case 'started':
      return Icons.play_circle_fill_rounded;
    case 'completed':
      return Icons.verified_rounded;
    case 'canceled':
    case 'cancelled':
      return Icons.cancel_rounded;
    default:
      return Icons.route_rounded;
  }
}

class RideDetailsPage extends StatefulWidget {
  final int rideId;
  const RideDetailsPage({super.key, required this.rideId});
  @override
  State<RideDetailsPage> createState() => _RideDetailsPageState();
}

class _RideDetailsPageState extends State<RideDetailsPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _ride;
  List<dynamic> _bookings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await Api.getRideDetailsAdmin(widget.rideId);
      final data = resp['data'] as Map?;
      setState(() {
        _ride = (data?['ride'] as Map?)?.cast<String, dynamic>();
        _bookings = (data?['bookings'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Failed to load ride details'; _loading = false; });
    }
  }

  Future<void> _updateBooking(int bookingId, String status) async {
    setState(() { _loading = true; });
    try {
      await Api.updateBookingStatus(bookingId, status);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking $status')));
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update booking')));
      setState(() { _loading = false; });
    }
  }

  Future<void> _changeRideStatus(String status) async {
    setState(() { _loading = true; });
    try {
      await Api.changeRideStatus(widget.rideId, status);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ride set to $status')));
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to change ride status')));
      setState(() { _loading = false; });
    }
  }

  Future<void> _exportCsv() async {
    setState(() { _loading = true; });
    try {
      final resp = await Api.exportRideCsv(widget.rideId);
      final csv = (resp['data'] is Map) ? resp['data']['csv'] : null;
      setState(() { _loading = false; });
      if (csv == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No CSV returned')));
        return;
      }
      // Show CSV in dialog with copy button
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Exported CSV'),
        content: SingleChildScrollView(child: SelectableText(csv)),
        actions: [
          TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: csv)); Navigator.of(context).pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard'))); }, child: const Text('Copy')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ));
    } catch (e) {
      setState(() { _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to export CSV')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideStatus = (_ride?['status'] ?? '').toString().toLowerCase();
    final isTerminalRide = rideStatus == 'completed' || rideStatus == 'canceled' || rideStatus == 'cancelled';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details'),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF18283D),
        elevation: 0,
        actions: [
          IconButton(onPressed: _exportCsv, icon: const Icon(Icons.download_rounded)),
          if (isTerminalRide)
            const Tooltip(
              message: 'Ride is closed',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.lock_rounded, color: Colors.white70),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Change ride status',
              icon: const Icon(Icons.tune_rounded),
              onSelected: (v) { _changeRideStatus(v); },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'active', child: Text('Set Active')),
                const PopupMenuItem(value: 'started', child: Text('Set Started')),
                const PopupMenuItem(value: 'completed', child: Text('Set Completed')),
                const PopupMenuItem(value: 'canceled', child: Text('Set Canceled')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _ride == null
                  ? const Center(child: Text('Ride not found'))
                  : Stack(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFF7F8FC), Color(0xFFFFFFFF)],
                            ),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF18283D), Color(0xFF2B4C7E)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 20),
                                    Row(
                                  children: [
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.16),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(_rideIcon((_ride!['status'] ?? '').toString()), color: Colors.white),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Ride overview',
                                            style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 0.5),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_ride!['pickup_location']} → ${_ride!['destination']}',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _statusColor(_ride!['status']).withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        (_ride!['status'] ?? '-').toString().toUpperCase(),
                                        style: TextStyle(
                                          color: _statusColor(_ride!['status']),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _StatChip(icon: Icons.schedule_rounded, label: 'Departure', value: '${_ride!['departure_time'] ?? '-'}'),
                                        _StatChip(icon: Icons.monetization_on_rounded, label: 'Fare', value: '${_ride!['fare'] ?? '-'}'),
                                        _StatChip(icon: Icons.event_seat_rounded, label: 'Seats', value: '${_ride!['available_seats'] ?? '-'} / ${_ride!['total_seats'] ?? '-'}'),
                                      ],
                                    ),
                                    if (isTerminalRide) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                                        ),
                                        child: const Text(
                                          'This ride is closed. Status changes are disabled.',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Bookings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  Text('${_bookings.length} request${_bookings.length == 1 ? '' : 's'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ..._bookings.map((b) {
                                final bm = b as Map;
                                final status = (bm['booking_status'] ?? '').toString();
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: Colors.black.withOpacity(0.05)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 14,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    leading: CircleAvatar(
                                      radius: 24,
                                      backgroundColor: _statusColor(status).withOpacity(0.16),
                                      child: Text(
                                        (bm['passenger_name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                                        style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    title: Text(
                                      bm['passenger_name'] ?? 'Passenger',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '${bm['passenger_email'] ?? ''}\nSeats: ${bm['seats_booked'] ?? '-'}',
                                        style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                                      ),
                                    ),
                                    isThreeLine: true,
                                    trailing: SizedBox(
                                      width: 92,
                                      child: FittedBox(
                                        alignment: Alignment.centerRight,
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _statusColor(status).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(status.toUpperCase(), style: const TextStyle(fontSize: 12)),
                                            ),
                                            const SizedBox(height: 4),
                                            if (status == 'pending') Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: IconButton(
                                                    onPressed: () => _updateBooking(bm['booking_id'], 'accepted'),
                                                    icon: const Icon(Icons.check, color: Colors.green, size: 18),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: IconButton(
                                                    onPressed: () => _updateBooking(bm['booking_id'], 'rejected'),
                                                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
