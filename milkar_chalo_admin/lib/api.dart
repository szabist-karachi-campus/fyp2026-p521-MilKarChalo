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
/// PHYSICAL DEVICE:   http://192.168.2.106:4000  (set [_overrideBase] below)
/// WEB:               use same-origin or set override
/// ------------------------------------------------------------
const String _lanIp =
    ''; // set your local LAN IP if needed for physical device testing
String?
_overrideBase; // set at runtime if you want: Api.setBase('http://192.168.1.50:4000')

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
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static String? _bearerToken;

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
      final streamedResponse = await request.send().timeout(_defaultTimeout);
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
  static Future<Map> saveVehicle(Map<String, String> fields) =>
      _postMultipart('/profile/vehicle', fields: fields);

  static Future<Map> postRide(Map data) async {
    return await post('/rides/post', data);
  }

  static Future<List<dynamic>> searchRides(Map<String, String> filters) async {
    final resp = await get('/rides/search', query: filters);
    return resp['data'] ?? []; // Adjust based on your _safeJsonDecode structure
  }

  // Admin helpers
  static Future<Map> getDriverRides(int driverId) async {
    return await get('/admin/drivers/$driverId/rides');
  }

  static Future<Map> getRideDetailsAdmin(int rideId) async {
    return await get('/admin/rides/$rideId');
  }

  /// Update a booking's status (accepted|rejected|canceled)
  static Future<Map> updateBookingStatus(int bookingId, String status) async {
    return await post('/admin/bookings/$bookingId/status', {'status': status});
  }

  /// Change a ride's status (active|started|completed|canceled)
  static Future<Map> changeRideStatus(int rideId, String status) async {
    return await post('/admin/rides/$rideId/status', {'status': status});
  }

  /// Export ride bookings as CSV (backend returns CSV string in payload)
  static Future<Map> exportRideCsv(int rideId) async {
    return await get('/admin/rides/$rideId/export');
  }

  static Future<Map<String, dynamic>> getAdminReviews({
    int? driverId,
    int? rating,
    String? search,
    String? from,
    String? to,
  }) async {
    final query = <String, String>{};
    if (driverId != null) query['driverId'] = driverId.toString();
    if (rating != null) query['rating'] = rating.toString();
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;
    return await get('/admin/reviews', query: query.isEmpty ? null : query);
  }

  static Future<Map<String, dynamic>> getAdminSosEvents({
    String? status,   // 'active' | 'resolved' | null (all)
    String? from,     // YYYY-MM-DD
    String? to,       // YYYY-MM-DD
    String? search,   // name / email / phone
  }) async {
    final query = <String, String>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (from != null && from.isNotEmpty) query['from'] = from;
    if (to != null && to.isNotEmpty) query['to'] = to;
    if (search != null && search.isNotEmpty) query['search'] = search;
    return await get('/admin/sos-events', query: query.isEmpty ? null : query);
  }
}
