import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/widgets/user_avatar.dart';

const Color _navy = Color(0xFF0A2540);

class RideDetailPage extends StatefulWidget {
  const RideDetailPage({super.key});
  @override
  State<RideDetailPage> createState() => _RideDetailPageState();
}

class _RideDetailPageState extends State<RideDetailPage> {
  bool _booking = false;
  late Map _ride;
  bool _readOnly = false;

  // Recurring-specific state
  List<Map<String, dynamic>> _occurrences = [];
  bool _loadingOccurrences = false;
  // Multi-select: set of selected occurrence IDs
  final Set<int> _selectedOccurrenceIds = {};
  
  // Recurring round-trip state: map of departure occurrence ID -> paired return occurrence ID
  final Map<int, int> _pairedReturnOccurrences = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _ride    = args;
      _readOnly = args['read_only'] == true;
    } else {
      _ride = {};
    }
    if (_isRecurring && !_readOnly) {
      _loadOccurrences();
    }
  }

  bool get _isRecurring {
    final v = _ride['is_recurring'];
    return v == true || v == 1 || v == '1';
  }

  bool get _isRoundTrip {
    final v = _ride['is_round_trip'];
    return v == true || v == 1 || v == '1';
  }

  bool get _isRecurringRoundTrip => _isRecurring && _isRoundTrip;

  Future<void> _loadOccurrences() async {
    final rideId = _rideIdOf(_ride['id']);
    if (rideId == null) return;
    setState(() => _loadingOccurrences = true);
    try {
      final list = await Api.getRideOccurrences(rideId);
      if (!mounted) return;
      
      // For recurring round-trips, extract paired return occurrence IDs from search results
      if (_isRecurringRoundTrip) {
        for (var occ in list) {
          final depOccId = _rideIdOf(occ['id']);
          final retOccId = _rideIdOf(occ['paired_return_occurrence_id']);
          if (depOccId != null && retOccId != null) {
            _pairedReturnOccurrences[depOccId] = retOccId;
          }
        }
      }
      
      setState(() {
        _occurrences = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadingOccurrences = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOccurrences = false);
    }
  }

  int? _rideIdOf(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  bool get _hasReturnTrip => _ride['return_ride_id'] != null;
  int? get _departureRideId => _rideIdOf(_ride['id']);
  int? get _returnRideId => _rideIdOf(_ride['return_ride_id']);

  // Get the list of selected occurrence objects
  List<Map<String, dynamic>> get _selectedOccurrences =>
      _occurrences.where((o) {
        final id = _rideIdOf(o['id']);
        return id != null && _selectedOccurrenceIds.contains(id);
      }).toList();

  String _fareStr(dynamic value) {
    if (value == null) return '-';
    return 'Rs ${double.tryParse(value.toString())?.toStringAsFixed(0) ?? value}';
  }

  // Show selected dates summary or prompt
  String get _departureStr {
    if (!_isRecurring) {
      try {
        final dt = DateTime.parse(_ride['departure_time']?.toString() ?? '');
        return DateFormat('EEEE, MMM d yyyy  •  h:mm a').format(dt.toLocal());
      } catch (_) {
        return _ride['departure_time']?.toString() ?? '-';
      }
    }
    if (_selectedOccurrenceIds.isEmpty) return 'Select dates below';
    if (_selectedOccurrenceIds.length == 1) {
      final occ = _selectedOccurrences.first;
      final raw = occ['departure_datetime']?.toString() ?? '';
      try {
        final dt = DateTime.parse(raw.replaceFirst(' ', 'T'));
        return DateFormat('EEE, MMM d yyyy  •  h:mm a').format(dt);
      } catch (_) {
        return raw;
      }
    }
    return '${_selectedOccurrenceIds.length} dates selected';
  }

  String get _returnStr {
    try {
      final dt = DateTime.parse(_ride['return_departure_time']?.toString() ?? '');
      return DateFormat('EEEE, MMM d yyyy  •  h:mm a').format(dt.toLocal());
    } catch (_) {
      return _ride['return_departure_time']?.toString() ?? '-';
    }
  }

  String get _combinedFareStr {
    final departure = double.tryParse(_ride['fare']?.toString() ?? '') ?? 0;
    final returnFare = double.tryParse(_ride['return_fare']?.toString() ?? '') ?? departure;
    final total = departure + returnFare;
    final discount = _hasReturnTrip ? total * 0.1 : 0;
    final payable = total - discount;
    return 'Rs ${payable.toStringAsFixed(0)}${discount > 0 ? ' • save Rs ${discount.toStringAsFixed(0)}' : ''}';
  }

  // Total fare for selected occurrences
  String get _selectedFareStr {
    final fare = double.tryParse(_ride['fare']?.toString() ?? '') ?? 0;
    final count = _selectedOccurrenceIds.length;
    if (count == 0) return _fareStr(_ride['fare']);
    return 'Rs ${(fare * count).toStringAsFixed(0)} (${count}x)';
  }

  // Total fare for recurring round-trip (departure + return × count)
  String _getRecurringRoundTripFare() {
    final departure = double.tryParse(_ride['fare']?.toString() ?? '') ?? 0;
    final returnFare = double.tryParse(_ride['return_fare']?.toString() ?? '') ?? departure;
    final total = (departure + returnFare) * _selectedOccurrenceIds.length;
    return 'Rs ${total.toStringAsFixed(0)}';
  }

  Future<void> _bookSelected(List<int> rideIds, String successMessage) async {
    setState(() => _booking = true);
    try {
      if (rideIds.isEmpty) { _snack('Invalid ride data.', error: true); return; }
      if (rideIds.length == 1) {
        await Api.bookRide(rideIds.first);
      } else {
        await Api.bookRides(rideIds);
      }
      if (!mounted) return;
      _snack(successMessage);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _bookDeparture() async {
    final rideId = _departureRideId;
    if (rideId == null) { _snack('Invalid departure ride.', error: true); return; }

    if (_isRecurring) {
      if (_selectedOccurrenceIds.isEmpty) {
        _snack('Please select at least one date to book.', error: true);
        return;
      }
      
      // For recurring round-trips, use bookRecurringRoundTrip with paired occurrences
      if (_isRecurringRoundTrip) {
        // Collect paired return occurrence IDs for selected departures
        final returnOccIds = <int>[];
        for (final depOccId in _selectedOccurrenceIds) {
          final retOccId = _pairedReturnOccurrences[depOccId];
          if (retOccId == null) {
            _snack('Paired return occurrence not found for occurrence $depOccId.', error: true);
            return;
          }
          returnOccIds.add(retOccId);
        }
        
        final occIds = _selectedOccurrenceIds.toList();
        setState(() => _booking = true);
        try {
          await Api.bookRecurringRoundTrip(rideId, occIds, returnOccIds);
          if (!mounted) return;
          final count = occIds.length;
          _snack(count == 1
              ? 'Round-trip booked for ${_formatOccurrenceDate(_selectedOccurrences.first['occurrence_date']?.toString())}! 🎉'
              : '$count round-trip pairs booked! Waiting for driver approval. 🎉');
          Navigator.pop(context, true);
        } on ApiException catch (e) {
          _snack(e.message, error: true);
        } finally {
          if (mounted) setState(() => _booking = false);
        }
        return;
      }
      
      // Regular recurring (non-round-trip) booking
      final occIds = _selectedOccurrenceIds.toList();
      setState(() => _booking = true);
      try {
        await Api.bookOccurrences(rideId, occIds);
        if (!mounted) return;
        final count = occIds.length;
        _snack(count == 1
            ? 'Ride booked for ${_formatOccurrenceDate(_selectedOccurrences.first['occurrence_date']?.toString())}! 🎉'
            : '$count dates booked! Waiting for driver approval. 🎉');
        Navigator.pop(context, true);
      } on ApiException catch (e) {
        _snack(e.message, error: true);
      } finally {
        if (mounted) setState(() => _booking = false);
      }
      return;
    }
    await _bookSelected([rideId], 'Departure trip booked successfully! 🎉');
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

  Future<void> _bookReturn() async {
    final rideId = _returnRideId;
    if (rideId == null) { _snack('Invalid return ride.', error: true); return; }
    await _bookSelected([rideId], 'Return trip booked successfully! 🎉');
  }

  Future<void> _bookBoth() async {
    final departureId = _departureRideId;
    final returnId = _returnRideId;
    if (departureId == null || returnId == null) {
      _snack('Round trip is not fully configured.', error: true); return;
    }
    await _bookSelected([departureId, returnId], 'Round trip booked successfully! 🎉');
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Ride Details', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header Banner ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              decoration: const BoxDecoration(
                color: _navy,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _ride['pickup_location']?.toString() ?? '-',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(children: List.generate(3, (_) => const Text('|', style: TextStyle(color: Colors.white38, height: 0.8)))),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _ride['destination']?.toString() ?? '-',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (_hasReturnTrip) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.loop, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text('Linked round trip offering', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.loop, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            '🔄 Round Trip',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // ── Recurring badge in header ──────────────────────────────
                  if (_isRecurring) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.repeat, color: Colors.amberAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isRecurringRoundTrip
                                ? '🔄 Recurring Round-Trip • ${_recurrenceSummary()}'
                                : _recurrenceSummary(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Schedule & Fare ──
                  _card(children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 18, color: Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isRecurring
                                    ? (_selectedOccurrenceIds.length > 1 ? 'Selected Occurrences' : 'Selected Occurrence')
                                    : 'Departure',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 2),
                              Text(_departureStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _infoRow(
                      Icons.event_seat,
                      'Available Seats',
                      _isRecurring && _selectedOccurrenceIds.length == 1
                          ? '${_selectedOccurrences.first['available_seats'] ?? '-'} seats'
                          : '${_ride['available_seats'] ?? '-'} seats',
                    ),
                    const Divider(height: 20),
                    _infoRow(Icons.payments_outlined, 'Fare per Seat', _fareStr(_ride['fare']),
                        valueStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _navy)),
                    if (_hasReturnTrip) ...[
                      const Divider(height: 20),
                      _infoRow(Icons.change_circle_outlined, 'Return Trip', _returnStr),
                      const Divider(height: 20),
                      _infoRow(Icons.event_seat, 'Return Seats', '${_ride['return_available_seats'] ?? '-'} seats'),
                      const Divider(height: 20),
                      _infoRow(Icons.payments_outlined, 'Return Fare per Seat', _fareStr(_ride['return_fare'])),
                      const Divider(height: 20),
                      _infoRow(Icons.savings_outlined, 'Book Both Together', _combinedFareStr,
                          valueStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
                    ],
                  ]),
                  const SizedBox(height: 14),

                  // ── Occurrence picker (recurring rides only) ──────────────
                  if (_isRecurring && !_readOnly) ...[
                    _card(children: [
                      Row(
                        children: [
                          const Text('SELECT DATES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                          const Spacer(),
                          if (_occurrences.isNotEmpty) ...[
                            // Select All / Clear All toggle
                            GestureDetector(
                              onTap: () => setState(() {
                                if (_selectedOccurrenceIds.length == _occurrences.length) {
                                  _selectedOccurrenceIds.clear();
                                } else {
                                  _selectedOccurrenceIds.addAll(
                                    _occurrences.map((o) => _rideIdOf(o['id'])).whereType<int>(),
                                  );
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _selectedOccurrenceIds.length == _occurrences.length
                                      ? _navy
                                      : _navy.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _selectedOccurrenceIds.length == _occurrences.length
                                      ? 'Clear All'
                                      : 'Select All',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedOccurrenceIds.length == _occurrences.length
                                        ? Colors.white
                                        : _navy,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_loadingOccurrences)
                        const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                      else if (_occurrences.isEmpty)
                        const Text('No upcoming dates available.', style: TextStyle(color: Colors.grey))
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _occurrences.map((occ) {
                            final occId = _rideIdOf(occ['id']);
                            final isSelected = occId != null && _selectedOccurrenceIds.contains(occId);
                            final seats = int.tryParse(occ['available_seats']?.toString() ?? '0') ?? 0;
                            final hasSeats = seats > 0;
                            String dayLabel = '-';
                            String monthLabel = '-';
                            String timeLabel = '';
                            try {
                              final raw = occ['occurrence_date']?.toString() ?? '';
                              final datePart = raw.substring(0, 10);
                              final parts = datePart.split('-');
                              final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                              dayLabel = DateFormat('d').format(dt);
                              monthLabel = DateFormat('MMM').format(dt);
                            } catch (_) {}
                            try {
                              final dtRaw = occ['departure_datetime']?.toString() ?? '';
                              if (dtRaw.isNotEmpty) {
                                final dt = DateTime.parse(dtRaw.replaceFirst(' ', 'T'));
                                timeLabel = DateFormat('h:mm a').format(dt);
                              }
                            } catch (_) {}
                            return GestureDetector(
                              onTap: hasSeats ? () {
                                if (occId == null) return;
                                setState(() {
                                  if (_selectedOccurrenceIds.contains(occId)) {
                                    _selectedOccurrenceIds.remove(occId);
                                  } else {
                                    _selectedOccurrenceIds.add(occId);
                                  }
                                });
                              } : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 62,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !hasSeats
                                      ? Colors.grey.shade100
                                      : isSelected
                                          ? _navy
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: !hasSeats
                                        ? Colors.grey.shade300
                                        : isSelected
                                            ? _navy
                                            : Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(dayLabel, style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold,
                                      color: !hasSeats ? Colors.grey.shade400 : isSelected ? Colors.white : Colors.black87,
                                    )),
                                    Text(monthLabel, style: TextStyle(
                                      fontSize: 11,
                                      color: !hasSeats ? Colors.grey.shade400 : isSelected ? Colors.white70 : Colors.grey,
                                    )),
                                    if (timeLabel.isNotEmpty)
                                      Text(timeLabel, style: TextStyle(
                                        fontSize: 9,
                                        color: !hasSeats ? Colors.grey.shade400 : isSelected ? Colors.white60 : Colors.grey,
                                      )),
                                    Text(
                                      hasSeats ? '$seats seats' : 'Full',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: !hasSeats ? Colors.red.shade300 : isSelected ? Colors.white60 : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (_selectedOccurrenceIds.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _navy.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _selectedOccurrenceIds.length == 1
                                ? 'Booking 1 date  •  ${_fareStr(_ride['fare'])}'
                                : 'Booking ${_selectedOccurrenceIds.length} dates  •  $_selectedFareStr',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 14),
                  ],

                  // ── Recurring Round-Trip Booking Summary ──
                  if (_isRecurringRoundTrip && _selectedOccurrenceIds.isNotEmpty) ...[
                    _card(children: [
                      const Text('BOOKING SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Round-Trip Pairs', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                '${_selectedOccurrenceIds.length} pair${_selectedOccurrenceIds.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Total Fare', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                _getRecurringRoundTripFare(),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Both departure and return legs will be booked together',
                                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                  ],

                  if (_hasReturnTrip && !_isRecurringRoundTrip) ...[
                    _card(children: [
                      const Text('ROUND TRIP BENEFITS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      const Text(
                        'Booking both legs together keeps your return seat reserved, applies combined pricing, and avoids a separate search later.',
                        style: TextStyle(color: Colors.black87, height: 1.35),
                      ),
                    ]),
                    const SizedBox(height: 14),
                  ],

                  // ── Driver Info ──
                  _card(children: [
                    const Text('DRIVER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        UserAvatar(
                          imageUrl: _ride['driver_image_url']?.toString(),
                          radius: 26,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ride['driver_name']?.toString() ?? 'Driver',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Row(children: [
                                const Icon(Icons.shield, size: 13, color: Colors.green),
                                const SizedBox(width: 4),
                                const Text('Verified Driver', style: TextStyle(color: Colors.green, fontSize: 12)),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // ── Vehicle Info ──
                  if ((_ride['car_make'] ?? '').toString().isNotEmpty)
                    _card(children: [
                      const Text('VEHICLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      _infoRow(Icons.directions_car, 'Car',
                          '${_ride['car_make'] ?? ''} ${_ride['car_model'] ?? ''}'.trim()),
                      if ((_ride['car_color'] ?? '').toString().isNotEmpty) ...[
                        const Divider(height: 16),
                        _infoRow(Icons.palette_outlined, 'Color', _ride['car_color']?.toString() ?? '-'),
                      ],
                      if ((_ride['car_plate'] ?? '').toString().isNotEmpty) ...[
                        const Divider(height: 16),
                        _infoRow(Icons.credit_card, 'Plate No.', _ride['car_plate']?.toString() ?? '-'),
                      ],
                    ]),

                  const SizedBox(height: 28),

                  // ── Book Button (hidden when already booked) ──
                  if (_readOnly) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You have booked this ride',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                    fontSize: 15,
                                  ),
                                ),
                                if ((_ride['booking_status']?.toString() ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Status: ${_ride['booking_status']?.toString() ?? ''}',
                                    style: TextStyle(color: Colors.green.shade600, fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      onPressed: _booking ? null : (_isRecurringRoundTrip ? _bookDeparture : (_hasReturnTrip ? _bookBoth : _bookDeparture)),
                      child: _booking
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.white),
                                const SizedBox(width: 10),
                                Text(
                                  _isRecurringRoundTrip
                                      ? (_selectedOccurrenceIds.isEmpty
                                          ? 'Select Dates to Book'
                                          : _selectedOccurrenceIds.length == 1
                                              ? 'Book Round-Trip  •  ${_getRecurringRoundTripFare()}'
                                              : 'Book ${_selectedOccurrenceIds.length} Round-Trips  •  ${_getRecurringRoundTripFare()}')
                                      : (_hasReturnTrip
                                          ? 'Book Round Trip  •  $_combinedFareStr'
                                          : _isRecurring && _selectedOccurrenceIds.length > 1
                                              ? 'Book ${_selectedOccurrenceIds.length} Dates  •  $_selectedFareStr'
                                              : 'Book Ride  •  ${_fareStr(_ride['fare'])}'),
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                  ),
                  if (_hasReturnTrip && !_isRecurringRoundTrip) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _booking ? null : _bookDeparture,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _navy),
                              foregroundColor: _navy,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Departure only'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _booking ? null : _bookReturn,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _navy),
                              foregroundColor: _navy,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Return only'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _infoRow(IconData icon, String label, String value, {TextStyle? valueStyle}) => Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(value, style: valueStyle ?? const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ]),
          ),
        ],
      );

  String _recurrenceSummary() {
    final type = _ride['recurrence_type']?.toString() ?? '';
    if (type == 'daily') return '🔁 Recurring Daily';
    // For weekly/custom we'd need day names — show generic label
    return '🔁 Recurring Ride';
  }
}
