// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:app/core/services/connectivity_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../shared/layouts/admin_layout.dart';
import '../../../api/admin_dashboard_api.dart';
import '../../../api/base_api.dart';

// ─── Admin Dashboard Page ─────────────────────────────────────────────────────

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _api = AdminDashboardApi();

  // ── Filter state ─────────────────────────────────────────────────────────────
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int _trendYear1 = DateTime.now().year - 1;
  int _trendYear2 = DateTime.now().year;

  // ── Data state ────────────────────────────────────────────────────────────────
  AdminDashboardData? _dashData;
  Map<int, List<MonthlyCount>> _trendData = {};
  bool _loadingDash = true;
  bool _loadingTrend = true;
  bool _exporting = false;
  String? _dashError;
  int? _errorCode;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadTrend();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loadingDash = true;
      _dashError = null;
      _errorCode = null;
    });
    try {
      final data = await _api.fetchDashboardData(
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (mounted) setState(() => _dashData = data);
    } on ApiException catch (e) {
      if (mounted)
        setState(() {
          _dashError = e.message;
          _errorCode = e.statusCode;
        });
    } catch (e) {
      final code = await classifyError(e);
      if (mounted)
        setState(() {
          _dashError = e.toString();
          _errorCode = code;
        });
    } finally {
      if (mounted) setState(() => _loadingDash = false);
    }
  }

  Future<void> _loadTrend() async {
    setState(() => _loadingTrend = true);
    try {
      final data = await _api.fetchYearlyComparison(
        years: [_trendYear1, _trendYear2],
      );
      if (mounted) setState(() => _trendData = data);
    } catch (_) {
      // trend is non-critical; silently fail
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Exports ───────────────────────────────────────────────────────────────────

  Future<Directory> _exportDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getTemporaryDirectory();
  }

  String _exportLabel() {
    return _selectedMonth == 0
        ? '$_selectedYear'
        : '${_monthShort(_selectedMonth)}_$_selectedYear';
  }

  String _csvCell(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Replaces Unicode punctuation Helvetica can't render with plain ASCII.
  String _pdfSafe(String s) => s
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-');

  // ── CSV Export ────────────────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final d = _dashData;
      if (d == null) return;

      final periodLabel = _selectedMonth == 0
          ? 'Full Year $_selectedYear'
          : '${_monthName(_selectedMonth)} $_selectedYear';

      final buf = StringBuffer();

      // ── Header info ────────────────────────────────────────────────────────
      buf.writeln('City,San Pablo City');
      buf.writeln('Period,${_csvCell(periodLabel)}');
      buf.writeln();

      // ── Summary ────────────────────────────────────────────────────────────
      buf.writeln('SUMMARY');
      buf.writeln('Metric,Value');
      buf.writeln('Active Accommodations,${d.stats.activeAccommodations}');
      buf.writeln('Tourists This Period,${d.stats.touristsThisPeriod}');
      buf.writeln('Pending Registrations,${d.stats.pendingRegistrations}');
      buf.writeln('Total Tourists This Year,${d.stats.touristsThisYear}');
      buf.writeln();

      // ── Gender Distribution ────────────────────────────────────────────────
      buf.writeln('GENDER DISTRIBUTION');
      buf.writeln('Gender,Count,Percentage');
      buf.writeln(
        'Male,${d.genderDistribution.male},'
        '${(d.genderDistribution.maleRatio * 100).toStringAsFixed(1)}%',
      );
      buf.writeln(
        'Female,${d.genderDistribution.female},'
        '${(d.genderDistribution.femaleRatio * 100).toStringAsFixed(1)}%',
      );
      buf.writeln();

      // ── Age Group Distribution ─────────────────────────────────────────────
      buf.writeln('AGE GROUP DISTRIBUTION');
      buf.writeln('Age Group,Count,Percentage');
      final totalAge = d.ageGroups.fold<int>(0, (s, a) => s + a.count);
      for (final a in d.ageGroups) {
        final pct = totalAge == 0 ? 0.0 : (a.count / totalAge * 100);
        buf.writeln(
          '${_csvCell(a.ageGroup)},${a.count},${pct.toStringAsFixed(1)}%',
        );
      }
      buf.writeln();

      // ── Top Nationalities ──────────────────────────────────────────────────
      buf.writeln('TOP 5 COUNTRIES/NATIONALITIES');
      buf.writeln('Nationality,Tourists');
      for (final n in d.topNationalities) {
        buf.writeln('${_csvCell(n.nationality)},${n.count}');
      }
      buf.writeln();

      // ── Top Local Regions ──────────────────────────────────────────────────
      buf.writeln('TOP LOCAL REGIONS (Philippine Visitors)');
      buf.writeln('Region,Tourists');
      for (final r in d.topRegions) {
        buf.writeln('${_csvCell(r.region)},${r.count}');
      }
      buf.writeln();

      // ── Accommodation Types ────────────────────────────────────────────────
      buf.writeln('ACCOMMODATION TYPES');
      buf.writeln('Type,Tourists');
      for (final a in d.accommodationTypes) {
        buf.writeln('${_csvCell(a.type)},${a.count}');
      }
      buf.writeln();

      // ── Purpose of Visit ───────────────────────────────────────────────────
      buf.writeln('PURPOSE OF VISIT');
      buf.writeln('Purpose,Tourists');
      for (final pv in d.purposeOfVisit) {
        buf.writeln('${_csvCell(pv.purpose)},${pv.count}');
      }
      buf.writeln();

      // ── Tourist Trend ──────────────────────────────────────────────────────
      final y1Data =
          _trendData[_trendYear1] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));
      final y2Data =
          _trendData[_trendYear2] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));

      buf.writeln('TOURIST TREND - $_trendYear1 vs $_trendYear2');
      buf.writeln('Month,$_trendYear1 Tourists,$_trendYear2 Tourists');
      for (int i = 0; i < 12; i++) {
        final y1Count = i < y1Data.length ? y1Data[i].count : 0;
        final y2Count = i < y2Data.length ? y2Data[i].count : 0;
        buf.writeln('${_monthName(i + 1)},$y1Count,$y2Count');
      }

      final fileName = 'admin_dashboard_${_exportLabel()}.csv';
      final bytes = utf8.encode('\uFEFF${buf.toString()}');

      if (kIsWeb) {
        await saveFileToDownloads(fileName, bytes);
        if (!mounted) return;
        _showSnack('CSV downloaded: $fileName');
      } else {
        final dir = await _exportDirectory();
        final file = File(p.join(dir.path, fileName));
        await file.writeAsString('\uFEFF${buf.toString()}', flush: true);

        final result = await OpenFile.open(file.path);
        if (!mounted) return;
        if (result.type != ResultType.done) {
          _showSnack('CSV saved to ${file.path}. ${result.message}');
        } else {
          _showSnack('CSV exported to ${file.path}');
        }
      }
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── PDF Export ────────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final d = _dashData;
      if (d == null) return;

      final doc = pw.Document();
      final label = _selectedMonth == 0
          ? 'Full Year $_selectedYear'
          : '${_monthName(_selectedMonth)} $_selectedYear';

      final y1Data =
          _trendData[_trendYear1] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));
      final y2Data =
          _trendData[_trendYear2] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));

      final totalAge = d.ageGroups.fold<int>(0, (s, a) => s + a.count);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'San Pablo City Tourism',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _pdfSafe('Dashboard Report - $label'),
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Divider(),
            ],
          ),
          build: (_) => [
            // ── Summary ──────────────────────────────────────────────────────
            pw.Text(
              'Summary',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ['Active Accommodations', '${d.stats.activeAccommodations}'],
                ['Tourists This Period', '${d.stats.touristsThisPeriod}'],
                ['Pending Registrations', '${d.stats.pendingRegistrations}'],
                ['Total Tourists This Year', '${d.stats.touristsThisYear}'],
              ],
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Gender Distribution ───────────────────────────────────────────
            pw.Text(
              'Gender Distribution',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Gender', 'Count', 'Percentage'],
              data: [
                [
                  'Male',
                  '${d.genderDistribution.male}',
                  '${(d.genderDistribution.maleRatio * 100).toStringAsFixed(1)}%',
                ],
                [
                  'Female',
                  '${d.genderDistribution.female}',
                  '${(d.genderDistribution.femaleRatio * 100).toStringAsFixed(1)}%',
                ],
              ],
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Age Group Distribution ────────────────────────────────────────
            pw.Text(
              'Age Group Distribution',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Age Group', 'Count', 'Percentage'],
              data: d.ageGroups.map((a) {
                final pct = totalAge == 0 ? 0.0 : (a.count / totalAge * 100);
                return [a.ageGroup, '${a.count}', '${pct.toStringAsFixed(1)}%'];
              }).toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Top Nationalities ─────────────────────────────────────────────
            pw.Text(
              'Top 5 Countries/Nationalities',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Nationality', 'Tourists'],
              data: d.topNationalities
                  .map((n) => [n.nationality, '${n.count}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Top Local Regions ─────────────────────────────────────────────
            pw.Text(
              'Top Local Regions (Philippine Visitors)',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Region', 'Tourists'],
              data: d.topRegions.map((r) => [r.region, '${r.count}']).toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Accommodation Types ───────────────────────────────────────────
            pw.Text(
              'Accommodation Types',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Type', 'Tourists'],
              data: d.accommodationTypes
                  .map((a) => [a.type, '${a.count}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Purpose of Visit ──────────────────────────────────────────────
            pw.Text(
              'Purpose of Visit',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Purpose', 'Tourists'],
              data: d.purposeOfVisit
                  .map((pv) => [pv.purpose, '${pv.count}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Tourist Trend ─────────────────────────────────────────────────
            pw.Text(
              'Tourist Trend - $_trendYear1 vs $_trendYear2',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Monthly tourist arrivals - year-over-year comparison',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: [
                'Month',
                '$_trendYear1 Tourists',
                '$_trendYear2 Tourists',
              ],
              data: List.generate(12, (i) {
                final y1Count = i < y1Data.length ? y1Data[i].count : 0;
                final y2Count = i < y2Data.length ? y2Data[i].count : 0;
                return [_monthName(i + 1), '$y1Count', '$y2Count'];
              }),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );

      final fileName = 'admin_dashboard_${_exportLabel()}.pdf';
      final pdfBytes = await doc.save();

      if (kIsWeb) {
        await saveFileToDownloads(fileName, pdfBytes);
        if (!mounted) return;
        _showSnack('PDF downloaded: $fileName');
      } else {
        final dir = await _exportDirectory();
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(pdfBytes, flush: true);

        final result = await OpenFile.open(file.path);
        if (!mounted) return;
        if (result.type != ResultType.done) {
          _showSnack('PDF saved to ${file.path}. ${result.message}');
        } else {
          _showSnack('PDF exported to ${file.path}');
        }
      }
    } catch (e) {
      _showSnack('PDF export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Export Modal ──────────────────────────────────────────────────────────────

  void _showExportMenu() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon badge ────────────────────────────────────────────────
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.upload_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Title ─────────────────────────────────────────────────────
                const Text(
                  'Export Report',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _selectedMonth == 0
                      ? 'Full Year $_selectedYear'
                      : '${_monthName(_selectedMonth)} $_selectedYear',
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                // ── CSV option ────────────────────────────────────────────────
                _ExportDialogOption(
                  icon: Icons.table_chart_rounded,
                  color: AppColors.accentGreen,
                  title: 'Export as CSV',
                  subtitle: 'Summary, distribution & trend data',
                  onTap: () {
                    Navigator.pop(dialogCtx);
                    _exportCsv();
                  },
                ),
                const SizedBox(height: 10),

                // ── PDF option ────────────────────────────────────────────────
                _ExportDialogOption(
                  icon: Icons.picture_as_pdf_rounded,
                  color: AppColors.accentOrange,
                  title: 'Export as PDF',
                  subtitle: 'Formatted report document',
                  onTap: () {
                    Navigator.pop(dialogCtx);
                    _exportPdf();
                  },
                ),
                const SizedBox(height: 20),

                // ── Cancel ────────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.textGray,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.accentGreen),
    );
  }

  // ── Label helpers ─────────────────────────────────────────────────────────────

  static String _monthName(int m) => const [
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
  ][m];

  static String _monthShort(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m];

  // ── Build ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Dashboard',
      selectedIndex: 0,
      onNavSelected: (_) {},
      child: _dashError != null
          ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _loadDashboard)
          : Stack(
              children: [
                SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 600;
                      final isMedium = constraints.maxWidth < 900;
                      return Padding(
                        padding: EdgeInsets.all(isNarrow ? 16 : 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          if (isNarrow) ...[
                            _DashboardHeader(
                              selectedMonth: _selectedMonth,
                              selectedYear: _selectedYear,
                            ),
                            const SizedBox(height: 12),
                            _FilterRow(
                              selectedMonth: _selectedMonth,
                              selectedYear: _selectedYear,
                              onMonthChanged: (m) {
                                setState(() => _selectedMonth = m);
                                _loadDashboard();
                              },
                              onYearChanged: (y) {
                                setState(() => _selectedYear = y);
                                _loadDashboard();
                              },
                              onExport: _exporting ? null : _showExportMenu,
                              isExporting: _exporting,
                            ),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: _DashboardHeader(
                                    selectedMonth: _selectedMonth,
                                    selectedYear: _selectedYear,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _FilterRow(
                                  selectedMonth: _selectedMonth,
                                  selectedYear: _selectedYear,
                                  onMonthChanged: (m) {
                                    setState(() => _selectedMonth = m);
                                    _loadDashboard();
                                  },
                                  onYearChanged: (y) {
                                    setState(() => _selectedYear = y);
                                    _loadDashboard();
                                  },
                                  onExport: _exporting ? null : _showExportMenu,
                                  isExporting: _exporting,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (_loadingDash)
                            const _LoadingSection(height: 100)
                          else ...[
                            _StatCards(
                              stats: _dashData!.stats,
                              selectedMonth: _selectedMonth,
                              selectedYear: _selectedYear,
                            ),
                            const SizedBox(height: 20),
                            _DonutChartsRow(
                              genderDist: _dashData!.genderDistribution,
                              ageGroups: _dashData!.ageGroups,
                              topNationalities: _dashData!.topNationalities,
                              topRegions: _dashData!.topRegions,
                              accommodationTypes: _dashData!.accommodationTypes,
                              purposeOfVisit: _dashData!.purposeOfVisit,
                              isNarrow: isNarrow,
                              isMedium: isMedium,
                            ),
                            const SizedBox(height: 20),
                            _TrendCard(
                              trendData: _trendData,
                              year1: _trendYear1,
                              year2: _trendYear2,
                              isLoading: _loadingTrend,
                              onYear1Changed: (y) {
                                setState(() => _trendYear1 = y);
                                _loadTrend();
                              },
                              onYear2Changed: (y) {
                                setState(() => _trendYear2 = y);
                                _loadTrend();
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                    },
                  ),
                ),
                if (_exporting)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryCyan,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primaryCyan),
      ),
    );
  }
}

// ─── Export Dialog Option ─────────────────────────────────────────────────────

class _ExportDialogOption extends StatelessWidget {
  const _ExportDialogOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color.withOpacity(0.7),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dashboard Header ─────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.selectedMonth,
    required this.selectedYear,
  });

  final int selectedMonth;
  final int selectedYear;

  String get _periodLabel {
    if (selectedMonth == 0)
      return 'San Pablo City \u2014 Full Year $selectedYear';
    return 'San Pablo City \u2014 ${_monthName(selectedMonth)} $selectedYear';
  }

  static String _monthName(int m) => const [
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
  ][m];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tourism Overview',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _periodLabel,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Filter Row ───────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selectedMonth,
    required this.selectedYear,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onExport,
    required this.isExporting,
  });

  final int selectedMonth;
  final int selectedYear;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onYearChanged;
  final VoidCallback? onExport;
  final bool isExporting;

  static const _months = [
    (0, 'All Months'),
    (1, 'January'),
    (2, 'February'),
    (3, 'March'),
    (4, 'April'),
    (5, 'May'),
    (6, 'June'),
    (7, 'July'),
    (8, 'August'),
    (9, 'September'),
    (10, 'October'),
    (11, 'November'),
    (12, 'December'),
  ];

  List<int> get _years {
    final now = DateTime.now().year;
    return List.generate(5, (i) => now - i);
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Wrap(
      spacing: isNarrow ? 6 : 10,
      runSpacing: isNarrow ? 6 : 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: isNarrow ? 140 : 170,
          child: _FilterDropdown<int>(
            value: selectedMonth,
            items: _months.map((m) => (m.$1, m.$2)).toList(),
            onChanged: onMonthChanged,
            icon: Icons.calendar_month_rounded,
          ),
        ),
        SizedBox(
          width: isNarrow ? 90 : 110,
          child: _FilterDropdown<int>(
            value: selectedYear,
            items: _years.map((y) => (y, '$y')).toList(),
            onChanged: onYearChanged,
            icon: Icons.event_rounded,
          ),
        ),
        _ExportButton(onTap: onExport, isLoading: isExporting),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.primaryCyan),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: AppColors.cardBackground,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textGray,
                  size: 18,
                ),
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 12,
                ),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                items: items
                    .map(
                      (item) => DropdownMenuItem<T>(
                        value: item.$1,
                        child: Text(item.$2, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onTap, required this.isLoading});

  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.upload_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            const Text(
              'Export',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Cards ───────────────────────────────────────────────────────────────

class _StatCards extends StatelessWidget {
  const _StatCards({
    required this.stats,
    required this.selectedMonth,
    required this.selectedYear,
  });

  final AdminDashboardStats stats;
  final int selectedMonth;
  final int selectedYear;

  String get _periodLabel => selectedMonth == 0 ? 'This Year' : 'This Month';

  String get _yearSubLabel {
    final currentYear = DateTime.now().year;
    if (selectedYear < currentYear) return 'Full Year $selectedYear';
    final months = const [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Jan \u2013 ${months[DateTime.now().month]} $selectedYear';
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.assignment_rounded,
        iconColor: AppColors.primaryCyan,
        value: '${stats.activeAccommodations}',
        label: 'Active Accommodations',
        sub: stats.pendingRegistrations > 0
            ? '${stats.pendingRegistrations} pending'
            : null,
      ),
      _StatCard(
        icon: Icons.people_alt_rounded,
        iconColor: AppColors.primaryBlue,
        value: '${stats.touristsThisPeriod}',
        label: 'Tourists $_periodLabel',
      ),
      _StatCard(
        icon: Icons.calendar_today_rounded,
        iconColor: AppColors.accentOrange,
        value: '${stats.pendingRegistrations}',
        label: 'Pending Registrations',
      ),
      _StatCard(
        icon: Icons.groups_rounded,
        iconColor: AppColors.accentGreen,
        value: '${stats.touristsThisYear}',
        label: 'Total Tourists This Year',
        infoTooltip: _yearSubLabel,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cards
              .expand(
                (c) => [
                  Expanded(child: c),
                  if (c != cards.last) const SizedBox(width: 14),
                ],
              )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.sub,
    this.infoTooltip,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? sub;
  final String? infoTooltip;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    return _DashCard(
      child: SizedBox(
        width: double.infinity,
        child: isDesktop
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(icon, color: iconColor, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        value,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: const TextStyle(color: AppColors.textGray, fontSize: 12),
                        ),
                      ),
                      if (infoTooltip != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: infoTooltip!,
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: const TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 18),
                  const SizedBox(height: 10),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: const TextStyle(color: AppColors.textGray, fontSize: 12),
                        ),
                      ),
                      if (infoTooltip != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: infoTooltip!,
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: const TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 11,
                      ),
                    ),
                  ] else
                    const SizedBox(height: 13),
                ],
              ),
      ),
    );
  }
}

// ─── Donut Charts Row ─────────────────────────────────────────────────────────

class _DonutChartsRow extends StatelessWidget {
  const _DonutChartsRow({
    required this.genderDist,
    required this.ageGroups,
    required this.topNationalities,
    required this.topRegions,
    required this.accommodationTypes,
    required this.purposeOfVisit,
    required this.isNarrow,
    required this.isMedium,
  });

  final GenderDistribution genderDist;
  final List<AgeGroupCount> ageGroups;
  final List<NationalityCount> topNationalities;
  final List<RegionCount> topRegions;
  final List<AccommodationTypeCount> accommodationTypes;
  final List<PurposeCount> purposeOfVisit;
  final bool isNarrow;
  final bool isMedium;

  @override
  Widget build(BuildContext context) {
    final genderAgeCard = _GenderAgeCard(
      genderDist: genderDist,
      ageGroups: ageGroups,
    );
    final countriesRegionsCard = _CountriesRegionsCard(
      topNationalities: topNationalities,
      topRegions: topRegions,
    );
    final accommodationPurposeCard = _AccommodationPurposeCard(
      accommodationTypes: accommodationTypes,
      purposeOfVisit: purposeOfVisit,
    );

    if (isNarrow) {
      return Column(
        children: [
          genderAgeCard,
          const SizedBox(height: 14),
          countriesRegionsCard,
          const SizedBox(height: 14),
          accommodationPurposeCard,
        ],
      );
    }

    if (isMedium) {
      return Column(
        children: [
          genderAgeCard,
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: countriesRegionsCard),
              const SizedBox(width: 14),
              Expanded(child: accommodationPurposeCard),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: genderAgeCard),
        const SizedBox(width: 14),
        Expanded(child: countriesRegionsCard),
        const SizedBox(width: 14),
        Expanded(child: accommodationPurposeCard),
      ],
    );
  }
}

// ─── Toggle Card Title ────────────────────────────────────────────────────────

/// Renders two (or more) tab labels as the card title. The active label is
/// white + bold with a 1.5 px cyan underline; inactive labels are gray.
/// A "/" separator sits between each pair.
class _ToggleCardTitle extends StatelessWidget {
  const _ToggleCardTitle({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < options.length; i++) {
      if (i > 0) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '/',
              style: TextStyle(
                color: AppColors.textSubtle,
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        );
      }
      final isSelected = i == selectedIndex;
      widgets.add(
        GestureDetector(
          onTap: () => onChanged(i),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected
                      ? AppColors.primaryCyan
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
            child: Text(
              options[i],
              style: TextStyle(
                color: isSelected ? AppColors.textWhite : AppColors.textGray,
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }
}

// ─── Gender / Age Group Card ──────────────────────────────────────────────────

class _GenderAgeCard extends StatefulWidget {
  const _GenderAgeCard({required this.genderDist, required this.ageGroups});

  final GenderDistribution genderDist;
  final List<AgeGroupCount> ageGroups;

  @override
  State<_GenderAgeCard> createState() => _GenderAgeCardState();
}

class _GenderAgeCardState extends State<_GenderAgeCard> {
  int _tab = 0; // 0 = Gender, 1 = Age Group

  static const _ageColors = [
    AppColors.chartBlue,
    AppColors.chartGreen,
    AppColors.chartOrange,
    AppColors.chartPurple,
    AppColors.chartCyan,
    AppColors.chartGray,
  ];

  List<_Segment> get _segments {
    if (_tab == 0) {
      final d = widget.genderDist;
      final isEmpty = d.total == 0;
      return [
        _Segment(
          value: isEmpty ? 0.5 : d.maleRatio,
          color: AppColors.chartCyan,
          label: 'Male',
          percentage: '${d.male} tourists',
          isEmpty: isEmpty,
        ),
        _Segment(
          value: isEmpty ? 0.5 : d.femaleRatio,
          color: AppColors.chartPurple,
          label: 'Female',
          percentage: '${d.female} tourists',
          isEmpty: isEmpty,
        ),
      ];
    } else {
      if (widget.ageGroups.isEmpty) {
        return List.generate(
          5,
          (i) => _Segment(
            value: 0.2,
            color: _ageColors[i % _ageColors.length],
            isEmpty: true,
          ),
        );
      }
      final total = widget.ageGroups.fold<int>(0, (s, a) => s + a.count);
      return widget.ageGroups.asMap().entries.map((e) {
        final ratio = total == 0
            ? 1 / widget.ageGroups.length
            : e.value.count / total;
        return _Segment(
          value: ratio,
          color: _ageColors[e.key % _ageColors.length],
          label: e.value.ageGroup,
          percentage: '${e.value.count} tourists',
        );
      }).toList();
    }
  }

  List<_LegendItem> get _legend {
    if (_tab == 0) {
      return const [
        _LegendItem(label: 'Male', color: AppColors.chartCyan),
        _LegendItem(label: 'Female', color: AppColors.chartPurple),
      ];
    }
    return widget.ageGroups
        .asMap()
        .entries
        .map(
          (e) => _LegendItem(
            label: e.value.ageGroup,
            color: _ageColors[e.key % _ageColors.length],
          ),
        )
        .toList();
  }

  String? get _emptyHint {
    if (_tab == 0 && widget.genderDist.total == 0)
      return 'No data for this period';
    if (_tab == 1 && widget.ageGroups.isEmpty) return 'No data for this period';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToggleCardTitle(
            options: const ['Gender', 'Age Group'],
            selectedIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_emptyHint != null) ...[
            const SizedBox(height: 6),
            Text(
              _emptyHint!,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _DonutContent(
              key: ValueKey(_tab),
              segments: _segments,
              legend: _legend,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Countries / Local Regions Card ──────────────────────────────────────────

class _CountriesRegionsCard extends StatefulWidget {
  const _CountriesRegionsCard({
    required this.topNationalities,
    required this.topRegions,
  });

  final List<NationalityCount> topNationalities;
  final List<RegionCount> topRegions;

  @override
  State<_CountriesRegionsCard> createState() => _CountriesRegionsCardState();
}

class _CountriesRegionsCardState extends State<_CountriesRegionsCard> {
  int _tab = 0; // 0 = Countries, 1 = Local Regions

  static const _countryColors = [
    AppColors.chartGreen,
    AppColors.chartBlue,
    AppColors.chartOrange,
    AppColors.chartPurple,
    AppColors.chartGray,
  ];

  static const _regionColors = [
    AppColors.chartCyan,
    AppColors.chartGreen,
    AppColors.chartOrange,
    AppColors.chartPurple,
    AppColors.chartGray,
  ];

  List<_Segment> get _segments {
    if (_tab == 0) {
      final list = widget.topNationalities;
      if (list.isEmpty) {
        return List.generate(
          5,
          (i) => _Segment(
            value: 0.2,
            color: _countryColors[i % _countryColors.length],
            isEmpty: true,
          ),
        );
      }
      final total = list.fold<int>(0, (s, n) => s + n.count);
      return list.asMap().entries.map((e) {
        final ratio = total == 0 ? 1 / list.length : e.value.count / total;
        return _Segment(
          value: ratio,
          color: _countryColors[e.key % _countryColors.length],
          label: e.value.nationality,
          percentage: '${e.value.count} tourists',
        );
      }).toList();
    } else {
      final list = widget.topRegions;
      if (list.isEmpty) {
        return List.generate(
          5,
          (i) => _Segment(
            value: 0.2,
            color: _regionColors[i % _regionColors.length],
            isEmpty: true,
          ),
        );
      }
      final total = list.fold<int>(0, (s, r) => s + r.count);
      return list.asMap().entries.map((e) {
        final ratio = total == 0 ? 1 / list.length : e.value.count / total;
        return _Segment(
          value: ratio,
          color: _regionColors[e.key % _regionColors.length],
          label: e.value.region,
          percentage: '${e.value.count} tourists',
        );
      }).toList();
    }
  }

  List<_LegendItem> get _legend {
    if (_tab == 0) {
      return widget.topNationalities
          .asMap()
          .entries
          .map(
            (e) => _LegendItem(
              label: e.value.nationality,
              color: _countryColors[e.key % _countryColors.length],
            ),
          )
          .toList();
    }
    return widget.topRegions
        .asMap()
        .entries
        .map(
          (e) => _LegendItem(
            label: e.value.region,
            color: _regionColors[e.key % _regionColors.length],
          ),
        )
        .toList();
  }

  String? get _emptyHint {
    if (_tab == 0 && widget.topNationalities.isEmpty)
      return 'No data for this period';
    if (_tab == 1 && widget.topRegions.isEmpty)
      return 'No Philippine visitors for this period';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Top 5',
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              _ToggleCardTitle(
                options: const ['Countries', 'Local Regions'],
                selectedIndex: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ],
          ),
          if (_emptyHint != null) ...[
            const SizedBox(height: 6),
            Text(
              _emptyHint!,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _DonutContent(
              key: ValueKey(_tab),
              segments: _segments,
              legend: _legend,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Accommodation / Purpose of Visit Card ────────────────────────────────────

class _AccommodationPurposeCard extends StatefulWidget {
  const _AccommodationPurposeCard({
    required this.accommodationTypes,
    required this.purposeOfVisit,
  });

  final List<AccommodationTypeCount> accommodationTypes;
  final List<PurposeCount> purposeOfVisit;

  @override
  State<_AccommodationPurposeCard> createState() =>
      _AccommodationPurposeCardState();
}

class _AccommodationPurposeCardState extends State<_AccommodationPurposeCard> {
  int _tab = 0; // 0 = Accommodation, 1 = Purpose of Visit

  static const _accommodationColors = [
    AppColors.chartOrange,
    AppColors.chartBlue,
    AppColors.chartGreen,
    AppColors.chartPurple,
    AppColors.chartCyan,
    AppColors.chartGray,
  ];

  static const _purposeColors = [
    AppColors.chartPurple,
    AppColors.chartOrange,
    AppColors.chartBlue,
    AppColors.chartGreen,
    AppColors.chartCyan,
    AppColors.chartGray,
  ];

  List<_Segment> get _segments {
    if (_tab == 0) {
      final list = widget.accommodationTypes;
      if (list.isEmpty) {
        return List.generate(
          5,
          (i) => _Segment(
            value: 0.2,
            color: _accommodationColors[i % _accommodationColors.length],
            isEmpty: true,
          ),
        );
      }
      final total = list.fold<int>(0, (s, a) => s + a.count);
      return list.asMap().entries.map((e) {
        final ratio = total == 0 ? 1 / list.length : e.value.count / total;
        return _Segment(
          value: ratio,
          color: _accommodationColors[e.key % _accommodationColors.length],
          label: e.value.type,
          percentage: '${e.value.count} tourists',
        );
      }).toList();
    } else {
      final list = widget.purposeOfVisit;
      if (list.isEmpty) {
        return List.generate(
          5,
          (i) => _Segment(
            value: 0.2,
            color: _purposeColors[i % _purposeColors.length],
            isEmpty: true,
          ),
        );
      }
      final total = list.fold<int>(0, (s, p) => s + p.count);
      return list.asMap().entries.map((e) {
        final ratio = total == 0 ? 1 / list.length : e.value.count / total;
        return _Segment(
          value: ratio,
          color: _purposeColors[e.key % _purposeColors.length],
          label: e.value.purpose,
          percentage: '${e.value.count} tourists',
        );
      }).toList();
    }
  }

  List<_LegendItem> get _legend {
    if (_tab == 0) {
      return widget.accommodationTypes
          .asMap()
          .entries
          .map(
            (e) => _LegendItem(
              label: e.value.type,
              color: _accommodationColors[e.key % _accommodationColors.length],
            ),
          )
          .toList();
    }
    return widget.purposeOfVisit
        .asMap()
        .entries
        .map(
          (e) => _LegendItem(
            label: e.value.purpose,
            color: _purposeColors[e.key % _purposeColors.length],
          ),
        )
        .toList();
  }

  String? get _emptyHint {
    if (_tab == 0 && widget.accommodationTypes.isEmpty)
      return 'No accommodation data';
    if (_tab == 1 && widget.purposeOfVisit.isEmpty)
      return 'No data for this period';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToggleCardTitle(
            options: const ['Accommodation', 'Purpose of Visit'],
            selectedIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_emptyHint != null) ...[
            const SizedBox(height: 6),
            Text(
              _emptyHint!,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _DonutContent(
              key: ValueKey(_tab),
              segments: _segments,
              legend: _legend,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Donut Content (chart + legend, no title) ─────────────────────────────────

/// Shared content body used by all three toggleable donut cards.
class _DonutContent extends StatelessWidget {
  const _DonutContent({
    super.key,
    required this.segments,
    required this.legend,
  });

  final List<_Segment> segments;
  final List<_LegendItem> legend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(child: _DonutChart(segments: segments, size: 130)),
        if (legend.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Legend(items: legend),
        ],
      ],
    );
  }
}

// ─── Tourist Trend Card ───────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.trendData,
    required this.year1,
    required this.year2,
    required this.isLoading,
    required this.onYear1Changed,
    required this.onYear2Changed,
  });

  final Map<int, List<MonthlyCount>> trendData;
  final int year1;
  final int year2;
  final bool isLoading;
  final ValueChanged<int> onYear1Changed;
  final ValueChanged<int> onYear2Changed;

  List<int> get _availableYears {
    final now = DateTime.now().year;
    return List.generate(8, (i) => now - i);
  }

  @override
  Widget build(BuildContext context) {
    final chartHeight = MediaQuery.of(context).size.width < 500 ? 180.0 : 220.0;
    final y1Data =
        trendData[year1] ??
        List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));
    final y2Data =
        trendData[year2] ??
        List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _CardTitle(title: 'Tourist Trend')),
              _YearPill(
                year: year1,
                color: AppColors.chartBlue,
                years: _availableYears,
                onChanged: onYear1Changed,
              ),
              const SizedBox(width: 8),
              _YearPill(
                year: year2,
                color: AppColors.chartCyan,
                years: _availableYears,
                onChanged: onYear2Changed,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Monthly tourist arrivals \u2014 year-over-year comparison',
            style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            SizedBox(
              height: chartHeight,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryCyan),
              ),
            )
          else
            SizedBox(
              height: chartHeight,
              child: _ComparisonBarChart(
                year1: year1,
                year2: year2,
                year1Data: y1Data,
                year2Data: y2Data,
              ),
            ),
        ],
      ),
    );
  }
}

class _YearPill extends StatelessWidget {
  const _YearPill({
    required this.year,
    required this.color,
    required this.years,
    required this.onChanged,
  });

  final int year;
  final Color color;
  final List<int> years;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: year,
          dropdownColor: AppColors.cardBackground,
          icon: Icon(Icons.arrow_drop_down_rounded, color: color, size: 18),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: years
              .map((y) => DropdownMenuItem<int>(value: y, child: Text('$y')))
              .toList(),
        ),
      ),
    );
  }
}

// ─── Comparison Bar Chart ─────────────────────────────────────────────────────

class _ComparisonBarChart extends StatefulWidget {
  const _ComparisonBarChart({
    required this.year1,
    required this.year2,
    required this.year1Data,
    required this.year2Data,
  });

  final int year1;
  final int year2;
  final List<MonthlyCount> year1Data;
  final List<MonthlyCount> year2Data;

  @override
  State<_ComparisonBarChart> createState() => _ComparisonBarChartState();
}

class _ComparisonBarChartState extends State<_ComparisonBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _hoveredIsYear2 = false;
  int _hoveredMonth = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _ComparisonBarChart old) {
    super.didUpdateWidget(old);
    if (old.year1 != widget.year1 || old.year2 != widget.year2) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              _detectHover(
                box.globalToLocal(event.position),
                constraints.biggest,
              );
            }
          },
          onExit: (_) => setState(() => _hoveredMonth = -1),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _ComparisonBarPainter(
                year1: widget.year1,
                year2: widget.year2,
                year1Data: widget.year1Data,
                year2Data: widget.year2Data,
                animValue: _ctrl.value,
                hoveredMonth: _hoveredMonth,
                hoveredIsYear2: _hoveredIsYear2,
              ),
              size: constraints.biggest,
            ),
          ),
        );
      },
    );
  }

  void _detectHover(Offset pos, Size size) {
    const leftPad = 42.0;
    const bottomPad = 36.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad;

    if (pos.dy < 0 || pos.dy > chartH) {
      if (_hoveredMonth != -1) setState(() => _hoveredMonth = -1);
      return;
    }

    final groupW = chartW / 12;
    final barW = groupW * 0.30;
    const gap = 2.0;

    final allVals = [
      ...widget.year1Data.map((d) => d.count),
      ...widget.year2Data.map((d) => d.count),
    ];
    final maxVal = allVals.isEmpty ? 1 : allVals.reduce(math.max);
    final effectiveMax = (maxVal * 1.2).ceilToDouble();

    for (int i = 0; i < 12; i++) {
      final groupX = leftPad + i * groupW + groupW / 2 - barW - gap / 2;

      final x1 = groupX;
      final h1 =
          (widget.year1Data[i].count / effectiveMax) * chartH * _ctrl.value;
      if (pos.dx >= x1 && pos.dx <= x1 + barW && pos.dy >= chartH - h1) {
        if (_hoveredMonth != i || _hoveredIsYear2) {
          setState(() {
            _hoveredMonth = i;
            _hoveredIsYear2 = false;
          });
        }
        return;
      }

      final x2 = groupX + barW + gap;
      final h2 =
          (widget.year2Data[i].count / effectiveMax) * chartH * _ctrl.value;
      if (pos.dx >= x2 && pos.dx <= x2 + barW && pos.dy >= chartH - h2) {
        if (_hoveredMonth != i || !_hoveredIsYear2) {
          setState(() {
            _hoveredMonth = i;
            _hoveredIsYear2 = true;
          });
        }
        return;
      }
    }

    if (_hoveredMonth != -1) setState(() => _hoveredMonth = -1);
  }
}

