import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../core/api.dart';
import 'chat_service.dart';

const Color _navy = Color(0xFF0A2540);

class ChatPage extends StatefulWidget {
  final int bookingId;
  final String? counterpartName;

  const ChatPage({
    super.key,
    required this.bookingId,
    this.counterpartName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  IO.Socket? _socket;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  int? _conversationId;
  int? _currentUserId;
  bool _loading = true;
  bool _chatDisabled = false;
  bool _historyError = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
    _inputController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _init() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _initError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getInt('user_id');

      // Fallback: decode uid from the JWT token if user_id wasn't saved
      if (_currentUserId == null) {
        final token = Api.bearerToken;
        if (token.isNotEmpty) {
          try {
            final parts = token.split('.');
            if (parts.length == 3) {
              String payload = parts[1];
              // Pad base64url to a multiple of 4
              payload = base64Url.normalize(payload);
              final decoded = utf8.decode(base64Url.decode(payload));
              final claims = jsonDecode(decoded) as Map<String, dynamic>;
              final uid = claims['uid'];
              if (uid != null) {
                _currentUserId =
                    uid is int ? uid : int.tryParse(uid.toString());
              }
            }
          } catch (_) {}
        }
      }

      final conv = await ChatService.getOrCreateConversation(widget.bookingId)
          .timeout(const Duration(seconds: 10));

      final rawId = conv['id'];
      _conversationId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      if (_conversationId == null) throw Exception('Invalid conversation response');

      await _loadHistory();
      _connectSocket();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _loading = false;
        _chatDisabled = true;
        _initError = msg.contains('timed out') || msg.contains('timeout')
            ? 'Could not retrieve conversation. Please try again.'
            : msg.contains('403') || msg.contains('not available')
                ? 'Chat is not available for this booking.'
                : 'Could not retrieve conversation. Please try again.';
      });
    }
  }

  Future<void> _loadHistory() async {
    if (_conversationId == null) return;
    try {
      final msgs = await ChatService.getMessages(_conversationId!);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs.cast<Map<String, dynamic>>());
        _historyError = false;
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyError = true;
        _loading = false;
      });
    }
  }

  void _connectSocket() {
    final token = Api.bearerToken;
    final baseUrl = ApiConfig.base;

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('join_room', {'conversationId': _conversationId});
    });

    _socket!.on('new_message', (data) {
      if (!mounted) return;
      setState(() {
        _messages.add(Map<String, dynamic>.from(data as Map));
      });
      _scrollToBottom();
    });

    _socket!.on('chat_disabled', (_) {
      if (!mounted) return;
      setState(() => _chatDisabled = true);
    });

    _socket!.onReconnect((_) {
      _loadHistory();
      if (_conversationId != null && !_chatDisabled) {
        _socket!.emit('join_room', {'conversationId': _conversationId});
      }
    });

    _socket!.on('error', (data) {
      debugPrint('[ChatPage] socket error: $data');
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final content = _inputController.text.trim();
    if (content.isEmpty || _chatDisabled || _conversationId == null) return;
    _socket?.emit('send_message', {
      'conversationId': _conversationId,
      'content': content,
    });
    _inputController.clear();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        (widget.counterpartName?.trim().isNotEmpty == true)
            ? widget.counterpartName!
            : 'Your Ride Partner';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // History fetch error banner
          if (_historyError)
            Material(
              color: Colors.orange.shade50,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Could not load messages.',
                        style:
                            TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadHistory,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          // Chat disabled banner
          if (_chatDisabled && _initError == null)
            Material(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: const [
                    Icon(Icons.block, color: Colors.grey, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This chat is no longer available because the ride has ended or was cancelled.',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Init error state
          if (_initError != null && !_loading)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      _initError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _init,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          // Loading
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator())),

          // Message list
          if (!_loading && _initError == null)
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet. Say hello!',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final msg = _messages[i];
                        final senderId =
                            msg['sender_id'] ?? msg['senderId'];
                        final isOwn = senderId == _currentUserId ||
                            senderId?.toString() ==
                                _currentUserId?.toString();
                        return _MessageBubble(
                            message: msg, isOwn: isOwn);
                      },
                    ),
            ),

          // Input row (only when conversation loaded successfully)
          if (_initError == null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        enabled: !_chatDisabled,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _chatDisabled
                              ? 'Chat unavailable'
                              : 'Type a message…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.send_rounded),
                      color: _navy,
                      onPressed:
                          (_inputController.text.trim().isEmpty ||
                                  _chatDisabled)
                              ? null
                              : _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isOwn;

  const _MessageBubble({required this.message, required this.isOwn});

  @override
  Widget build(BuildContext context) {
    final sentAt =
        message['sent_at']?.toString() ?? message['sentAt']?.toString();
    final content = message['content']?.toString() ?? '';
    final timeStr = ChatService.formatMessageTime(sentAt);

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isOwn ? _navy : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOwn ? 16 : 4),
            bottomRight: Radius.circular(isOwn ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isOwn
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: TextStyle(
                color: isOwn ? Colors.white : Colors.black87,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                color: isOwn ? Colors.white60 : Colors.black38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
