import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';

const Color _navy = Color(0xFF0A2540);

class BookingRequestsPage extends StatefulWidget {
  const BookingRequestsPage({super.key});
  @override
  State<BookingRequestsPage> createState() => _BookingRequestsPageState();
}

class _BookingRequestsPageState extends State<BookingRequestsPage> {
  List<dynamic> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Api.getBookingRequests();
      setState(() { _requests = data; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _snack('Failed to load requests.', error: true);
    }
  }

  Future<void> _respond(int bookingId, String action) async {
    try {
      await Api.respondToBooking(bookingId, action);
      _snack(action == 'accepted' ? 'Booking accepted ✅' : 'Booking rejected ❌');
      _load(); // refresh
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  String _formatTime(String? raw) {
    try {
      return DateFormat('MMM d  •  h:mm a').format(DateTime.parse(raw ?? '').toLocal());
    } catch (_) {
      return raw ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Booking Requests', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No pending requests',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('When passengers book your rides,\nrequests will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => _RequestCard(
                      request: _requests[i] as Map,
                      formatTime: _formatTime,
                      onRespond: _respond,
                    ),
                  ),
                ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map request;
  final String Function(String?) formatTime;
  final Future<void> Function(int, String) onRespond;

  const _RequestCard({required this.request, required this.formatTime, required this.onRespond});

  @override
  Widget build(BuildContext context) {
    final rawId = request['booking_id'];
    final bookingId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final fare = double.tryParse(request['fare']?.toString() ?? '')?.toStringAsFixed(0) ?? '-';
    final legType = request['leg_type']?.toString();
    final hasRoundTrip = request['booking_group_id'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Passenger info ──
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _navy.withOpacity(0.1),
                  child: const Icon(Icons.person, color: _navy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request['passenger_name']?.toString() ?? 'Passenger',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(request['passenger_phone']?.toString() ?? '',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text('${request['seats_booked']} seat(s)',
                      style: TextStyle(color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // ── Route ──
            Row(children: [
              const Icon(Icons.my_location, size: 15, color: Colors.green),
              const SizedBox(width: 6),
              Expanded(child: Text(request['pickup_location']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on, size: 15, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(child: Text(request['destination']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 13))),
            ]),

            const SizedBox(height: 10),

            // ── Departure & fare ──
            Row(children: [
              const Icon(Icons.access_time, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(formatTime(request['departure_time']?.toString()),
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const Spacer(),
              Text('Rs $fare / seat',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
            ]),

            if (legType != null || hasRoundTrip) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (legType != null)
                    Chip(
                      label: Text(legType == 'return' ? 'Return leg' : 'Departure leg'),
                      backgroundColor: _navy.withOpacity(0.08),
                      labelStyle: const TextStyle(color: _navy, fontWeight: FontWeight.w600),
                      side: BorderSide.none,
                    ),
                  if (hasRoundTrip)
                    Chip(
                      label: const Text('Linked round trip'),
                      backgroundColor: Colors.green.shade50,
                      labelStyle: const TextStyle(color: Colors.green),
                      side: BorderSide(color: Colors.green.shade200),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // ── Accept / Reject buttons ──
            if (bookingId != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onRespond(bookingId, 'rejected'),
                      icon: const Icon(Icons.close, size: 18, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => onRespond(bookingId, 'accepted'),
                      icon: const Icon(Icons.check, size: 18, color: Colors.white),
                      label: const Text('Accept', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
