// ignore_for_file: deprecated_member_use

import 'dart:collection';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'base_api.dart';

export 'base_api.dart';

// ─── Generated Report Model ───────────────────────────────────────────────────

class GeneratedReport {
  const GeneratedReport({
    required this.id,
    required this.reportScope,
    required this.periodMonth,
    required this.periodYear,
    required this.generatedAt,
    this.batchId,
    this.businessId,
    this.businessName,
    this.fileUrl,
    this.pdfUrl,
    this.generatedBy,
  });

  final String id;
  final String reportScope;
  final int periodMonth;
  final int periodYear;
  final String? batchId;
  final String? businessId;
  final String? businessName;
  final String? fileUrl;
  final String? pdfUrl;
  final DateTime generatedAt;
  final String? generatedBy;

  bool get hasFile => fileUrl != null && fileUrl!.isNotEmpty;

  String get shortId => id.replaceAll('-', '').substring(0, 8).toUpperCase();

  String get periodLabel => reportScope == 'annual'
      ? '$periodYear'
      : '${_monthName(periodMonth)} $periodYear';

  static String _monthName(int m) {
    const n = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return (m >= 1 && m <= 12) ? n[m] : '—';
  }

  static GeneratedReport fromRow(Map<String, dynamic> row) => GeneratedReport(
    id: row['id'] as String,
    reportScope: row['report_scope'] as String? ?? 'monthly',
    periodMonth: row['period_month'] as int,
    periodYear: row['period_year'] as int,
    batchId: row['batch_id'] as String?,
    businessId: row['business_id'] as String?,
    businessName: row['report_type'] == 'total' ? 'Total' : (row['business_name'] as String?),
    fileUrl: row['file_url'] as String?,
    pdfUrl: row['pdf_url'] as String?,
    generatedAt: DateTime.parse(row['generated_at'] as String),
    generatedBy: row['generated_by_name'] as String?,
  );
}

class ReportParams {
  final int month;
  final int year;
  final String scope;
  const ReportParams({
    required this.month,
    required this.year,
    required this.scope,
  });
}

// ─── Report Service ───────────────────────────────────────────────────────────

class ReportService extends BaseApi {
  static const _maxCacheEntries = 20;
  static final _fileCache = LinkedHashMap<String, Uint8List>();

  /// Fetches paginated generated reports from the backend.
  Future<({List<GeneratedReport> data, int totalCount, int pageCount})> fetchReports({
    int page = 1,
    int pageSize = 10,
    String? month,
    String? year,
    String? filterBusinessName,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (month != null && month != 'All Months') queryParams['month'] = month;
    if (year != null && year != 'All Years') queryParams['year'] = year;
    if (filterBusinessName != null && filterBusinessName != 'All') queryParams['filterBusinessName'] = filterBusinessName;

    final uri = Uri.parse('/api/admin/reports').replace(queryParameters: queryParams);
    final response = await get(uri.toString());
    final body = handleResponse(response) as Map<String, dynamic>;
    final list = body['data'] as List;
    final totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
    final pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;
    final data = list.map((r) => GeneratedReport.fromRow(r)).toList();
    return (data: data, totalCount: totalCount, pageCount: pageCount);
  }

  /// Downloads a report file from the backend.
  Future<Uint8List> downloadReportFile(String fileUrl) async {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    final key = uri.toString();

    final cached = _fileCache[key];
    if (cached != null) return cached;

    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      _cacheFile(key, bytes);
      return bytes;
    } else {
      throw Exception('Failed to download report: ${response.statusCode}');
    }
  }

  static void _cacheFile(String key, Uint8List bytes) {
    if (_fileCache.length >= _maxCacheEntries) {
      _fileCache.remove(_fileCache.keys.first);
    }
    _fileCache[key] = bytes;
  }

  Uint8List? getCachedFile(String fileUrl) {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    return _fileCache[uri.toString()];
  }

  bool isCached(String fileUrl) {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    return _fileCache.containsKey(uri.toString());
  }

  /// Generates reports on the backend (one per establishment).
  Future<void> generateAndUpload(ReportParams params) async {
    final body = <String, dynamic>{
      'month': params.month,
      'year': params.year,
      'scope': params.scope,
    };
    await post('/api/admin/reports/generate', body);
  }
}