class _ComparisonBarPainter extends CustomPainter {
  const _ComparisonBarPainter({
    required this.year1,
    required this.year2,
    required this.year1Data,
    required this.year2Data,
    required this.animValue,
    required this.hoveredMonth,
    required this.hoveredIsYear2,
  });

  final int year1;
  final int year2;
  final List<MonthlyCount> year1Data;
  final List<MonthlyCount> year2Data;
  final double animValue;
  final int hoveredMonth;
  final bool hoveredIsYear2;

  static const _color1 = AppColors.chartBlue;
  static const _color2 = AppColors.chartCyan;

  static const _monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 42.0;
    const bottomPad = 36.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad;

    final allVals = [
      ...year1Data.map((d) => d.count),
      ...year2Data.map((d) => d.count),
    ];
    final maxVal = allVals.isEmpty ? 0 : allVals.reduce(math.max);
    final effectiveMax = maxVal == 0 ? 10.0 : (maxVal * 1.25).ceilToDouble();

    final gridPaint = Paint()
      ..color = AppColors.cardBorder
      ..strokeWidth = 0.5;
    final labelStyle = TextStyle(
      color: AppColors.textSubtle,
      fontSize: size.width < 400 ? 8.5 : 10,
    );

    const ySteps = 5;
    for (int i = 0; i <= ySteps; i++) {
      final val = (effectiveMax * i / ySteps).round();
      final y = chartH - (val / effectiveMax) * chartH;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      _drawText(canvas, '$val', Offset(0, y - 6), labelStyle, leftPad - 4);
    }

