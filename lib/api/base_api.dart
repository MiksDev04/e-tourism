import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../core/services/session_service.dart';

class BaseApi {
  String get baseUrl {
    if (kIsWeb) {
      return const String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: 'http://localhost:3000',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
    }
    return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
  }

  String? get apiKey {
    if (kIsWeb) {
      return const String.fromEnvironment('API_KEY', defaultValue: 'tourism_app_v2_secret_key_2026');
    }
    return dotenv.env['API_KEY'];
  }

  Map<String, String> get headers {
    final Map<String, String> h = {
      'Content-Type': 'application/json',
      'x-api-key': apiKey ?? '',
    };
    
    final token = SessionService.instance.current?.token;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    
    return h;
  }

  bool get hasToken {
    final token = SessionService.instance.current?.token;
    return token != null && token.isNotEmpty;
  }

  Future<bool> _attemptReauth() async {
    final session = SessionService.instance.current;
    if (session != null && session.username != null && session.password != null) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json', 'x-api-key': apiKey ?? ''},
          body: jsonEncode({
            'username': session.username,
            'password': session.password,
          }),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final token = data['token'];
          final updated = session.copyWith(token: token, isOfflineSession: false);
          await SessionService.instance.save(updated);
          await SessionService.instance.loadAndCache();
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<http.Response> get(String endpoint) async {
    var response = await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
      }
    }
    return response;
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    var response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await http.post(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(body),
        );
      }
    }
    return response;
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    var response = await http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await http.put(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(body),
        );
      }
    }
    return response;
  }

  Future<http.Response> delete(String endpoint) async {
    var response = await http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers);
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers);
      }
    }
    return response;
  }

  dynamic handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'An error occurred';
      try {
        final body = jsonDecode(response.body);
        message = body['message'] ?? message;
      } catch (_) {}
      
      if (response.statusCode == 401) {
        final session = SessionService.instance.current;
        final isBusiness = session?.role == 'business';
        final isOfflineSession = session?.isOfflineSession ?? false;

        if (isBusiness || isOfflineSession) {
          debugPrint('⚠️ Unauthorized (401) but business/offline session active. Skipping session clear.');
        } else {
          debugPrint('⚠️ Unauthorized (401): $message. Clearing session.');
          SessionService.instance.clear();
        }
      }
      
      throw ApiException(message, response.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}