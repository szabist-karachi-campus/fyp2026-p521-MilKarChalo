import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api.dart';
import '../../../core/widgets/places_autocomplete_field.dart';
import '../../../core/widgets/user_avatar.dart';

class SearchRidePage extends StatefulWidget {
  const SearchRidePage({super.key});
  @override
  State<SearchRidePage> createState() => _SearchRidePageState();
}

class _SearchRidePageState extends State<SearchRidePage> {
  final _pickupC = TextEditingController();
  final _dropC = TextEditingController();
  String _genderPref = 'both';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  List<dynamic> _results = [];
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _pickupC.dispose();
    _dropC.dispose();
    super.dispose();
  }
  
  Future<void> _doSearch() async {
    FocusScope.of(context).unfocus();

    // Validate mandatory fields
    if (_pickupC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a pickup location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_dropC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a destination'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() { _searching = true; _hasSearched = true; });
    try {
      final filters = <String, String>{
        'pickup': _pickupC.text.trim(),
        'destination': _dropC.text.trim(),
        'gender_pref': _genderPref,
        'seats_needed': '1',
      };

      if (_selectedDate != null) {
        filters['ride_date'] = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      }
      if (_selectedTime != null) {
        final h = _selectedTime!.hour.toString().padLeft(2, '0');
        final m = _selectedTime!.minute.toString().padLeft(2, '0');
        filters['ride_time'] = '$h:$m:00';
      }

      final results = await Api.searchRides(filters);
      if (!mounted) return;
      setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('Find a Ride', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    PlacesAutocompleteField(
                      controller: _pickupC,
                      hint: 'Pickup Point *',
                      prefixIcon: Icons.my_location,
                      accentColor: const Color(0xFF0A2540),
                    ),
                    const Divider(height: 1),
                    PlacesAutocompleteField(
                      controller: _dropC,
                      hint: 'Destination *',
                      prefixIcon: Icons.location_on,
                      accentColor: const Color(0xFF0A2540),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _genderPref,
                      decoration: const InputDecoration(
                        labelText: 'Gender Filter',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'both', child: Text('No Gender Preference')),
                        DropdownMenuItem(value: 'male', child: Text('Male Drivers Only')),
                        DropdownMenuItem(value: 'female', child: Text('Female Drivers Only')),
                      ],
                      onChanged: (v) => setState(() => _genderPref = v!),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                              _selectedDate == null
                                  ? 'Any Date'
                                  : DateFormat('MMM d, y').format(_selectedDate!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickTime,
                            icon: const Icon(Icons.schedule, size: 16),
                            label: Text(
                              _selectedTime == null
                                  ? 'Any Time'
                                  : _selectedTime!.format(context),
                            ),
                          ),
                        ),
                        if (_selectedDate != null || _selectedTime != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Clear date/time',
                            onPressed: () => setState(() {
                              _selectedDate = null;
                              _selectedTime = null;
                            }),
                            icon: const Icon(Icons.clear),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A2540),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _searching ? null : _doSearch,
                        child: _searching
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Search Rides', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search, size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('Enter your route and tap Search', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : _results.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('No rides found matching your criteria', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _results.length,
                            itemBuilder: (c, i) => _RideResultTile(
                              ride: _results[i],
                              occurrences: {},
                              onBooked: _doSearch,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _RideResultTile extends StatefulWidget {
  final Map ride;
  final Map<int, List<dynamic>> occurrences;
  final VoidCallback? onBooked;
  const _RideResultTile({
    required this.ride, 
    required this.occurrences,
    this.onBooked,
  });

  @override
  State<_RideResultTile> createState() => _RideResultTileState();
}

class _RideResultTileState extends State<_RideResultTile> {
  String _formatDeparture(Map ride) {
    final isRecurring = ride['is_recurring'] == true || 
                       ride['is_recurring'] == 1 || 
                       ride['is_recurring'] == '1';
    
    if (!isRecurring) {
      // Non-recurring rides: standard display using departure_time
      try {
        final dt = DateTime.parse(ride['departure_time']?.toString() ?? '');
        return DateFormat('MMM d, h:mm a').format(dt.toLocal());
      } catch (_) {
        return ride['departure_time']?.toString() ?? '-';
      }
    }
    
    // For recurring rides: MUST use departure_datetime from ride_occurrences
    // The search API joins with ride_occurrences and returns occurrence data
    try {
      if (ride['departure_datetime'] != null && ride['departure_datetime'].toString().isNotEmpty) {
        // departure_datetime is "YYYY-MM-DD HH:MM:SS" (local/server time, no timezone)
        // Parse without converting to avoid timezone offset issues
        final dt = DateTime.parse(ride['departure_datetime']?.toString() ?? '');
        return DateFormat('MMM d, h:mm a').format(dt);
      }
    } catch (_) {
      // Fall through to fallback
    }
    
    // Fallback only if occurrence datetime not available
    try {
      final dt = DateTime.parse(ride['departure_time']?.toString() ?? '').toLocal();
      return DateFormat('MMM d, h:mm a').format(dt);
    } catch (_) {
      return ride['departure_time']?.toString() ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final fare = ride['fare'];
    final fareStr = fare != null ? 'Rs ${double.tryParse(fare.toString())?.toStringAsFixed(0) ?? fare}' : '-';
    final hasRoundTrip = ride['return_ride_id'] != null || ride['is_round_trip'] == true || ride['is_round_trip'] == 1;
    final isRecurring  = ride['is_recurring'] == true || ride['is_recurring'] == 1 || ride['is_recurring'] == '1';

    final departureStr = _formatDeparture(ride);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  imageUrl: ride['driver_image_url']?.toString(),
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ride['driver_name'] ?? 'Driver'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${ride['car_make'] ?? ''} ${ride['car_model'] ?? ''}'.trim(),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(fareStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0A2540))),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(departureStr, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const Spacer(),
                const Icon(Icons.event_seat, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${ride['available_seats'] ?? '-'} seats', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
            if (hasRoundTrip) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2540).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.loop, size: 14, color: Color(0xFF0A2540)),
                    const SizedBox(width: 6),
                    const Text(
                      '🔄 Round Trip',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0A2540),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isRecurring) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.repeat, size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔁 Recurring Ride',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.amber,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'View details to see all available dates',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A2540),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                    final result = await Navigator.pushNamed(
                      context,
                      '/ride-detail',
                      arguments: widget.ride,
                    );
                    if (result == true) widget.onBooked?.call();
                  },
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('See Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
