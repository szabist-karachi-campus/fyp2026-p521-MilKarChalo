import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api.dart';
import '../../../router.dart';

const Color kNavy = Color(0xFF0A2540);
const Color kLightGrey = Color(0xFFF7F8F9);
const Color kGreyText = Color(0xFF6C757D);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _displayName;
  String? _displayEmail;
  String? _avatarUrl;
  String? _displayRole;
  bool _inited = false;
  bool _loadingProfile = false;
  double _averageRating = 0;
  int _reviewCount = 0;

  // Vehicle data
  String? _vehicleMake;
  String? _vehicleModel;
  String? _vehicleColor;
  String? _vehiclePlate;
  String? _vehicleSeats;

  // Driver verification status
  String? _verificationStatus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _loadUser();
  }

  // STEP 1: load from SharedPreferences immediately so screen shows instantly
  // STEP 2: then fetch fresh data from the server in background
  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {};

    setState(() {
      _displayName  = args['name']      as String? ?? prefs.getString('user_name')  ?? '';
      _displayEmail = args['email']     as String? ?? prefs.getString('user_email') ?? '';
      _avatarUrl    = args['avatarUrl'] as String? ?? prefs.getString('user_avatar');
      _displayRole  = args['role']      as String? ?? prefs.getString('user_role');

      // Load vehicle data from SharedPreferences as initial values
      _vehicleMake  = prefs.getString('vehicle_make');
      _vehicleModel = prefs.getString('vehicle_model');
      _vehicleColor = prefs.getString('vehicle_color');
      _vehiclePlate = prefs.getString('vehicle_plate');
      _vehicleSeats = prefs.getString('vehicle_total_seats');
    });

    // Now fetch fresh data from the server to ensure vehicle info is up to date
    _fetchProfileFromServer(prefs);
  }

  Future<void> _fetchProfileFromServer(SharedPreferences prefs) async {
    setState(() => _loadingProfile = true);
    try {
      final resp = await Api.get('/profile/me');
      if (!mounted) return;

      final user    = resp['user']    as Map?;
      final vehicle = resp['vehicle'] as Map?;
      final driver  = resp['driver']  as Map?;

      if (user != null) {
        final name   = user['name']?.toString()      ?? _displayName  ?? '';
        final email  = user['email']?.toString()     ?? _displayEmail ?? '';
        final avatar = user['image_url']?.toString() ?? _avatarUrl    ?? '';
        final role   = user['role']?.toString()      ?? _displayRole  ?? '';
        final averageRating = double.tryParse(user['average_rating']?.toString() ?? '0') ?? 0;
        final reviewCount = int.tryParse(user['review_count']?.toString() ?? '0') ?? 0;

        await prefs.setString('user_name',   name);
        await prefs.setString('user_email',  email);
        await prefs.setString('user_avatar', avatar);
        await prefs.setString('user_role',   role);

        setState(() {
          _displayName  = name;
          _displayEmail = email;
          _avatarUrl    = avatar;
          _displayRole  = role;
          _averageRating = averageRating;
          _reviewCount = reviewCount;
        });
      }

      if (driver != null) {
        setState(() => _verificationStatus = driver['verification_status']?.toString());
      }

      // FIX: Update vehicle data from server — this is the fix for Issue #1
      if (vehicle != null) {
        final make  = vehicle['make']?.toString()        ?? '';
        final model = vehicle['model']?.toString()       ?? '';
        final color = vehicle['color']?.toString()       ?? '';
        final plate = vehicle['plate_no']?.toString()    ?? '';
        final seats = vehicle['total_seats']?.toString() ?? '';

        await prefs.setString('vehicle_make',        make);
        await prefs.setString('vehicle_model',       model);
        await prefs.setString('vehicle_color',       color);
        await prefs.setString('vehicle_plate',       plate);
        await prefs.setString('vehicle_total_seats', seats);

        setState(() {
          _vehicleMake  = make.isNotEmpty  ? make  : null;
          _vehicleModel = model.isNotEmpty ? model : null;
          _vehicleColor = color.isNotEmpty ? color : null;
          _vehiclePlate = plate.isNotEmpty ? plate : null;
          _vehicleSeats = seats.isNotEmpty ? seats : null;
        });
      }
    } catch (e) {
      // Silently fail — we already have SharedPreferences data on screen
      debugPrint('⚠️ ProfilePage: Could not fetch fresh profile: $e');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  void _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('⚠️ Failed to clear user prefs: $e');
    }
    Api.setToken(null);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.welcome, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDriver = _displayRole?.toLowerCase() == 'driver';

    String? fullAvatarUrl;
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      if (_avatarUrl!.startsWith('http')) {
        fullAvatarUrl = _avatarUrl;
      } else {
        final baseUrl = ApiConfig.base;
        final avatarPath = _avatarUrl!.startsWith('/') ? _avatarUrl!.substring(1) : _avatarUrl!;
        fullAvatarUrl = '$baseUrl/$avatarPath';
      }
    }

    final hasVehicle = isDriver && _vehicleMake != null && _vehicleMake!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kNavy),
          onPressed: () {
            if (isDriver) {
              Navigator.pushReplacementNamed(context, AppRoutes.driverDashboard);
            } else {
              Navigator.pushReplacementNamed(context, AppRoutes.passengerDashboard);
            }
          },
        ),
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        actions: [
          if (_loadingProfile)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Avatar ──
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: kLightGrey,
                  child: fullAvatarUrl == null
                      ? const Icon(Icons.person, size: 50, color: kNavy)
                      : ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: fullAvatarUrl,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const CircularProgressIndicator(),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.person, size: 50, color: kNavy),
                          ),
                        ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kNavy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _displayName ?? '',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 4),
            Text(
              _displayEmail ?? '',
              style: theme.textTheme.bodyLarge?.copyWith(color: kGreyText),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_rounded, color: _reviewCount > 0 ? Colors.amber.shade700 : Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(
                    _reviewCount > 0 ? _averageRating.toStringAsFixed(1) : 'No reviews yet',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  if (_reviewCount > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '($_reviewCount reviews)',
                      style: const TextStyle(color: kGreyText, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (isDriver)
              Chip(
                avatar: const Icon(Icons.shield, color: kNavy, size: 16),
                label: const Text('DRIVER'),
                backgroundColor: kNavy.withOpacity(0.1),
                labelStyle: const TextStyle(color: kNavy, fontWeight: FontWeight.bold),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),

            // ── Verification Status Badge ──
            if (isDriver && _verificationStatus != null) ...[
              const SizedBox(height: 8),
              _VerificationBadge(status: _verificationStatus!),
            ],

            // ── Vehicle Info Card ──
            if (hasVehicle) ...[
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'MY VEHICLE',
                  style: TextStyle(
                      color: kGreyText, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kLightGrey,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: kNavy.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.directions_car, color: kNavy),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_vehicleMake ?? ''} ${_vehicleModel ?? ''}'.trim(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _VehicleInfoRow(label: 'Color',       value: _vehicleColor ?? '-'),
                    const SizedBox(height: 6),
                    _VehicleInfoRow(label: 'Plate No.',   value: _vehiclePlate ?? '-'),
                    const SizedBox(height: 6),
                    _VehicleInfoRow(label: 'Total Seats', value: _vehicleSeats ?? '-'),
                  ],
                ),
              ),
            ] else if (isDriver && !_loadingProfile) ...[
              // Driver has no vehicle registered yet
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'No vehicle registered. Add your vehicle to start posting rides.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Account Settings ──
            const SizedBox(height: 32),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ACCOUNT SETTINGS',
                style: TextStyle(
                    color: kGreyText, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
            const SizedBox(height: 16),
            _ProfileMenuItem(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              subtitle: 'Update your personal information',
              onTap: () {
                if (isDriver) {
                  Navigator.pushNamed(context, AppRoutes.editDriverProfile);
                } else {
                  Navigator.pushNamed(context, AppRoutes.editPassengerProfile);
                }
              },
            ),
            const SizedBox(height: 12),
            _ProfileMenuItem(
              icon: Icons.event_available_outlined,
              title: 'Upcoming Rides',
              subtitle: isDriver
                  ? 'View your upcoming posted rides'
                  : 'View your accepted upcoming rides',
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.upcomingRides);
              },
            ),
            const SizedBox(height: 12),
            _ProfileMenuItem(
              icon: Icons.history_outlined,
              title: 'Ride History',
              subtitle: isDriver
                  ? 'View past and completed rides'
                  : 'View your previous bookings',
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.rideHistory);
              },
            ),
            if (isDriver) ...[
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.inbox_outlined,
                title: 'Booking Requests',
                subtitle: 'Review new passenger booking requests',
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.bookingRequests);
                },
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.directions_car_outlined,
                title: 'Edit Vehicle',
                subtitle: 'Manage your registered car details',
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.editVehicle).then((_) {
                    // Refresh profile after returning from edit vehicle
                    _inited = false;
                    _loadUser();
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            _ProfileMenuItem(
              icon: Icons.reviews_outlined,
              title: 'Review History',
              subtitle: 'See ratings and comments you have received',
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.reviewHistory);
              },
            ),
            const SizedBox(height: 12),
            _ProfileMenuItem(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              subtitle: 'View our app policies and rules',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _ProfileMenuItem(
              icon: Icons.help_outline,
              title: 'Support',
              subtitle: 'Help center and contact us',
              onTap: () {},
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('Logout', style: TextStyle(color: Colors.white)),
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final String status;
  const _VerificationBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    IconData icon;
    String label;

    switch (status) {
      case 'approved':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        icon = Icons.verified;
        label = 'Approved — You can post rides';
        break;
      case 'rejected':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        icon = Icons.cancel;
        label = 'Rejected — Contact support';
        break;
      case 'suspended':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        icon = Icons.cancel;
        label = 'Suspended — Contact support';
        break;
      default:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
        icon = Icons.hourglass_top;
        label = 'Pending admin approval';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _VehicleInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _VehicleInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: kGreyText, fontSize: 14)),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)),
      ],
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kLightGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kNavy.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: kNavy),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: kGreyText, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kGreyText),
          ],
        ),
      ),
    );
  }
}
