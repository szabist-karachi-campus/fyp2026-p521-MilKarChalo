import 'package:intl/intl.dart';
import '../../core/api.dart';

class ChatService {
  /// Get or create a conversation for the given [bookingId].
  /// Returns the conversation map with keys: id, booking_id, created_at.
  static Future<Map<String, dynamic>> getOrCreateConversation(int bookingId) async {
    final resp = await Api.post('/chat/conversations', {'booking_id': bookingId});
    return resp;
  }

  /// Fetch all messages for [conversationId], ordered by sent_at ascending.
  static Future<List<dynamic>> getMessages(int conversationId) async {
    final resp = await Api.get('/chat/conversations/$conversationId/messages');
    final data = resp['data'];
    return data is List ? data : [];
  }

  /// Format a sent_at string as HH:mm in local timezone.
  /// Returns '--:--' on parse failure.
  static String formatMessageTime(String? sentAt) {
    if (sentAt == null || sentAt.isEmpty) return '--:--';
    try {
      DateTime dt;
      // Handle both ISO strings and MySQL DATETIME strings (space separator)
      final normalized = sentAt.replaceFirst(' ', 'T');
      dt = DateTime.parse(normalized).toLocal();
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return '--:--';
    }
  }
}
