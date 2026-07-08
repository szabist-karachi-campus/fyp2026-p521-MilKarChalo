import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException, SocketException, File;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

/// ------------------------------------------------------------
/// Base URL auto-detection
/// ANDROID EMULATOR:  http://10.0.2.2:4000
/// IOS SIMULATOR:     http://localhost:4000
/// PHYSICAL DEVICE:   http://172.16.166.136:4000  (set [_overrideBase] below)
/// WEB:               use same-origin or set override
/// ------------------------------------------------------------
const String _lanIp =
    'http://192.168.194.177:4000'; // set your local LAN IP if needed for physical device testing
String?
_overrideBase; // set at runtime if you want: Api.setBase('http://192.168.194.177:4000')

String get _autoBase {
  if (_overrideBase != null && _overrideBase!.isNotEmpty) return _overrideBase!;
  if (kIsWeb) return 'http://localhost:4000';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return _lanIp.isNotEmpty ? _lanIp : 'http://10.0.2.2:4000';
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return 'http://localhost:4000';
    default:
      return _lanIp.isNotEmpty ? _lanIp : 'http://localhost:4000';
  }
}

/// Public setter if you need to force a base (e.g., physical device testing)
class ApiConfig {
  static void setBase(String base) => _overrideBase = base;
  static String get base => _autoBase;
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  ApiException(this.message, {this.statusCode, this.data});
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class Api {
  static const Duration _defaultTimeout = Duration(seconds: 30); // FIX: was 15s
  static const Duration _uploadTimeout = Duration(
    seconds: 90,
  ); // FIX: image uploads need more time
  static String? _bearerToken;

  /// Exposes the current token so socket connections can authenticate.
  static String get bearerToken => _bearerToken ?? '';

  static void setToken(String? token) {
    _bearerToken = token;
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    final base = ApiConfig.base;
    final u = Uri.parse('$base$path');
    return (query == null || query.isEmpty)
        ? u
        : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  static Map<String, String> _headers([Map<String, String>? extra]) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_bearerToken != null && _bearerToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_bearerToken';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  static dynamic _safeJsonDecode(String src) {
    if (src.isEmpty) return {};
    try {
      return jsonDecode(src);
    } catch (_) {
      debugPrint('⚠️ API: Failed to parse JSON. Body was: $src');
      return {'message': 'Invalid response from server'};
    }
  }

  static ApiException _asApiError(http.Response res) {
    final body = _safeJsonDecode(res.body);
    final code = res.statusCode;
    String msg = (body is Map && body['message'] is String)
        ? body['message']
        : (body is Map && body['error'] is String)
        ? body['error']
        : 'Request failed ($code)';
    if (body is Map &&
        body['errors'] is List &&
        (body['errors'] as List).isNotEmpty) {
      final first = (body['errors'] as List).first;
      if (first is Map && first['msg'] is String) msg = first['msg'];
    }
    return ApiException(msg, statusCode: code, data: body);
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map? data,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = _uri(path, query);
    final h = _headers(headers);

    http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: h).timeout(timeout);
          break;
        case 'POST':
          res = await http
              .post(uri, headers: h, body: jsonEncode(data ?? {}))
              .timeout(timeout);
          break;
        case 'PUT':
          res = await http
              .put(uri, headers: h, body: jsonEncode(data ?? {}))
              .timeout(timeout);
          break;
        case 'DELETE':
          res = await http
              .delete(uri, headers: h, body: jsonEncode(data ?? {}))
              .timeout(timeout);
          break;
        default:
          throw ApiException('Unsupported method $method');
      }
    } on TimeoutException {
      throw ApiException('Request timed out. Please try again.');
    } on SocketException {
      throw ApiException(
        'Cannot reach server. Check your network or server URL.',
      );
    } on HttpException catch (e) {
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException('Unexpected error: $e');
    }

    if (res.statusCode >= 400) {
      debugPrint(
        '❌ API Error ${res.statusCode} on $path. Response: ${res.body}',
      );
      throw _asApiError(res);
    }

    final body = _safeJsonDecode(res.body);
    if (body is Map<String, dynamic>) return body;
    return {'data': body, 'ok': true};
  }

  static Future<Map<String, dynamic>> _postMultipart(
    String path, {
    required Map<String, String> fields,
    File? file,
    String fileField = 'image',
  }) async {
    final uri = _uri(path);
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll({
      if (_bearerToken != null) 'Authorization': 'Bearer $_bearerToken',
    });
    request.fields.addAll(fields);

    if (file != null) {
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      final multipartFile = http.MultipartFile(
        fileField,
        stream,
        length,
        filename: file.path.split('/').last,
        contentType: http.MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);
    }

    try {
      final streamedResponse = await request.send().timeout(
        _uploadTimeout,
      ); // FIX: use longer timeout for uploads
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode >= 400) {
        debugPrint(
          '❌ API Multipart Error ${response.statusCode} on $path. Response: ${response.body}',
        );
        throw _asApiError(response);
      }
      final body = _safeJsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
      return {'data': body, 'ok': true};
    } on SocketException {
      throw ApiException('Cannot reach server.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Upload failed: $e');
    }
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) => _request('GET', path, query: query);
  static Future<Map<String, dynamic>> post(String path, Map data) =>
      _request('POST', path, data: data);
  static Future<Map<String, dynamic>> put(String path, Map data) =>
      _request('PUT', path, data: data);
  static Future<Map<String, dynamic>> delete(String path, [Map? data]) =>
      _request('DELETE', path, data: data);

  static Future<Map> signup(Map dto) => post('/auth/register', dto);
  static Future<Map> login(Map dto) => post('/auth/login', dto);

  static Future<Map> sendOtp(Map dto) {
    final purpose = (dto['purpose'] as String?)?.toLowerCase() ?? 'signup';
    switch (purpose) {
      case 'signup':
        return post('/auth/resend-otp', {'email': dto['email']});
      case 'login':
        return post('/auth/resend-login-otp', {'email': dto['email']});
      case 'reset':
        return post('/auth/forgot', {'email': dto['email']});
      default:
        throw ApiException('Unknown OTP purpose: $purpose');
    }
  }

  static Future<Map> verifyOtp(Map dto) {
    final purpose = (dto['purpose'] as String?)?.toLowerCase() ?? 'signup';
    final email = dto['email'] as String;
    final code = dto['code'] as String;
    final payload = {'email': email, 'code': code};
    switch (purpose) {
      case 'signup':
        return post('/auth/verify-otp', payload);
      case 'login':
        return post('/auth/verify-login-otp', payload);
      case 'reset':
        return post('/auth/verify-reset', payload);
      default:
        throw ApiException('Unknown OTP purpose: $purpose');
    }
  }

  static Future<Map> resetPassword(Map dto) => post('/auth/reset', dto);

  static Future<Map> savePassengerProfile(
    Map<String, String> fields,
    File? file,
  ) => _postMultipart('/profile/passenger', fields: fields, file: file);
  static Future<Map> saveDriverProfile(
    Map<String, String> fields,
    File? file,
  ) => _postMultipart(
    '/profile/driver',
    fields: fields,
    file: file,
    fileField: 'image',
  );
  static Future<Map> saveVehicle(Map<String, String> fields) {
    // FIX: Vehicle has no file upload — send as JSON, NOT multipart.
    // When multipart is used without a multer middleware on the backend,
    // req.body is completely empty and every field fails validation.
    return post('/profile/vehicle', {
      'make': fields['make'] ?? '',
      'model': fields['model'] ?? '',
      'color': fields['color'] ?? '',
      'plate_no': fields['plate_no'] ?? '',
      'seats': int.tryParse(fields['seats'] ?? '') ?? 1,
    });
  }

  static Future<Map> postRide(Map data) async {
    return await post('/rides/post', data);
  }

  static Future<List<dynamic>> searchRides(Map<String, String> filters, {bool includeOccurrences = false}) async {
    if (includeOccurrences) {
      filters = {...filters, 'include_occurrences': 'true'};
    }
    final resp = await get('/rides/search', query: filters);
    final data = resp['data'];
    if (data is List) return data;
    return [];
  }

  static Future<Map> bookRide(int rideId, {int seatsRequested = 1}) async {
    return await post('/rides/book', {
      'ride_id': rideId,
      'seats_requested': seatsRequested,
    });
  }

  static Future<Map> bookRides(List<int> rideIds, {int seatsRequested = 1}) async {
    return await post('/rides/book', {
      'ride_ids': rideIds,
      'seats_requested': seatsRequested,
    });
  }

  static Future<Map<String, dynamic>> getMyProfile() => get('/profile/me');

  static Future<List<dynamic>> getBookingRequests() async {
    final resp = await get('/rides/booking-requests');
    final data = resp['data'];
    return data is List ? data : [];
  }

  static Future<Map> respondToBooking(int bookingId, String action) => post(
    '/rides/respond-booking',
    {'booking_id': bookingId, 'action': action},
  );

  static Future<Map> cancelBooking(int bookingId) => post(
    '/rides/bookings/$bookingId/cancel',
    {},
  );

  static Future<Map> cancelBookingGroup(String groupId) => post(
    '/rides/booking-groups/$groupId/cancel',
    {},
  );

  static Future<Map> submitReview(Map<String, dynamic> payload) => post('/rides/reviews', payload);

  static Future<Map<String, dynamic>> getReceivedReviews({
    String? from,
    String? to,
    int? rating,
  }) async {
    final query = <String, String>{};
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;
    if (rating != null && rating >= 1 && rating <= 5) query['rating'] = rating.toString();
    return await get('/rides/reviews/received', query: query.isEmpty ? null : query);
  }

  static Future<List<dynamic>> getMyBookings() async {
    final resp = await get('/rides/my-bookings');
    final data = resp['data'];
    return data is List ? data : [];
  }

  static Future<List<dynamic>> getMyRides() async {
    final resp = await get('/rides/my-rides');
    final data = resp['data'];
    return data is List ? data : [];
  }

  static Future<Map<String, dynamic>> getDriverRideDetails(int rideId, {int? occurrenceId}) async {
    final query = occurrenceId != null ? {'occurrence_id': '$occurrenceId'} : null;
    return await get('/rides/my-rides/$rideId', query: query);
  }

  static Future<Map> startDriverRide(int rideId) async {
    return await post('/rides/my-rides/$rideId/start', {});
  }

  static Future<Map> cancelDriverRide(int rideId) async {
    return await post('/rides/my-rides/$rideId/cancel', {});
  }

  static Future<Map> cancelDriverRoundTrip(int rideId) async {
    return await post('/rides/my-rides/$rideId/cancel-round-trip', {});
  }

  static Future<Map> endDriverRide(int rideId) async {
    return await post('/rides/my-rides/$rideId/end', {});
  }

  // ── Recurring rides ────────────────────────────────────────────────────────

  /// Fetch upcoming active occurrences for a recurring ride.
  static Future<List<dynamic>> getRideOccurrences(int rideId, {int limit = 30}) async {
    final resp = await get('/rides/$rideId/occurrences', query: {'limit': '$limit'});
    final data = resp['data'];
    return data is List ? data : [];
  }

  /// Book an occurrence of a recurring ride.
  static Future<Map> bookOccurrence(int rideId, int occurrenceId, {int seatsRequested = 1}) async {
    return await post('/rides/book', {
      'ride_id': rideId,
      'occurrence_id': occurrenceId,
      'seats_requested': seatsRequested,
    });
  }

  /// Book multiple occurrences of a recurring ride in one request.
  static Future<Map> bookOccurrences(int rideId, List<int> occurrenceIds, {int seatsRequested = 1}) async {
    return await post('/rides/book', {
      'ride_id': rideId,
      'occurrence_ids': occurrenceIds,
      'seats_requested': seatsRequested,
    });
  }

  /// Book paired occurrences of a recurring round-trip (both departure and return legs).
  static Future<Map> bookRecurringRoundTrip(
    int rideId,
    List<int> departureOccurrenceIds,
    List<int> returnOccurrenceIds, {
    int seatsRequested = 1,
  }) async {
    if (departureOccurrenceIds.length != returnOccurrenceIds.length) {
      throw ApiException('Departure and return occurrence counts must match.');
    }
    return await post('/rides/book', {
      'ride_id': rideId,
      'occurrence_ids': departureOccurrenceIds,
      'return_occurrence_ids': returnOccurrenceIds,
      'include_return_leg': true,
      'seats_requested': seatsRequested,
    });
  }

  /// Driver cancels a single occurrence.
  static Future<Map> cancelOccurrence(int occurrenceId) async {
    return await post('/rides/occurrences/$occurrenceId/cancel', {});
  }

  /// Driver cancels entire recurring series.
  static Future<Map> cancelRecurringSeries(int rideId) async {
    return await post('/rides/my-rides/$rideId/cancel-recurring', {});
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  /// 12.1 — Register or update the device's FCM token on the server.
  static Future<Map<String, dynamic>> registerFcmToken(String token) =>
      post('/notifications/fcm-token', {'fcm_token': token});

  /// 12.2 — Fetch the 50 most-recent notifications for the current user.
  static Future<List<dynamic>> getNotifications() async {
    final resp = await get('/notifications');
    final data = resp['data'];
    return data is List ? data : [];
  }

  /// 12.3 — Return the number of unread notifications for the current user.
  static Future<int> getUnreadCount() async {
    final resp = await get('/notifications/unread-count');
    final count = resp['count'];
    return count is int ? count : (count as num?)?.toInt() ?? 0;
  }

  /// 12.4 — Mark a single notification as read by its [id].
  static Future<Map<String, dynamic>> markRead(int id) =>
      post('/notifications/$id/read', {});

  /// 12.5 — Bulk-mark a list of notifications as read.
  /// Returns `{ ok: true, updated: N }`.
  static Future<Map<String, dynamic>> markReadBulk(List<int> ids) =>
      post('/notifications/read-bulk', {'ids': ids});

  // ── SOS ────────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getEmergencyContacts() async {
    final resp = await get('/sos/emergency-contacts');
    final data = resp['data'];
    return data is List ? data : [];
  }

  static Future<Map<String, dynamic>> addEmergencyContact(Map<String, dynamic> data) =>
      post('/sos/emergency-contacts', data);

  static Future<Map<String, dynamic>> updateEmergencyContact(int id, Map<String, dynamic> data) =>
      put('/sos/emergency-contacts/$id', data);

  static Future<Map<String, dynamic>> deleteEmergencyContact(int id) =>
      delete('/sos/emergency-contacts/$id');

  static Future<Map<String, dynamic>> activateSos({
    required int bookingId,
    double? latitude,
    double? longitude,
  }) =>
      post('/sos/activate', {
        'booking_id': bookingId,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      });

  static Future<Map<String, dynamic>> deactivateSos(int sosId) =>
      post('/sos/events/$sosId/deactivate', {});

  static Future<Map<String, dynamic>> getActiveSos(int bookingId) =>
      get('/sos/bookings/$bookingId/active');

  static Future<Map<String, dynamic>> updateSosLocation(
      int sosId, double latitude, double longitude) =>
      post('/sos/events/$sosId/location', {
        'latitude': latitude,
        'longitude': longitude,
      });

  // ── Places Autocomplete ────────────────────────────────────────────────────

  /// Returns up to 5 address suggestions from Google Places Autocomplete.
  /// The API key lives on the backend — this call never exposes it.
  static Future<List<Map<String, dynamic>>> getPlaces(String input) async {
    if (input.trim().length < 2) return [];
    final resp = await get('/rides/places', query: {'input': input.trim()});
    final data = resp['data'];
    if (data is List) {
      return data
          .map((e) => (e is Map)
              ? e.map((k, v) => MapEntry(k.toString(), v))
              : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  // ── ETA ────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getEta({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) =>
      get('/rides/eta', query: {
        'originLat': originLat.toString(),
        'originLng': originLng.toString(),
        'destLat': destLat.toString(),
        'destLng': destLng.toString(),
      });
}
