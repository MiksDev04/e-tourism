import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'session_service.dart';
import 'connectivity_service.dart';

class DocumentService {
  DocumentService._internal();
  static final DocumentService instance = DocumentService._internal();

  static const _maxCacheEntries = 20;
  final _cache = LinkedHashMap<String, Uint8List>();

  /// Resolves a relative or absolute URL to a full backend URL
  String _resolveUrl(String relativeOrAbsoluteUrl) {
    if (relativeOrAbsoluteUrl.isEmpty) return '';
    if (relativeOrAbsoluteUrl.startsWith('http://') || relativeOrAbsoluteUrl.startsWith('https://')) {
      return relativeOrAbsoluteUrl;
    }

    final String backendUrl;
    if (kIsWeb) {
      backendUrl = const String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: 'http://localhost:3000',
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      backendUrl = dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
    } else {
      backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    }

    final cleanBackend = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;
    final cleanRelative = relativeOrAbsoluteUrl.startsWith('/')
        ? relativeOrAbsoluteUrl
        : '/$relativeOrAbsoluteUrl';

    return '$cleanBackend$cleanRelative';
  }

  /// Fetches document bytes, using cache if available
  Future<Uint8List> fetchDocument(String url) async {
    if (url.isEmpty) throw Exception('Document URL is empty.');

    final resolved = _resolveUrl(url);

    // Check cache first
    final cached = _cache[resolved];
    if (cached != null) return cached;

    final token = SessionService.instance.current?.token;
    final apiKey = kIsWeb
        ? const String.fromEnvironment('API_KEY', defaultValue: '')
        : (dotenv.env['API_KEY'] ?? '');

    final headers = {
      'x-api-key': apiKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final response = await http.get(Uri.parse(resolved), headers: headers).timeout(const Duration(seconds: 30));
    
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      _cacheDoc(resolved, bytes);
      return bytes;
    } else {
      throw Exception('HTTP Error ${response.statusCode}');
    }
  }

  void _cacheDoc(String url, Uint8List bytes) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = bytes;
  }

  /// Pre-fetches a document to fill the cache
  Future<void> prefetch(String url) async {
    try {
      await fetchDocument(url);
    } catch (_) {
      // Silently fail prefetch
    }
  }

  /// Checks if a document is already cached
  bool isCached(String url) {
    if (url.isEmpty) return false;
    return _cache.containsKey(_resolveUrl(url));
  }
}