    final groupW = chartW / 12;
    const gap = 2.0;
    final barW = groupW * 0.30;

    for (int i = 0; i < 12; i++) {
      final groupX = leftPad + i * groupW + groupW / 2 - barW - gap / 2;

      final v1 = year1Data[i].count;
      final h1 = (v1 / effectiveMax) * chartH * animValue;
      final isHov1 = hoveredMonth == i && !hoveredIsYear2;

      if (h1 > 0) {
        final rect1 = Rect.fromLTWH(groupX, chartH - h1, barW, h1);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect1,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                isHov1 ? _color1 : _color1.withOpacity(0.9),
                _color1.withOpacity(isHov1 ? 0.8 : 0.4),
              ],
            ).createShader(rect1),
        );
      }

      final v2 = year2Data[i].count;
      final h2 = (v2 / effectiveMax) * chartH * animValue;
      final isHov2 = hoveredMonth == i && hoveredIsYear2;
      final x2 = groupX + barW + gap;

      if (h2 > 0) {
        final rect2 = Rect.fromLTWH(x2, chartH - h2, barW, h2);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect2,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                isHov2 ? _color2 : _color2.withOpacity(0.9),
                _color2.withOpacity(isHov2 ? 0.8 : 0.4),
              ],
            ).createShader(rect2),
        );
      }

      if (hoveredMonth == i) {
        final isY2 = hoveredIsYear2;
        final hov = isY2 ? h2 : h1;
        final hovVal = isY2 ? v2 : v1;
        final hovYear = isY2 ? year2 : year1;
        final hovX = isY2 ? x2 : groupX;
        final hovColor = isY2 ? _color2 : _color1;
        _drawTooltip(
          canvas,
          '$hovYear: $hovVal tourists',
          hovColor,
          Offset(hovX + barW / 2, chartH - hov - 8),
          size.width,
        );
      }

      _drawText(
        canvas,
        _monthLabels[i],
        Offset(leftPad + i * groupW + groupW / 2 - 10, chartH + 8),
        labelStyle,
        groupW,
      );
    }

    _drawLegend(canvas, size, chartH + 22);
  }

  void _drawLegend(Canvas canvas, Size size, double y) {
    const dotR = 5.0;
    const spacing = 12.0;
    final style = TextStyle(
      color: AppColors.textGray,
      fontSize: size.width < 400 ? 9 : 11,
    );

    canvas.drawCircle(
      Offset(size.width / 2 - 60, y + dotR),
      dotR,
      Paint()..color = _color1,
    );
    _drawText(
      canvas,
      '$year1',
      Offset(size.width / 2 - 60 + dotR * 2 + 2, y),
      style,
      60,
    );

    canvas.drawCircle(
      Offset(size.width / 2 + spacing + 20, y + dotR),
      dotR,
      Paint()..color = _color2,
    );
    _drawText(
      canvas,
      '$year2',
      Offset(size.width / 2 + spacing + 20 + dotR * 2 + 2, y),
      style,
      60,
    );
  }

  void _drawTooltip(
    Canvas canvas,
    String text,
    Color color,
    Offset anchor,
    double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tw = tp.width + 14;
    final th = tp.height + 8;
    var tx = anchor.dx - tw / 2;
    final ty = anchor.dy - th - 4;
    tx = tx.clamp(0, maxWidth - tw);

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tx, ty, tw, th),
      const Radius.circular(5),
    );
    canvas.drawRRect(bgRect, Paint()..color = const Color(0xFF1E293B));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, Offset(tx + 7, ty + 4));
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
    double maxW,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ComparisonBarPainter old) =>
      old.animValue != animValue ||
      old.hoveredMonth != hoveredMonth ||
      old.hoveredIsYear2 != hoveredIsYear2 ||
      old.year1 != year1 ||
      old.year2 != year2;
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 500;
    return Container(
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textWhite,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LegendItem {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

// ─── Donut Chart ──────────────────────────────────────────────────────────────

class _Segment {
  const _Segment({
    required this.value,
    required this.color,
    this.label,
    this.percentage,
    this.isEmpty = false,
  });

  final double value;
  final Color color;
  final String? label;
  final String? percentage;
  final bool isEmpty;
}

class _DonutChart extends StatefulWidget {
  const _DonutChart({required this.segments, required this.size});

  final List<_Segment> segments;
  final double size;

  @override
  State<_DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<_DonutChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _hoveredIdx = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _DonutChart old) {
    super.didUpdateWidget(old);
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _checkHover(Offset pos, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final strokeW = size.width * 0.17;
    final inner = size.width / 2 - strokeW;
    final outer = size.width / 2;

    if (dist < inner || dist > outer) {
      if (_hoveredIdx != -1) setState(() => _hoveredIdx = -1);
      return;
    }

    double angle = math.atan2(dy, dx);
    angle = (angle + math.pi * 2) % (math.pi * 2);
    final startAngle = (angle + math.pi / 2) % (math.pi * 2);

    double acc = 0;
    for (int i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i].value * math.pi * 2;
      if (startAngle >= acc && startAngle <= acc + seg) {
        if (_hoveredIdx != i) setState(() => _hoveredIdx = i);
        return;
      }
      acc += seg;
    }

    if (_hoveredIdx != -1) setState(() => _hoveredIdx = -1);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          _checkHover(
            box.globalToLocal(e.position),
            Size(widget.size, widget.size),
          );
        }
      },
      onExit: (_) => setState(() => _hoveredIdx = -1),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _ctrl.value,
          child: Transform.scale(
            scale: 0.95 + _ctrl.value * 0.05,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    painter: _DonutPainter(
                      segments: widget.segments,
                      animValue: _ctrl.value,
                      hoveredIdx: _hoveredIdx,
                    ),
                    size: Size(widget.size, widget.size),
                  ),
                  if (_hoveredIdx != -1 &&
                      widget.segments[_hoveredIdx].label != null &&
                      !widget.segments[_hoveredIdx].isEmpty)
                    _DonutTooltip(segment: widget.segments[_hoveredIdx]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutTooltip extends StatelessWidget {
  const _DonutTooltip({required this.segment});

  final _Segment segment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            segment.label!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            segment.percentage!,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.segments,
    required this.animValue,
    required this.hoveredIdx,
  });

  final List<_Segment> segments;
  final double animValue;
  final int hoveredIdx;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeW = size.width * 0.17;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeW / 2);

    double startAngle = -math.pi / 2;
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final sweep = seg.value * 2 * math.pi * animValue;
      final isHov = hoveredIdx == i;
      final currentStroke = isHov ? strokeW + 5 : strokeW;
      final color = seg.isEmpty
          ? seg.color.withOpacity(0.15)
          : (isHov ? seg.color : seg.color.withOpacity(0.85));
      canvas.drawArc(
        rect,
        startAngle,
        sweep - 0.04,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = currentStroke
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.animValue != animValue || old.hoveredIdx != hoveredIdx;
}
