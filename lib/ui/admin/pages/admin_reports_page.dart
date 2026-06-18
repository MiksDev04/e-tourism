// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/ui/shared/layouts/admin_layout.dart';
import 'package:app/ui/shared/widgets/paginator.dart';
import 'package:app/api/admin_report_api.dart';
import 'package:app/ui/admin/widgets/report_view_modal.dart';


// ─── Admin Reports Page ───────────────────────────────────────────────────────

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final ReportService _reportService = ReportService();

  List<GeneratedReport> _reports = [];

  bool _loadingReports = false;
  int? _errorCode;
  String? _fetchError;
  bool _isGenerating = false;
  bool _showFilters = false;
  String _searchQuery = '';
  String _filterMonth = '';
  String _filterYear = '';
  int _currentPage = 0;
  int _pageSize = 10;

  final _searchCtrl = TextEditingController();

  static const List<int> _pageSizeOptions = [10, 20, 30];

  static const List<String> _months = [
    'All Months',
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

  static const List<String> _years = [
    'All Years',
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
  ];

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchReports() async {
    if (!mounted) return;
    setState(() {
      _loadingReports = true;
      _fetchError = null;
      _errorCode = null;
    });
    try {
      final reports = await _reportService.fetchReports();

      if (!mounted) return;
      setState(() {
        _reports = reports;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.message;
        _errorCode = e.statusCode;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _fetchError = 'no_internet';
        _errorCode = 503;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.toString();
        _errorCode = 500;
      });
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  Future<void> _onGenerateReport({
    required int month,
    required int year,
    required ReportSheetOptions sheetOptions,
  }) async {
    setState(() => _isGenerating = true);
    try {
      await _reportService.generateAndUpload(
        ReportParams(month: month, year: year, sheetOptions: sheetOptions),
      );
      await _fetchReports();
      if (!mounted) return;
      _showSuccess('Report generated successfully');
    } catch (e) {
      if (!mounted) return;
      _showError('Error generating report: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showGenerateDialog() {
    showDialog(
      context: context,
      builder: (_) => _GenerateReportDialog(
        months: _months.where((m) => m != 'All Months').toList(),
        years: _years.where((y) => y != 'All Years').toList(),
        onGenerate: ({
          required int month,
          required int year,
          required ReportSheetOptions sheetOptions,
        }) {
          Navigator.pop(context);
          _onGenerateReport(
            month: month,
            year: year,
            sheetOptions: sheetOptions,
          );
        },
      ),
    );
  }

  // ── View Report ───────────────────────────────────────────────────────────

  void _viewReport(GeneratedReport report) {
    if (!report.hasFile) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ReportViewerModal(
        report: report,
        onDownloadExcel: () => _downloadReport(report),
      ),
    );
  }

  // ── Download Excel ────────────────────────────────────────────────────────

  Future<void> _downloadReport(GeneratedReport report) async {
    if (!report.hasFile) return;
    try {
      _showSuccess('Downloading file...');
      final fileData = await _reportService.downloadReportFile(report.fileUrl!);

      final fileName =
          'Report_${report.shortId}_${report.periodLabel.replaceAll(' ', '_')}.xlsx';


      if (kIsWeb) {
        await saveFileToDownloads(fileName, fileData);
        if (!mounted) return;
        _showSuccess('File downloaded: $fileName');
        return;
      }

      final Directory? downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        if (mounted) _showError('Could not access the Downloads folder.');
        return;
      }

      final localFile = File('${downloadsDir.path}/$fileName');
      await localFile.writeAsBytes(fileData);
      if (!mounted) return;
      await _openFile(localFile);
      _showSuccess('File saved to Downloads: $fileName');
    } catch (e) {
      if (mounted) _showError('Error downloading file: $e');
    }
  }

  Future<void> _openFile(File file) async {
    try {
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) _showError('Could not open file.');
      }
    } catch (e) {
      if (mounted) _showError('Could not open file: $e');
    }
  }

  void _clearFilters() {
    setState(() {
      _filterMonth = '';
      _filterYear = '';
      _searchQuery = '';
      _searchCtrl.clear();
      _currentPage = 0;
    });
  }

  List<GeneratedReport> get _filteredReports {
    var list = _reports;
    final q = _searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) =>
        r.id.toLowerCase().contains(q) ||
        (r.businessName ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (_filterMonth.isNotEmpty && _filterMonth != 'All Months') {
      list = list.where((r) => r.periodLabel.contains(_filterMonth)).toList();
    }
    if (_filterYear.isNotEmpty && _filterYear != 'All Years') {
      final y = int.tryParse(_filterYear);
      if (y != null) list = list.where((r) => r.periodYear == y).toList();
    }
    return list;
  }

  int get _totalPages =>
      (_filteredReports.length / _pageSize).ceil().clamp(1, 999);

  int get _clampedPage => _currentPage.clamp(0, _totalPages - 1);

  List<GeneratedReport> get _pagedReports {
    final start = _clampedPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _filteredReports.length);
    return _filteredReports.sublist(start, end);
  }

  void _resetPage() => _currentPage = 0;

  void _showSuccess(
    String msg, {
    String? actionText,
    VoidCallback? onActionPressed,
    Duration? duration,
    SnackBarBehavior? behavior,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF00C48C),
        behavior: behavior ?? SnackBarBehavior.fixed,
        margin:
            (behavior ?? SnackBarBehavior.fixed) == SnackBarBehavior.floating
                ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
                : null,
        duration: duration ?? const Duration(seconds: 3),
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        action: (actionText != null && onActionPressed != null)
            ? SnackBarAction(
                label: actionText,
                onPressed: onActionPressed,
                textColor: Colors.white,
              )
            : null,
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFFF4D6A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Report',
      selectedIndex: 2,
      onNavSelected: (_) {},
      child: _fetchError != null
          ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _fetchReports)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                return RefreshIndicator(
                  onRefresh: _fetchReports,
                  color: AppColors.primaryCyan,
                  backgroundColor: AppColors.cardBackground,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(isNarrow ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PageHeader(
                          isNarrow: isNarrow,
                          showFilters: _showFilters,
                          isGenerating: _isGenerating,
                          onFilterTap: () =>
                              setState(() => _showFilters = !_showFilters),
                          onGenerateTap: _showGenerateDialog,
                        ),
                        const SizedBox(height: 16),
                        if (_showFilters) ...[
                          _FilterSection(
                            months: _months,
                            years: _years,
                            selectedMonth: _filterMonth,
                            selectedYear: _filterYear,
                            onMonthChanged: (v) => setState(() {
                              _filterMonth = v ?? '';
                              _resetPage();
                            }),
                            onYearChanged: (v) => setState(() {
                              _filterYear = v ?? '';
                              _resetPage();
                            }),
                            onClear: _clearFilters,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _SearchBar(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() {
                            _searchQuery = v;
                            _resetPage();
                          }),
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(
                          icon: Icons.folder_zip_rounded,
                          label: 'Generated Reports',
                          subtitle:
                              'One file per establishment',
                          trailing: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryCyan,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        if (_loadingReports)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: CircularProgressIndicator(
                                color: AppColors.primaryCyan,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        else
                          _GeneratedReportsTable(
                            rows: _pagedReports,
                            isLoading: false,
                            onView: _viewReport,
                          ),
                        if (!_loadingReports) ...[
                          const SizedBox(height: 12),
                          Paginator(
                            currentPage: _clampedPage,
                            totalPages: _totalPages,
                            totalItems: _filteredReports.length,
                            pageSize: _pageSize,
                            pageSizeOptions: _pageSizeOptions,
                            onPageSizeChanged: (size) => setState(() {
                              _pageSize = size;
                              _currentPage = 0;
                            }),
                            onPageChanged: (page) =>
                                setState(() => _currentPage = page),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primaryCyan, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style:
                    const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─── Generated Reports Table ──────────────────────────────────────────────────

class _GeneratedReportsTable extends StatelessWidget {
  const _GeneratedReportsTable({
    required this.rows,
    required this.isLoading,
    required this.onView,
  });

  final List<GeneratedReport> rows;
  final bool isLoading;
  final void Function(GeneratedReport) onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (_, constraints) =>
                _TableHeader(isNarrow: constraints.maxWidth < 700),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryCyan,
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                'No reports yet. Use "Generate Report" to create one.',
                style: TextStyle(color: AppColors.textGray, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.cardBorder, height: 1),
              itemBuilder: (_, i) => LayoutBuilder(
                builder: (_, constraints) => _TableRow(
                  report: rows[i],
                  isNarrow: constraints.maxWidth < 700,
                  onView: () => onView(rows[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.isNarrow});
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(flex: 3, child: _HeaderCell('Report ID')),
            Expanded(flex: 3, child: _HeaderCell('Business')),
            Expanded(flex: 2, child: _HeaderCell('Period')),
            SizedBox(width: 72),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Report ID')),
          Expanded(flex: 2, child: _HeaderCell('Business')),
          Expanded(flex: 1, child: _HeaderCell('Type')),
          Expanded(flex: 1, child: _HeaderCell('Period')),
          Expanded(flex: 1, child: _HeaderCell('Sheets')),
          Expanded(flex: 2, child: _HeaderCell('Generated At')),
          SizedBox(width: 88, child: _HeaderCell('Actions')),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.report,
    required this.isNarrow,
    required this.onView,
  });

  final GeneratedReport report;
  final bool isNarrow;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${report.generatedAt.year}-'
        '${report.generatedAt.month.toString().padLeft(2, '0')}-'
        '${report.generatedAt.day.toString().padLeft(2, '0')}';

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportIdBadge(shortId: report.shortId),
                  const SizedBox(height: 3),
                  Text(
                    report.businessName ?? '',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                report.periodLabel,
                style:
                    const TextStyle(color: AppColors.textGray, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 72,
              child: _ViewButton(hasFile: report.hasFile, onTap: onView),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Tooltip(
              message: report.id,
              child: _ReportIdBadge(shortId: report.shortId),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              report.businessName ?? '',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 1, child: _TypeBadge(label: report.reportType)),
          Expanded(
            flex: 1,
            child: Text(
              report.periodLabel,
              style:
                  const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(flex: 1, child: _SheetPills(options: report.sheetOptions)),
          Expanded(
            flex: 2,
            child: Text(
              dateStr,
              style:
                  const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 88,
            child: _ViewButton(hasFile: report.hasFile, onTap: onView),
          ),
        ],
      ),
    );
  }
}

// ─── View Button ──────────────────────────────────────────────────────────────

class _ViewButton extends StatelessWidget {
  const _ViewButton({required this.hasFile, required this.onTap});
  final bool hasFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!hasFile) {
      return const Tooltip(
        message: 'File unavailable',
        child: Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFFF4D6A),
          size: 18,
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primaryCyan.withOpacity(0.10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.primaryCyan.withOpacity(0.3)),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_full_rounded,
                color: AppColors.primaryCyan,
                size: 13,
              ),
              SizedBox(width: 5),
              Text(
                'View',
                style: TextStyle(
                  color: AppColors.primaryCyan,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small shared widgets ─────────────────────────────────────────────────────

class _ReportIdBadge extends StatelessWidget {
  const _ReportIdBadge({required this.shortId});
  final String shortId;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.tag_rounded, color: AppColors.textSubtle, size: 13),

        const SizedBox(width: 4),
        Text(
          shortId,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primaryCyan.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primaryCyan.withOpacity(0.25)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.primaryCyan,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SheetPills extends StatelessWidget {
  const _SheetPills({this.options});
  final ReportSheetOptions? options;

  @override
  Widget build(BuildContext context) {
    if (options == null) {
      return const Text(
        '—',
        style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (options!.includeDailySheet) const _Pill('S1'),
        if (options!.includeCountrySumSheet) const _Pill('S2'),
        if (options!.includeMonthlySummarySheet) const _Pill('S3'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryCyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.primaryCyan.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primaryCyan,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Generate Report Dialog ───────────────────────────────────────────────────

class _GenerateReportDialog extends StatefulWidget {
  const _GenerateReportDialog({
    required this.months,
    required this.years,
    required this.onGenerate,
  });

  final List<String> months;
  final List<String> years;
  final void Function({
    required int month,
    required int year,
    required ReportSheetOptions sheetOptions,
  }) onGenerate;

  @override
  State<_GenerateReportDialog> createState() => _GenerateReportDialogState();
}

class _GenerateReportDialogState extends State<_GenerateReportDialog> {
  String? _selectedMonth;
  String? _selectedYear;

  bool _sheet1 = true;
  bool _sheet2 = true;
  bool _sheet3 = true;

  bool get _canGenerate =>
      _selectedMonth != null &&
      _selectedYear != null &&
      (_sheet1 || _sheet2 || _sheet3);

  static int _monthIndex(String name) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names.indexOf(name) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: AppColors.primaryCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate DAE-1B Report',
                        style: TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'One file per establishment · export as .xlsx',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _DialogLabel('Month'),
              const SizedBox(height: 6),
              _DropdownField<String>(
                hint: 'Select month',
                value: _selectedMonth,
                items: widget.months,
                itemLabel: (m) => m,
                onChanged: (v) => setState(() => _selectedMonth = v),
              ),
              const SizedBox(height: 14),
              const _DialogLabel('Year'),
              const SizedBox(height: 6),
              _DropdownField<String>(
                hint: 'Select year',
                value: _selectedYear,
                items: widget.years,
                itemLabel: (y) => y,
                onChanged: (v) => setState(() => _selectedYear = v),
              ),
              const SizedBox(height: 18),
              const Text(
                'Include Sheets',
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    _SheetToggle(
                      label: 'Daily Breakdown',
                      subtitle:
                          'One tab per establishment for selected month',
                      value: _sheet1,
                      onChanged: (v) => setState(() => _sheet1 = v),
                      isFirst: true,
                    ),
                    const Divider(color: AppColors.cardBorder, height: 1),
                    _SheetToggle(
                      label: 'Country Summary',
                      subtitle:
                          'Per establishment — selected month',
                      value: _sheet2,
                      onChanged: (v) => setState(() => _sheet2 = v),
                    ),
                    const Divider(color: AppColors.cardBorder, height: 1),
                    _SheetToggle(
                      label: 'Monthly Summary',
                      subtitle:
                          'Per establishment — all 12 months',
                      value: _sheet3,
                      onChanged: (v) => setState(() => _sheet3 = v),
                      isLast: true,
                    ),
                  ],
                ),
              ),
              if (!_sheet1 && !_sheet2 && !_sheet3)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Select at least one sheet to generate.',
                    style:
                        TextStyle(color: Color(0xFFFF4D6A), fontSize: 11.5),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                          color: AppColors.textGray, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _canGenerate
                        ? () => widget.onGenerate(
                              month: _monthIndex(_selectedMonth!),
                              year: int.parse(_selectedYear!),
                              sheetOptions: ReportSheetOptions(
                                includeDailySheet: _sheet1,
                                includeCountrySumSheet: _sheet2,
                                includeMonthlySummarySheet: _sheet3,
                              ),
                            )
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: _canGenerate
                            ? AppColors.primaryCyan
                            : AppColors.primaryCyan.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 15,
                            color:
                                _canGenerate ? Colors.black : Colors.black45,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Generate & Save',
                            style: TextStyle(
                              color: _canGenerate
                                  ? Colors.black
                                  : Colors.black45,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetToggle extends StatelessWidget {
  const _SheetToggle({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(10) : Radius.zero,
        bottom: isLast ? const Radius.circular(10) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.primaryCyan,
                checkColor: Colors.black,
                side: const BorderSide(
                    color: AppColors.textGray, width: 1.2),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color:
                          value ? AppColors.textWhite : AppColors.textGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: value
                          ? AppColors.textGray
                          : AppColors.textSubtle,
                      fontSize: 11,
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

// ─── Shared small helpers ─────────────────────────────────────────────────────

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.hint,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String hint;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          hint: Text(
            hint,
            style: const TextStyle(
                color: AppColors.textSubtle, fontSize: 13),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGray,
            size: 20,
          ),
          style:
              const TextStyle(color: AppColors.textWhite, fontSize: 13),
          dropdownColor: AppColors.cardBackground,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemLabel(item),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textWhite, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Filter Section ───────────────────────────────────────────────────────────

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.months,
    required this.years,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onClear,
  });

  final List<String> months;
  final List<String> years;
  final String selectedMonth;
  final String selectedYear;
  final void Function(String?) onMonthChanged;
  final void Function(String?) onYearChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 600 ? 2 : 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filters',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                child: const Text(
                  'Clear All',
                  style: TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 58,
            children: [
              _FilterDropdown(
                label: 'Month',
                value: selectedMonth.isEmpty ? 'All Months' : selectedMonth,
                items: months,
                onChanged: onMonthChanged,
              ),
              _FilterDropdown(
                label: 'Year',
                value: selectedYear.isEmpty ? 'All Years' : selectedYear,
                items: years,
                onChanged: onYearChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textGray,
                size: 20,
              ),
              style: const TextStyle(
                  color: AppColors.textWhite, fontSize: 13),
              dropdownColor: AppColors.cardBackground,
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textWhite, fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Search Bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style:
            const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
        decoration: const InputDecoration(
          hintText: 'Search by report ID…',
          hintStyle:
              TextStyle(color: AppColors.textSubtle, fontSize: 13.5),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.textSubtle,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.isNarrow,
    required this.showFilters,
    required this.isGenerating,
    required this.onFilterTap,
    required this.onGenerateTap,
  });

  final bool isNarrow;
  final bool showFilters;
  final bool isGenerating;
  final VoidCallback onFilterTap;
  final VoidCallback onGenerateTap;

  @override
  Widget build(BuildContext context) {
    final filterBtn = _HeaderButton(
      icon: Icons.filter_list_rounded,
      label: isNarrow ? null : 'Filters',
      isActive: showFilters,
      onTap: onFilterTap,
    );

    final generateBtn = _HeaderButton(
      icon: Icons.description_rounded,
      label: isNarrow ? null : 'Generate Report',
      isPrimary: true,
      isLoading: isGenerating,
      onTap: onGenerateTap,
    );

    const titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reports',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Generate and download DAE-1B reports',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [filterBtn, generateBtn]),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        titleBlock,
        Row(children: [filterBtn, const SizedBox(width: 10), generateBtn]),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.isActive = false,
    this.isPrimary = false,
    this.isLoading = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isPrimary;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;

    if (isPrimary) {
      bg = AppColors.primaryCyan;
      border = AppColors.primaryCyan;
      fg = Colors.white;
    } else if (isActive) {
      bg = AppColors.primaryCyan.withOpacity(0.15);
      border = AppColors.primaryCyan;
      fg = AppColors.primaryCyan;
    } else {
      bg = AppColors.cardBackground;
      border = AppColors.cardBorder;
      fg = AppColors.textGray;
    }

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: isPrimary
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              )
            : BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryCyan,
                ),
              )
            else
              Icon(icon, color: fg, size: 16),
            if (label != null && !isLoading) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight:
                      isPrimary ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
