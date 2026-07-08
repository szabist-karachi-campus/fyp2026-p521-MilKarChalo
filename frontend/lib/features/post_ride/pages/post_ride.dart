import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api.dart';
import '../../../core/widgets/places_autocomplete_field.dart';

class PostRidePage extends StatefulWidget {
  const PostRidePage({super.key});

  @override
  State<PostRidePage> createState() => _PostRidePageState();
}

class _PostRidePageState extends State<PostRidePage> {
  final _formKey = GlobalKey<FormState>();
  final _pickupC = TextEditingController();
  final _dropC   = TextEditingController();
  final _fareC   = TextEditingController();
  final _returnFareC = TextEditingController();

  DateTime  _selectedDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  DateTime  _returnDate   = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _returnTime   = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(days: 1)));
  int _seats = 3;
  bool _roundTripEnabled = false;
  bool _loading = false;

  // ── Recurring state ──────────────────────────────────────────────────────
  bool _recurringEnabled = false;
  String _recurrenceType = 'weekly';   // 'daily' | 'weekly' | 'custom'
  // 1=Mon … 7=Sun
  final Set<int> _selectedDays = {1, 2, 3, 4, 5};
  DateTime? _recurStartDate;
  DateTime? _recurEndDate;

  static const _navy = Color(0xFF042D4A);

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void dispose() {
    _pickupC.dispose();
    _dropC.dispose();
    _fareC.dispose();
    _returnFareC.dispose();
    super.dispose();
  }

  // ── Date / time pickers ──────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _pickReturnDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate,
      firstDate: _selectedDate,
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _returnDate = picked);
  }

  Future<void> _pickReturnTime() async {
    final picked = await showTimePicker(context: context, initialTime: _returnTime);
    if (picked != null) setState(() => _returnTime = picked);
  }

  Future<void> _pickRecurStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recurStartDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _recurStartDate = picked);
  }

  Future<void> _pickRecurEnd() async {
    final first = _recurStartDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _recurEndDate ?? first.add(const Duration(days: 30)),
      firstDate: first.add(const Duration(days: 1)),
      lastDate: first.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _recurEndDate = picked);
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submitRide() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    // Recurring validation
    if (_recurringEnabled) {
      if (_recurrenceType != 'daily' && _selectedDays.isEmpty) {
        _snack('Please select at least one day.', error: true);
        return;
      }
      if (_recurStartDate == null) {
        _snack('Please select a start date for the recurring ride.', error: true);
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final departure = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute,
      );
      final returnDeparture = DateTime(
        _returnDate.year, _returnDate.month, _returnDate.day,
        _returnTime.hour, _returnTime.minute,
      );

      if (_roundTripEnabled && !returnDeparture.isAfter(departure)) {
        _snack('Return trip must be after the departure trip.', error: true);
        return;
      }

      final fareValue       = double.tryParse(_fareC.text.trim()) ?? 0.0;
      final returnFareValue = double.tryParse(_returnFareC.text.trim()) ?? fareValue;

      final payload = <String, dynamic>{
        'pickup_location':  _pickupC.text.trim(),
        'destination':      _dropC.text.trim(),
        'departure_time':   departure.toIso8601String(),
        'total_seats':      _seats,
        'fare':             fareValue,
        'round_trip_enabled': _roundTripEnabled,
      };

      if (_roundTripEnabled) {
        payload['return_departure_time'] = returnDeparture.toIso8601String();
        payload['return_total_seats']    = _seats;
        payload['return_fare']           = returnFareValue;
      }

      if (_recurringEnabled) {
        payload['is_recurring']          = true;
        payload['recurrence_type']       = _recurrenceType;
        payload['recurrence_start_date'] =
            DateFormat('yyyy-MM-dd').format(_recurStartDate!);
        if (_recurEndDate != null) {
          payload['recurrence_end_date'] =
              DateFormat('yyyy-MM-dd').format(_recurEndDate!);
        }
        if (_recurrenceType != 'daily') {
          payload['recurrence_days'] = _selectedDays.toList()..sort();
        }
      }

      await Api.postRide(payload);

      if (!mounted) return;
      _snack(
        _recurringEnabled
            ? 'Recurring ride posted successfully!'
            : 'Ride posted successfully!',
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('Post a Ride',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Route ──────────────────────────────────────────────────────
              const Text('Route Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),
              PlacesAutocompleteField(
                controller: _pickupC,
                hint: 'Where are you leaving from?',
                prefixIcon: Icons.my_location,
                accentColor: _navy,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter pickup location' : null,
              ),
              const SizedBox(height: 15),
              PlacesAutocompleteField(
                controller: _dropC,
                hint: 'Where are you going?',
                prefixIcon: Icons.location_on,
                accentColor: _navy,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter destination' : null,
              ),

              const SizedBox(height: 18),

              // ── Round trip toggle ──────────────────────────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Round trip', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Create a linked return journey for the same route'),
                value: _roundTripEnabled,
                onChanged: (v) => setState(() => _roundTripEnabled = v),
                activeThumbColor: _navy,
              ),

              if (_roundTripEnabled) ...[
                const SizedBox(height: 12),
                _infoBox(
                  icon: Icons.loop,
                  title: 'Linked return leg',
                  body: 'Passengers will see this as a single round-trip offering with separate departure and return legs.',
                ),
              ],

              // ── Recurring ride toggle ──────────────────────────────────────
              const Divider(height: 28),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    const Icon(Icons.repeat, size: 20, color: _navy),
                    const SizedBox(width: 8),
                    const Text('Recurring ride', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                subtitle: const Text('Repeat this ride on a regular schedule'),
                value: _recurringEnabled,
                onChanged: (v) => setState(() => _recurringEnabled = v),
                activeThumbColor: _navy,
              ),

              if (_recurringEnabled) ...[
                const SizedBox(height: 16),
                _buildRecurringSection(),
              ],

              // ── Schedule ───────────────────────────────────────────────────
              const SizedBox(height: 24),
              const Text('Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _scheduleTile(
                      label: _recurringEnabled ? 'Departure Time' : 'Date',
                      value: _recurringEnabled
                          ? _selectedTime.format(context)
                          : DateFormat('MMM d, yyyy').format(_selectedDate),
                      icon: _recurringEnabled ? Icons.access_time : Icons.calendar_today,
                      onTap: _recurringEnabled ? _pickTime : _pickDate,
                    ),
                  ),
                  if (!_recurringEnabled) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _scheduleTile(
                        label: 'Time',
                        value: _selectedTime.format(context),
                        icon: Icons.access_time,
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ],
              ),

              if (_roundTripEnabled) ...[
                const SizedBox(height: 18),
                const Text('Return Schedule',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (!_recurringEnabled)
                      Expanded(
                        child: _scheduleTile(
                          label: 'Return Date',
                          value: DateFormat('MMM d, yyyy').format(_returnDate),
                          icon: Icons.calendar_today,
                          onTap: _pickReturnDate,
                        ),
                      ),
                    if (!_recurringEnabled) const SizedBox(width: 10),
                    Expanded(
                      child: _scheduleTile(
                        label: 'Return Time',
                        value: _returnTime.format(context),
                        icon: Icons.access_time,
                        onTap: _pickReturnTime,
                      ),
                    ),
                  ],
                ),
              ],

              // ── Ride details ───────────────────────────────────────────────
              const SizedBox(height: 30),
              const Text('Ride Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              _buildSeatCounter(),
              const SizedBox(height: 15),
              TextFormField(
                controller: _fareC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Fare per seat (Rs)', Icons.money),
                validator: (v) {
                  final val = double.tryParse(v?.trim() ?? '');
                  if (val == null || val <= 0) return 'Enter a valid fare amount';
                  return null;
                },
              ),

              if (_roundTripEnabled) ...[
                const SizedBox(height: 15),
                TextFormField(
                  controller: _returnFareC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dec('Return fare per seat (optional)', Icons.attach_money),
                ),
              ],

              // ── Submit ─────────────────────────────────────────────────────
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : _submitRide,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : Text(
                          _recurringEnabled
                              ? 'Post Recurring Ride'
                              : 'Post Ride',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Recurring section ─────────────────────────────────────────────────────

  Widget _buildRecurringSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recurrence type
          const Text('Recurrence Type',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              _typeChip('Daily',  'daily'),
              const SizedBox(width: 8),
              _typeChip('Weekly', 'weekly'),
              const SizedBox(width: 8),
              _typeChip('Custom', 'custom'),
            ],
          ),

          // Day-of-week picker (weekly / custom)
          if (_recurrenceType != 'daily') ...[
            const SizedBox(height: 16),
            const Text('Days of Week',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1; // 1=Mon … 7=Sun
                final selected = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(_dayLabels[i]),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedDays.add(day);
                    } else {
                      _selectedDays.remove(day);
                    }
                  }),
                  selectedColor: _navy,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: selected ? _navy : Colors.grey.shade300),
                );
              }),
            ),
          ],

          // Start & end date
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _scheduleTile(
                  label: 'Start Date *',
                  value: _recurStartDate != null
                      ? DateFormat('MMM d, yyyy').format(_recurStartDate!)
                      : 'Select',
                  icon: Icons.calendar_today,
                  onTap: _pickRecurStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _scheduleTile(
                  label: 'End Date (optional)',
                  value: _recurEndDate != null
                      ? DateFormat('MMM d, yyyy').format(_recurEndDate!)
                      : 'No end date',
                  icon: Icons.event,
                  onTap: _pickRecurEnd,
                ),
              ),
            ],
          ),

          if (_recurEndDate != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _recurEndDate = null),
              child: const Text('Clear end date',
                  style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],

          const SizedBox(height: 12),
          Text(
            '⚠️  Occurrences are generated for up to 12 months.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, String value) {
    final selected = _recurrenceType == value;
    return GestureDetector(
      onTap: () => setState(() => _recurrenceType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _navy : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _infoBox({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: _navy),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Colors.black54, height: 1.3)),
      ]),
    );
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        suffixIcon: Icon(icon, color: _navy),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _scheduleTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
                Icon(icon, size: 18, color: _navy),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Available Seats',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          Row(children: [
            IconButton(
              onPressed: () => setState(() { if (_seats > 1) _seats--; }),
              icon: const Icon(Icons.remove_circle_outline, color: _navy),
            ),
            Text('$_seats',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            IconButton(
              onPressed: () => setState(() { if (_seats < 9) _seats++; }),
              icon: const Icon(Icons.add_circle, color: _navy),
            ),
          ]),
        ],
      ),
    );
  }
}
