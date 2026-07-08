import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import 'driver_rides_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<dynamic> _pending  = [];
  List<dynamic> _approved = [];
  List<dynamic> _allDrivers = [];
  List<dynamic> _reviews = [];
  List<dynamic> _sosEvents = [];
  bool _loadingPending  = true;
  bool _loadingApproved = true;
  bool _loadingAll = true;
  bool _loadingReviews = true;
  bool _loadingSos = true;
  String? _errorPending;
  String? _errorApproved;
  String? _errorAll;
  String? _errorReviews;
  String? _errorSos;
  String _reviewSearch = '';
  int? _reviewRatingFilter;
  int? _reviewDriverFilter;
  DateTimeRange? _reviewDateRange;
  String _sosStatusFilter = 'all'; // 'all' | 'active' | 'resolved'
  String _sosSearch = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _fetchPending();
    _fetchApproved();
    _fetchAllDrivers();
    _fetchReviews();
    _fetchSosEvents();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Data fetching ──────────────────────────────────────────────

  Future<void> _fetchPending() async {
    setState(() { _loadingPending = true; _errorPending = null; });
    try {
      final resp = await Api.get('/admin/pending-drivers');
      final data = resp['data'];
      setState(() { _pending = (data is List) ? data : []; _loadingPending = false; });
    } catch (e) {
      setState(() { _errorPending = 'Failed to load pending drivers.'; _loadingPending = false; });
    }
  }

  Future<void> _fetchApproved() async {
    setState(() { _loadingApproved = true; _errorApproved = null; });
    try {
      final resp = await Api.get('/admin/approved-drivers');
      final data = resp['data'];
      setState(() { _approved = (data is List) ? data : []; _loadingApproved = false; });
    } catch (e) {
      setState(() { _errorApproved = 'Failed to load approved drivers.'; _loadingApproved = false; });
    }
  }

  Future<void> _fetchAllDrivers() async {
    setState(() { _loadingAll = true; _errorAll = null; });
    try {
      final resp = await Api.get('/admin/all-drivers');
      final data = resp['data'];
      setState(() { _allDrivers = (data is List) ? data : []; _loadingAll = false; });
    } catch (e) {
      setState(() { _errorAll = 'Failed to load all drivers.'; _loadingAll = false; });
    }
  }

  Future<void> _fetchReviews() async {
    setState(() { _loadingReviews = true; _errorReviews = null; });
    try {
      final resp = await Api.getAdminReviews();
      final data = resp['data'];
      setState(() {
        _reviews = (data is List) ? data : [];
        _loadingReviews = false;
      });
    } catch (e) {
      setState(() { _errorReviews = 'Failed to load reviews.'; _loadingReviews = false; });
    }
  }

  Future<void> _fetchSosEvents() async {
    setState(() { _loadingSos = true; _errorSos = null; });
    try {
      final statusParam = _sosStatusFilter == 'all' ? null : _sosStatusFilter;
      final resp = await Api.getAdminSosEvents(
        status: statusParam,
        search: _sosSearch.isEmpty ? null : _sosSearch,
      );
      final data = resp['data'];
      setState(() {
        _sosEvents = (data is List) ? data : [];
        _loadingSos = false;
      });
    } catch (e) {
      setState(() { _errorSos = 'Failed to load SOS events.'; _loadingSos = false; });
    }
  }

  Future<void> _verify(int userId, String status) async {
    try {
      await Api.post('/admin/verify-driver', {'userId': userId, 'status': status});
      final s = status.toLowerCase();
      final label = _statusLabel(s).toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Driver marked as $label'),
        backgroundColor: _statusColor(s),
      ));
      // Refresh both lists after an action
      _fetchPending();
      _fetchApproved();
      _fetchAllDrivers();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed. Please try again.')));
    }
  }

  void _openDriverReviews(int driverId) {
    setState(() {
      _reviewDriverFilter = driverId;
      _tabs.index = 3;
    });
  }

  // ── Logout ─────────────────────────────────────────────────────

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_role');
    Api.setToken(null);
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  // ── Dialogs ────────────────────────────────────────────────────

  void _showPendingDetails(Map d) {
    final rawId = d['user_id'] ?? d['id'];
    final userId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Review: ${d['name'] ?? 'Unknown'}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _dRow('Email',   d['email']?.toString()              ?? '-'),
              _dRow('Phone',   d['phone']?.toString()              ?? '-'),
              _dRow('CNIC',    d['cnic']?.toString()               ?? '-'),
              _dRow('License', d['driving_license_no']?.toString() ?? '-'),
              _dRow('Address', d['address']?.toString()            ?? '-'),
              if (d['image_url'] != null) ...[
                const SizedBox(height: 12),
                const Text('Profile Image:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network('${ApiConfig.base}${d['image_url']}',
                      width: 380, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text('Could not load image.',
                          style: TextStyle(color: Colors.grey))),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (userId != null) ...[
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _verify(userId, 'rejected'); },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Reject', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _verify(userId, 'approved'); },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Approve', style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }

  void _showApprovedDetails(Map d) {
    final rawId = d['user_id'] ?? d['id'];
    final userId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final rides = d['total_rides'];
    final ridesCount = rides is int ? rides : int.tryParse(rides?.toString() ?? '0') ?? 0;
    final averageRating = double.tryParse(d['average_rating']?.toString() ?? '0') ?? 0;
    final reviewCount = int.tryParse(d['review_count']?.toString() ?? '0') ?? 0;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF0A2540).withOpacity(0.1),
              child: const Icon(Icons.person, color: Color(0xFF0A2540)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(d['name']?.toString() ?? 'Driver',
                style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rides summary chip
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    Text('$ridesCount',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                            color: Colors.green.shade700)),
                    Text('Total Rides',
                        style: TextStyle(color: Colors.green.shade600, fontSize: 13)),
                  ],
                ),
              ),
              const Text('PERSONAL INFO', style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 8),
              _dRow('Email',   d['email']?.toString()  ?? '-'),
              _dRow('Phone',   d['phone']?.toString()  ?? '-'),
              _dRow('Gender',  d['gender']?.toString() ?? '-'),
              _dRow('City',    d['city']?.toString()   ?? '-'),
              _dRow('Average Rating', reviewCount == 0 ? 'No reviews yet' : '${averageRating.toStringAsFixed(1)} / 5'),
              _dRow('Total Reviews', reviewCount.toString()),
              _dRow('CNIC',    d['cnic']?.toString()   ?? '-'),
              _dRow('License', d['driving_license_no']?.toString() ?? '-'),
              _dRow('Address', d['address']?.toString() ?? '-'),
              const SizedBox(height: 14),
              const Text('VEHICLE', style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 8),
              _dRow('Car',      '${d['make'] ?? '-'} ${d['model'] ?? ''}'.trim()),
              _dRow('Color',    d['color']?.toString()    ?? '-'),
              _dRow('Plate',    d['plate_no']?.toString() ?? '-'),
              _dRow('Seats',    d['seats']?.toString()    ?? '-'),
            ],
          ),
        ),
          actions: [
          if (userId != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _verify(userId, 'suspended');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Suspend', style: TextStyle(color: Colors.white)),
            ),
          if (userId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => DriverRidesPage(driverId: userId)));
              },
              child: const Text('View Rides'),
            ),
          if (userId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _openDriverReviews(userId);
              },
              child: const Text('View Reviews'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showAllDriverDetails(Map d) {
    final rawId = d['user_id'] ?? d['id'];
    final userId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final rides = d['total_rides'];
    final ridesCount = rides is int ? rides : int.tryParse(rides?.toString() ?? '0') ?? 0;
    String selectedStatus = (d['verification_status']?.toString() ?? 'pending').toLowerCase();
    final averageRating = double.tryParse(d['average_rating']?.toString() ?? '0') ?? 0;
    final reviewCount = int.tryParse(d['review_count']?.toString() ?? '0') ?? 0;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF0A2540).withOpacity(0.1),
                child: const Icon(Icons.person, color: Color(0xFF0A2540)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  d['name']?.toString() ?? 'Driver',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _statusColor(selectedStatus).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _statusColor(selectedStatus).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$ridesCount',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      Text(
                        'Total Rides',
                        style: TextStyle(color: Colors.green.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reviewCount == 0 ? 'No reviews yet' : '${averageRating.toStringAsFixed(1)} / 5 from $reviewCount reviews',
                        style: TextStyle(color: Colors.green.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'VERIFICATION STATUS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                    DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setDialogState(() => selectedStatus = v);
                  },
                ),
                const SizedBox(height: 14),
                const Text(
                  'PERSONAL INFO',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                _dRow('Email',   d['email']?.toString()  ?? '-'),
                _dRow('Phone',   d['phone']?.toString()  ?? '-'),
                _dRow('Gender',  d['gender']?.toString() ?? '-'),
                _dRow('City',    d['city']?.toString()   ?? '-'),
                _dRow('Average Rating', reviewCount == 0 ? 'No reviews yet' : '${averageRating.toStringAsFixed(1)} / 5'),
                _dRow('Total Reviews', reviewCount.toString()),
                _dRow('CNIC',    d['cnic']?.toString()   ?? '-'),
                _dRow('License', d['driving_license_no']?.toString() ?? '-'),
                _dRow('Address', d['address']?.toString() ?? '-'),
                const SizedBox(height: 14),
                const Text(
                  'VEHICLE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                _dRow('Car', '${d['make'] ?? '-'} ${d['model'] ?? ''}'.trim()),
                _dRow('Color', d['color']?.toString() ?? '-'),
                _dRow('Plate', d['plate_no']?.toString() ?? '-'),
                _dRow('Seats', d['seats']?.toString() ?? '-'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            if (userId != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _verify(userId, selectedStatus);
                },
                style: ElevatedButton.styleFrom(backgroundColor: _statusColor(selectedStatus)),
                child: const Text('Update Status', style: TextStyle(color: Colors.white)),
              ),
            if (userId != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openDriverReviews(userId);
                },
                child: const Text('View Reviews'),
              ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────

  Widget _dRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _emptyState(IconData icon, String title, String sub) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(sub, style: const TextStyle(color: Colors.grey)),
        ]),
      );

  Widget _errorState(String msg, VoidCallback retry) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: retry, child: const Text('Retry')),
        ]),
      );

  String _statusLabel(String? rawStatus) {
    final status = (rawStatus ?? '').toLowerCase();
    if (status == 'approved') return 'Approved';
    if (status == 'pending') return 'Pending';
    if (status == 'suspended') return 'Suspended';
    if (status == 'rejected') return 'Rejected';
    return 'Unknown';
  }

  Color _statusColor(String? rawStatus) {
    final status = (rawStatus ?? '').toLowerCase();
    if (status == 'approved') return Colors.green;
    if (status == 'pending') return Colors.orange;
    if (status == 'suspended') return const Color(0xFF8E6A00);
    if (status == 'rejected') return Colors.red;
    return Colors.blueGrey;
  }

  // ── Pending Tab ────────────────────────────────────────────────

  Widget _pendingTab() {
    if (_loadingPending) return const Center(child: CircularProgressIndicator());
    if (_errorPending != null) return _errorState(_errorPending!, _fetchPending);
    if (_pending.isEmpty) return _emptyState(Icons.check_circle_outline,
        'No Pending Drivers', 'All applications have been reviewed.');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Name',    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Email',   style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('CNIC',    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('License', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Action',  style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _pending.map<DataRow>((d) => DataRow(cells: [
            DataCell(Text(d['name']?.toString()              ?? '-')),
            DataCell(Text(d['email']?.toString()             ?? '-')),
            DataCell(Text(d['cnic']?.toString()              ?? '-')),
            DataCell(Text(d['driving_license_no']?.toString() ?? '-')),
            DataCell(ElevatedButton(
              onPressed: () => _showPendingDetails(d as Map),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Review', style: TextStyle(color: Colors.white)),
            )),
          ])).toList(),
        ),
      ),
    );
  }

  // ── Approved Tab ───────────────────────────────────────────────

  Widget _approvedTab() {
    if (_loadingApproved) return const Center(child: CircularProgressIndicator());
    if (_errorApproved != null) return _errorState(_errorApproved!, _fetchApproved);
    if (_approved.isEmpty) return _emptyState(Icons.group_outlined,
        'No Approved Drivers Yet', 'Approve pending drivers to see them here.');

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 168,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _approved.length,
      itemBuilder: (_, i) {
        final d = _approved[i] as Map;
        final rides = d['total_rides'];
        final ridesCount = rides is int ? rides : int.tryParse(rides?.toString() ?? '0') ?? 0;
        final averageRating = double.tryParse(d['average_rating']?.toString() ?? '0') ?? 0;
        final reviewCount = int.tryParse(d['review_count']?.toString() ?? '0') ?? 0;
        return GestureDetector(
          onTap: () => _showApprovedDetails(d),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF0A2540).withOpacity(0.1),
                      child: const Icon(Icons.person, color: Color(0xFF0A2540), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(d['name']?.toString() ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Text('Active', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(d['email']?.toString() ?? '-',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.directions_car, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text('${d['make'] ?? '-'} ${d['model'] ?? ''}'.trim(),
                        style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.route, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text('$ridesCount rides', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    reviewCount == 0 ? 'No reviews yet' : 'Rating ${averageRating.toStringAsFixed(1)} from $reviewCount reviews',
                    style: TextStyle(
                      fontSize: 12,
                      color: reviewCount == 0 ? Colors.grey : (averageRating < 3.5 ? Colors.red : Colors.teal),
                      fontWeight: reviewCount == 0 ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _allDriversTab() {
    if (_loadingAll) return const Center(child: CircularProgressIndicator());
    if (_errorAll != null) return _errorState(_errorAll!, _fetchAllDrivers);
    if (_allDrivers.isEmpty) return _emptyState(Icons.people_alt_outlined,
        'No Drivers Found', 'Driver profiles will appear here once created.');

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 168,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _allDrivers.length,
      itemBuilder: (_, i) {
        final d = _allDrivers[i] as Map;
        final rides = d['total_rides'];
        final ridesCount = rides is int ? rides : int.tryParse(rides?.toString() ?? '0') ?? 0;
        final status = d['verification_status']?.toString() ?? '';
        final statusColor = _statusColor(status);
        final averageRating = double.tryParse(d['average_rating']?.toString() ?? '0') ?? 0;
        final reviewCount = int.tryParse(d['review_count']?.toString() ?? '0') ?? 0;
        return GestureDetector(
          onTap: () => _showAllDriverDetails(d),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF0A2540).withOpacity(0.1),
                      child: const Icon(Icons.person, color: Color(0xFF0A2540), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(d['name']?.toString() ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(_statusLabel(status), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(d['email']?.toString() ?? '-',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.directions_car, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text('${d['make'] ?? '-'} ${d['model'] ?? ''}'.trim(),
                        style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.route, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text('$ridesCount rides', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    reviewCount == 0 ? 'No reviews yet' : 'Rating ${averageRating.toStringAsFixed(1)} from $reviewCount reviews',
                    style: TextStyle(
                      fontSize: 12,
                      color: reviewCount == 0 ? Colors.grey : (averageRating < 3.5 ? Colors.red : Colors.teal),
                      fontWeight: reviewCount == 0 ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<dynamic> get _filteredReviews {
    return _reviews.where((item) {
      final review = item as Map;
      final rating = int.tryParse(review['rating']?.toString() ?? '0') ?? 0;
      final reviewer = review['reviewer_name']?.toString().toLowerCase() ?? '';
      final reviewee = review['reviewee_name']?.toString().toLowerCase() ?? '';
      final route = '${review['pickup_location'] ?? ''} ${review['destination'] ?? ''}'.toLowerCase();
      final comment = review['comment']?.toString().toLowerCase() ?? '';
      final createdAt = DateTime.tryParse(review['created_at']?.toString() ?? '');

      if (_reviewDriverFilter != null && review['reviewee_id']?.toString() != _reviewDriverFilter.toString()) {
        return false;
      }
      if (_reviewRatingFilter != null && rating != _reviewRatingFilter) {
        return false;
      }
      if (_reviewSearch.trim().isNotEmpty) {
        final needle = _reviewSearch.trim().toLowerCase();
        final haystack = '$reviewer $reviewee $route $comment'.toLowerCase();
        if (!haystack.contains(needle)) return false;
      }
      if (_reviewDateRange != null && createdAt != null) {
        final start = DateTime(_reviewDateRange!.start.year, _reviewDateRange!.start.month, _reviewDateRange!.start.day);
        final end = DateTime(_reviewDateRange!.end.year, _reviewDateRange!.end.month, _reviewDateRange!.end.day, 23, 59, 59, 999);
        if (createdAt.isBefore(start) || createdAt.isAfter(end)) return false;
      }
      return true;
    }).toList();
  }

  Widget _reviewStars(double rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          final active = index < rating.round();
          return Icon(
            active ? Icons.star_rounded : Icons.star_border_rounded,
            size: 16,
            color: active ? const Color(0xFFFFB703) : Colors.grey.shade400,
          );
        }),
      );

  Widget _statusChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );

  Widget _reviewsTab() {
    if (_loadingReviews) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorReviews != null) {
      return _errorState(_errorReviews!, _fetchReviews);
    }

    final filtered = _filteredReviews;
    final totalReviews = _reviews.length;
    final averageRating = totalReviews == 0
        ? 0
        : _reviews
            .map((item) => double.tryParse((item as Map)['rating']?.toString() ?? '0') ?? 0)
            .fold<double>(0, (sum, value) => sum + value) /
            totalReviews;
    final lowRatedDrivers = _allDrivers.where((item) {
      final driver = item as Map;
      final average = double.tryParse(driver['average_rating']?.toString() ?? '0') ?? 0;
      final count = int.tryParse(driver['review_count']?.toString() ?? '0') ?? 0;
      return count > 0 && average < 3.5;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _statChip(totalReviews.toString(), 'All Reviews', Colors.blueGrey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statChip(averageRating == 0 ? '0.0' : averageRating.toStringAsFixed(1), 'Avg Rating', Colors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statChip(lowRatedDrivers.toString(), 'Low Rated', Colors.redAccent),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search reviews or drivers',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onChanged: (value) => setState(() => _reviewSearch = value),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<int?>(
                value: _reviewRatingFilter,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                items: const [
                  DropdownMenuItem<int?>(value: null, child: Text('All')),
                  DropdownMenuItem<int?>(value: 5, child: Text('5★')),
                  DropdownMenuItem<int?>(value: 4, child: Text('4★')),
                  DropdownMenuItem<int?>(value: 3, child: Text('3★')),
                  DropdownMenuItem<int?>(value: 2, child: Text('2★')),
                  DropdownMenuItem<int?>(value: 1, child: Text('1★')),
                ],
                onChanged: (value) => setState(() => _reviewRatingFilter = value),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: (_reviewSearch.isEmpty && _reviewRatingFilter == null && _reviewDriverFilter == null)
                  ? null
                  : () {
                      setState(() {
                        _reviewSearch = '';
                        _reviewRatingFilter = null;
                        _reviewDriverFilter = null;
                      });
                    },
              icon: const Icon(Icons.clear_all_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: _reviewDateRange,
                    helpText: 'Filter review dates',
                  );
                  if (picked == null) return;
                  setState(() => _reviewDateRange = picked);
                },
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  _reviewDateRange == null
                      ? 'Date range'
                      : '${DateFormat('MMM d').format(_reviewDateRange!.start)} - ${DateFormat('MMM d').format(_reviewDateRange!.end)}',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0A2540),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _reviewDateRange == null ? null : () => setState(() => _reviewDateRange = null),
              child: const Text('Clear date'),
            ),
          ],
        ),
        if (_reviewDriverFilter != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text('Driver filter: #$_reviewDriverFilter'),
              backgroundColor: Colors.blueGrey.shade50,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(Icons.rate_review_outlined, 'No reviews found', 'Use the filters above to narrow the list.')
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final review = filtered[i] as Map;
                    final rating = double.tryParse(review['rating']?.toString() ?? '0') ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF0A2540).withOpacity(0.08),
                                  child: const Icon(Icons.person, color: Color(0xFF0A2540)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${review['reviewee_name']?.toString() ?? 'Driver'} reviewed by ${review['reviewer_name']?.toString() ?? 'User'}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      _reviewStars(rating),
                                    ],
                                  ),
                                ),
                                Text(
                                  DateFormat('MMM d, yyyy').format(DateTime.parse(review['created_at'].toString()).toLocal()),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${review['pickup_location']?.toString() ?? '-'} → ${review['destination']?.toString() ?? '-'}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              review['comment']?.toString().isNotEmpty == true ? review['comment'].toString() : 'No comment provided.',
                              style: const TextStyle(color: Colors.black87),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statusChip('Driver avg ${double.tryParse(review['reviewee_average_rating']?.toString() ?? '0')?.toStringAsFixed(1) ?? '0.0'}', Colors.green),
                                _statusChip('${review['reviewee_review_count']?.toString() ?? '0'} reviews', Colors.blueGrey),
                                _statusChip(review['ride_status']?.toString() ?? 'unknown', Colors.indigo),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            backgroundColor: const Color(0xFF0A2540),
            selectedIndex: 0,
            extended: true,
            minExtendedWidth: 200,
            onDestinationSelected: (_) {},
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white70),
                    tooltip: 'Logout',
                    onPressed: _logout,
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.admin_panel_settings, color: Colors.white),
                label: Text('Driver Management', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),

          // Main
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Driver Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              Text('Review pending applications and monitor active drivers',
                                  style: TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                          const Spacer(),
                          // Stats chips
                          _statChip('${_pending.length}', 'Pending', Colors.orange),
                          const SizedBox(width: 10),
                          _statChip('${_approved.length}', 'Active', Colors.green),
                          const SizedBox(width: 10),
                          _statChip('${_allDrivers.length}', 'All', Colors.blueGrey),
                          const SizedBox(width: 10),
                          _statChip('${_reviews.length}', 'Reviews', Colors.indigo),
                          const SizedBox(width: 10),
                          _statChip(
                            '${_sosEvents.where((e) => (e as Map)['status'] == 'active').length}',
                            'SOS Active',
                            Colors.red,
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh',
                            onPressed: () { _fetchPending(); _fetchApproved(); _fetchAllDrivers(); _fetchReviews(); _fetchSosEvents(); },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TabBar(
                        controller: _tabs,
                        labelColor: const Color(0xFF0A2540),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF0A2540),
                        indicatorWeight: 3,
                        tabs: [
                          Tab(text: 'Pending Approval  (${_pending.length})'),
                          Tab(text: 'Active Drivers  (${_approved.length})'),
                          Tab(text: 'All Drivers  (${_allDrivers.length})'),
                          Tab(text: 'Reviews  (${_reviews.length})'),
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_sosEvents.any((e) => (e as Map)['status'] == 'active'))
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text('SOS Events  (${_sosEvents.length})'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      Padding(padding: const EdgeInsets.all(24), child: _pendingTab()),
                      Padding(padding: const EdgeInsets.all(24), child: _approvedTab()),
                      Padding(padding: const EdgeInsets.all(24), child: _allDriversTab()),
                      Padding(padding: const EdgeInsets.all(24), child: _reviewsTab()),
                      Padding(padding: const EdgeInsets.all(24), child: _sosTab()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── SOS Events Tab ────────────────────────────────────────────

  Widget _sosTab() {
    if (_loadingSos) return const Center(child: CircularProgressIndicator());
    if (_errorSos != null) return _errorState(_errorSos!, _fetchSosEvents);

    // Filter locally for the search box (re-fetch is used for status filter)
    final filtered = _sosEvents.where((e) {
      final ev = e as Map;
      if (_sosSearch.isEmpty) return true;
      final q = _sosSearch.toLowerCase();
      return (ev['user_name']?.toString().toLowerCase().contains(q) ?? false) ||
             (ev['user_email']?.toString().toLowerCase().contains(q) ?? false) ||
             (ev['user_phone']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();

    final activeCount = filtered.where((e) => (e as Map)['status'] == 'active').length;
    final resolvedCount = filtered.where((e) => (e as Map)['status'] == 'resolved').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter bar
        Row(
          children: [
            // Search field
            SizedBox(
              width: 280,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by name, email, phone…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => _sosSearch = v),
              ),
            ),
            const SizedBox(width: 12),
            // Status filter chips
            _filterChip('All', _sosStatusFilter == 'all', Colors.blueGrey, () {
              setState(() => _sosStatusFilter = 'all');
              _fetchSosEvents();
            }),
            const SizedBox(width: 6),
            _filterChip('Active', _sosStatusFilter == 'active', Colors.red, () {
              setState(() => _sosStatusFilter = 'active');
              _fetchSosEvents();
            }),
            const SizedBox(width: 6),
            _filterChip('Resolved', _sosStatusFilter == 'resolved', Colors.green, () {
              setState(() => _sosStatusFilter = 'resolved');
              _fetchSosEvents();
            }),
            const Spacer(),
            // Summary chips
            _statChip('$activeCount', 'Active', Colors.red),
            const SizedBox(width: 8),
            _statChip('$resolvedCount', 'Resolved', Colors.green),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _fetchSosEvents,
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (filtered.isEmpty)
          Expanded(child: _emptyState(Icons.sos_rounded, 'No SOS Events', 'No emergencies have been reported.'))
        else
          Expanded(
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('ID',       style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status',   style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('User',     style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Role',     style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Route',    style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Driver',   style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Activated',style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Resolved', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: filtered.map<DataRow>((e) {
                    final ev = e as Map;
                    final isActive = ev['status'] == 'active';
                    final statusColor = isActive ? Colors.red : Colors.green;
                    final lat = ev['latitude']?.toString();
                    final lng = ev['longitude']?.toString();
                    final hasLocation = lat != null && lng != null && lat.isNotEmpty && lng.isNotEmpty;
                    final route = [ev['pickup_location'], ev['destination']]
                        .where((s) => s != null && s.toString().isNotEmpty)
                        .join(' → ');

                    return DataRow(
                      color: isActive
                          ? WidgetStateProperty.all(Colors.red.shade50)
                          : null,
                      cells: [
                        DataCell(Text('#${ev['sos_id'] ?? ev['id'] ?? '-'}')),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withOpacity(0.4)),
                          ),
                          child: Text(
                            isActive ? 'ACTIVE' : 'RESOLVED',
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        )),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ev['user_name']?.toString() ?? '-',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(ev['user_phone']?.toString() ?? ev['user_email']?.toString() ?? '-',
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (ev['role'] == 'driver' ? Colors.blue : Colors.purple).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            (ev['role']?.toString() ?? 'unknown').toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: ev['role'] == 'driver' ? Colors.blue : Colors.purple,
                            ),
                          ),
                        )),
                        DataCell(Text(route.isEmpty ? '-' : route,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(ev['driver_name']?.toString() ?? '-',
                            style: const TextStyle(fontSize: 12))),
                        DataCell(Text(_formatSosTime(ev['activated_at']?.toString()),
                            style: const TextStyle(fontSize: 12))),
                        DataCell(Text(
                          isActive ? '—' : _formatSosTime(ev['deactivated_at']?.toString()),
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive ? Colors.grey : Colors.green,
                          ),
                        )),
                        DataCell(
                          hasLocation
                              ? TextButton.icon(
                                  icon: const Icon(Icons.map_outlined, size: 14),
                                  label: const Text('View', style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _showSosLocationDialog(ev),
                                )
                              : const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.grey.shade600,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _formatSosTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  void _showSosLocationDialog(Map ev) {
    final lat = ev['latitude']?.toString() ?? '';
    final lng = ev['longitude']?.toString() ?? '';
    final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.location_on, color: Colors.red),
          const SizedBox(width: 8),
          Text('Location — ${ev['user_name'] ?? 'User'}'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dRow('Latitude',  lat),
            _dRow('Longitude', lng),
            const SizedBox(height: 12),
            SelectableText(
              mapsUrl,
              style: const TextStyle(color: Colors.blue, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text('Copy the link above and open in a browser to view on Google Maps.',
                style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _statChip(String count, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Text(count, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ]),
      );
}
