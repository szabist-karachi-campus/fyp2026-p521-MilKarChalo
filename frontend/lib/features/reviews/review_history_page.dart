import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';

const Color _navy = Color(0xFF0A2540);

class ReviewHistoryPage extends StatefulWidget {
  const ReviewHistoryPage({super.key});

  @override
  State<ReviewHistoryPage> createState() => _ReviewHistoryPageState();
}

class _ReviewHistoryPageState extends State<ReviewHistoryPage> {
  List<dynamic> _reviews = [];
  Map<String, dynamic> _stats = const {'average_rating': 0, 'review_count': 0};
  bool _loading = true;
  DateTimeRange? _dateRange;
  int? _ratingFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _fromDate => _dateRange == null ? null : DateFormat('yyyy-MM-dd').format(_dateRange!.start);
  String? get _toDate => _dateRange == null ? null : DateFormat('yyyy-MM-dd').format(_dateRange!.end);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await Api.getReceivedReviews(
        from: _fromDate,
        to: _toDate,
        rating: _ratingFilter,
      );
      if (!mounted) return;
      setState(() {
        _reviews = (resp['data'] as List?) ?? [];
        _stats = (resp['stats'] as Map?)?.cast<String, dynamic>() ?? _stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load review history: $e')),
      );
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      helpText: 'Filter reviews by date',
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    await _load();
  }

  void _clearFilters() {
    setState(() {
      _dateRange = null;
      _ratingFilter = null;
    });
    _load();
  }

  Widget _stars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final active = index < rating.round();
        return Icon(
          active ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: active ? const Color(0xFFFFB703) : Colors.grey.shade400,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final average = double.tryParse(_stats['average_rating']?.toString() ?? '0') ?? 0;
    final count = int.tryParse(_stats['review_count']?.toString() ?? '0') ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Review History', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0A2540), Color(0xFF1D4C7C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.star_rounded, color: Colors.amber, size: 34),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ratings received',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                count == 0 ? 'No reviews yet' : '${average.toStringAsFixed(1)} / 5',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$count total reviews',
                                style: TextStyle(color: Colors.white.withOpacity(0.8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDateRange,
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                            _dateRange == null
                                ? 'Filter by date'
                                : '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _navy,
                            backgroundColor: Colors.white,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 112,
                        child: DropdownButtonFormField<int?>(
                          value: _ratingFilter,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          items: const [
                            DropdownMenuItem<int?>(value: null, child: Text('All')),
                            DropdownMenuItem<int?>(value: 5, child: Text('5★')),
                            DropdownMenuItem<int?>(value: 4, child: Text('4★')),
                            DropdownMenuItem<int?>(value: 3, child: Text('3★')),
                            DropdownMenuItem<int?>(value: 2, child: Text('2★')),
                            DropdownMenuItem<int?>(value: 1, child: Text('1★')),
                          ],
                          onChanged: (value) {
                            setState(() => _ratingFilter = value);
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: (_dateRange == null && _ratingFilter == null) ? null : _clearFilters,
                        icon: const Icon(Icons.clear_all_rounded),
                        tooltip: 'Clear filters',
                        color: _navy,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_reviews.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.rate_review_outlined, size: 72, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text('No reviews found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            'Ratings and comments you receive will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._reviews.map((item) {
                      final review = item as Map;
                      final rating = double.tryParse(review['rating']?.toString() ?? '0') ?? 0;
                      final rideTime = review['departure_time']?.toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 20,
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
                                children: [
                                  CircleAvatar(
                                    backgroundColor: _navy.withOpacity(0.1),
                                    child: Text(
                                      (review['reviewer_name']?.toString() ?? '?').isNotEmpty
                                          ? review['reviewer_name'].toString()[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(color: _navy, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'From ${review['reviewer_name']?.toString() ?? 'Anonymous'}',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        _stars(rating),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM d, yyyy').format(DateTime.parse(review['created_at'].toString()).toLocal()),
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.route_rounded, size: 18, color: _navy),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${review['pickup_location']?.toString() ?? '-'} → ${review['destination']?.toString() ?? '-'}',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time_rounded, size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            rideTime == null || rideTime.isEmpty
                                                ? '-'
                                                : DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(rideTime).toLocal()),
                                            style: TextStyle(color: Colors.grey.shade700),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if ((review['comment']?.toString() ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  review['comment'].toString(),
                                  style: const TextStyle(fontSize: 14, height: 1.4),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Tag(label: review['ride_status']?.toString() ?? 'unknown', color: Colors.blueGrey),
                                  _Tag(label: review['booking_status']?.toString() ?? 'unknown', color: Colors.teal),
                                  if ((review['leg_type']?.toString() ?? '').isNotEmpty)
                                    _Tag(label: review['leg_type'].toString(), color: _navy),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
