import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../main.dart' show unreadCount;

const Color _navy = Color(0xFF0A2540);
const Color _unreadBg = Color(0xFFE3F2FD);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _markingAll = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Api.getNotifications();
      setState(() {
        _notifications = data
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Normalises is_read from bool or int (0/1) to a Dart bool.
  bool _isRead(Map<String, dynamic> n) {
    final raw = n['is_read'];
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    return false;
  }

  /// Tapping a single notification marks it read and decrements the badge.
  void _onTap(int index) {
    final n = _notifications[index];
    if (_isRead(n)) return;

    setState(() {
      _notifications[index] = {...n, 'is_read': true};
    });
    unreadCount.value = (unreadCount.value - 1).clamp(0, 1 << 30);

    final id = n['id'];
    if (id != null) {
      Api.markRead(id is int ? id : int.parse(id.toString())).catchError((e) {
        debugPrint('markRead failed: $e');
        return <String, dynamic>{};
      });
    }
  }

  /// Bulk-marks all unread notifications as read.
  Future<void> _markAllRead() async {
    final unreadIds = _notifications
        .where((n) => !_isRead(n))
        .map((n) {
          final id = n['id'];
          return id is int ? id : int.tryParse(id?.toString() ?? '');
        })
        .whereType<int>()
        .toList();

    if (unreadIds.isEmpty) return;

    // Optimistic update — reflect the change in the UI immediately
    setState(() {
      _markingAll = true;
      _notifications = _notifications
          .map((n) => _isRead(n) ? n : {...n, 'is_read': true})
          .toList();
    });

    // Reset the global badge to 0
    unreadCount.value = 0;

    try {
      await Api.markReadBulk(unreadIds);
    } catch (e) {
      debugPrint('markReadBulk failed: $e');
      // Silently swallow — local state already reflects the change
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  String _formatTime(String? raw) {
    try {
      final dt = DateTime.parse(raw ?? '').toLocal();
      return DateFormat('MMM d, yyyy  •  h:mm a').format(dt);
    } catch (_) {
      return raw ?? '-';
    }
  }

  bool get _hasUnread => _notifications.any((n) => !_isRead(n));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // "Mark all read" button — visible only when unread items exist
          if (_hasUnread)
            _markingAll
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _markAllRead,
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Could not load notifications',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No notifications yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "When something happens, you'll see it here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        itemBuilder: (_, i) => _buildItem(i),
      ),
    );
  }

  Widget _buildItem(int index) {
    final n = _notifications[index];
    final read = _isRead(n);

    final bgColor = read ? Colors.white : _unreadBg;
    final titleWeight = read ? FontWeight.normal : FontWeight.bold;

    return InkWell(
      onTap: () => _onTap(index),
      child: Container(
        color: bgColor,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread dot
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: read
                      ? Colors.transparent
                      : const Color(0xFF1565C0),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n['title']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: titleWeight,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n['body']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(n['created_at']?.toString()),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey,
                    ),
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
