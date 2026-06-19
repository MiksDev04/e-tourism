// ignore_for_file: deprecated_member_use

import 'dart:convert';
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
    businessName: row['business_name'] as String?,
    fileUrl: row['file_url'] as String?,
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
  /// Fetches all generated reports from the backend.
  Future<List<GeneratedReport>> fetchReports() async {
    final response = await get('/api/admin/reports');
    final List data = handleResponse(response);
    return data.map((r) => GeneratedReport.fromRow(r)).toList();
  }

  /// Downloads a report file from the backend.
  Future<Uint8List> downloadReportFile(String fileUrl) async {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to download report: ${response.statusCode}');
    }
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
