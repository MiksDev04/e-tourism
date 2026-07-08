// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/ui/shared/layouts/admin_layout.dart';
import 'package:app/ui/shared/widgets/paginator.dart';
import 'package:app/ui/shared/widgets/report_loading_overlay.dart';
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
  bool _generationCancelled = false;
  String _filterMonth = '';
  String _filterYear = '';
  String _filterBusinessName = '';
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

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

  List<String> get _businessNameOptions {
    final names = _reports
        .map((r) => r.businessName)
        .whereType<String>()
        .where((n) => n.isNotEmpty && n != 'Total')
        .toSet()
        .toList();
    names.sort();
    return ['All', 'Total', ...names];
  }

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  @override
  void dispose() {
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
      final result = await _reportService.fetchReports(
        page: _currentPage + 1,
        pageSize: _pageSize,
        month: _filterMonth.isNotEmpty ? _filterMonth : null,
        year: _filterYear.isNotEmpty ? _filterYear : null,
        filterBusinessName: _filterBusinessName.isNotEmpty ? _filterBusinessName : null,
      );

      if (!mounted) return;
      setState(() {
        _reports = result.data;
        _totalPages = result.pageCount;
        _totalItems = result.totalCount;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.message;
        _errorCode = e.statusCode;
      });
    } catch (e) {
      final code = await classifyError(e);
      if (!mounted) return;
      setState(() {
        _fetchError = e.toString();
        _errorCode = code;
      });
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  Future<void> _onGenerateReport({
    required int month,
    required int year,
    required String scope,
  }) async {
    _generationCancelled = false;

    if (!mounted) return;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportLoadingOverlay(
        onInternetLost: () => _generationCancelled = true,
        onDismiss: () {
          Navigator.pop(context);
          _showError('Report generation failed due to network issues.');
        },
      ),
    ));

    try {
      await _reportService.generateAndUpload(
        ReportParams(month: month, year: year, scope: scope),
      );
      if (!mounted || _generationCancelled) return;
      if (mounted) Navigator.pop(context);
      await _fetchReports();
      if (!mounted) return;
      _showSuccess('Report generated successfully');
    } catch (e) {
      if (!mounted) return;
      if (_generationCancelled) return;
      if (mounted) Navigator.pop(context);
      _showError('Error generating report: $e');
    }
  }

  void _showGenerateDialog() {
    showDialog(
      context: context,
      builder: (_) => _GenerateReportDialog(
        months: _months.where((m) => m != 'All Months').toList(),
        years: _years.where((y) => y != 'All Years').toList(),
        onGenerate:
            ({required int month, required int year, required String scope}) {
              Navigator.pop(context);
              _onGenerateReport(month: month, year: year, scope: scope);
            },
      ),
    );
  }

  // ── View Report ───────────────────────────────────────────────────────────
  
  void _viewReport(GeneratedReport report) {
    if (!report.hasFile) return;
    
    final pdfUrl = report.pdfUrl ??
        report.fileUrl!.replaceAll('.xlsx', '.pdf');
    _reportService.downloadReportFile(pdfUrl);
    
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
      _filterBusinessName = '';
      _currentPage = 0;
    });
    _fetchReports();
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
                          onGenerateTap: _showGenerateDialog,
                        ),
                        const SizedBox(height: 16),
                        _FilterSection(
                          isNarrow: isNarrow,
                          months: _months,
                          years: _years,
                          businessNameOptions: _businessNameOptions,
                          selectedMonth: _filterMonth,
                          selectedYear: _filterYear,
                          selectedBusinessName: _filterBusinessName,
                          onMonthChanged: (v) {
                            setState(() {
                              _filterMonth = v ?? '';
                              _currentPage = 0;
                            });
                            _fetchReports();
                          },
                          onYearChanged: (v) {
                            setState(() {
                              _filterYear = v ?? '';
                              _currentPage = 0;
                            });
                            _fetchReports();
                          },
                          onBusinessNameChanged: (v) {
                            setState(() {
                              _filterBusinessName = v ?? '';
                              _currentPage = 0;
                            });
                            _fetchReports();
                          },
                          onClear: _clearFilters,
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(
                          icon: Icons.folder_zip_rounded,
                          label: 'Generated Reports',
                          subtitle: 'One file per establishment',
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
                            rows: _reports,
                            isLoading: false,
                            onView: _viewReport,
                          ),
                        if (!_loadingReports) ...[
                          const SizedBox(height: 12),
                          Paginator(
                            currentPage: _currentPage,
                            totalPages: _totalPages,
                            totalItems: _totalItems,
                            pageSize: _pageSize,
                            pageSizeOptions: _pageSizeOptions,
                            onPageSizeChanged: (size) {
                              setState(() {
                                _pageSize = size;
                                _currentPage = 0;
                              });
                              _fetchReports();
                            },
                            onPageChanged: (page) {
                              setState(() => _currentPage = page);
                              _fetchReports();
                            },
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
  });

  final IconData icon;
  final String label;
  final String subtitle;

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
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
            ],
          ),
        ),
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
          Expanded(flex: 2, child: _HeaderCell('Business')),
          Expanded(flex: 1, child: _HeaderCell('Period')),
          Expanded(flex: 1, child: _HeaderCell('Scope')),
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
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
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
            flex: 2,
            child: Text(
              report.businessName ?? '',
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              report.periodLabel,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(flex: 1, child: _ScopeBadge(scope: report.reportScope)),
          Expanded(
            flex: 2,
            child: Text(
              dateStr,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
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

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.scope});
  final String scope;

  @override
  Widget build(BuildContext context) {
    final label = scope == 'annual' ? 'Annual' : 'Monthly';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
    required String scope,
  })
  onGenerate;

  @override
  State<_GenerateReportDialog> createState() => _GenerateReportDialogState();
}

class _GenerateReportDialogState extends State<_GenerateReportDialog> {
  String _scope = 'monthly';
  String? _selectedMonth;
  String? _selectedYear;

  bool get _canGenerate =>
      _selectedYear != null && (_scope == 'annual' || _selectedMonth != null);

  static int _monthIndex(String name) {
    const names = [
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
    return names.indexOf(name) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Generate Report',
                          style: TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'One record per establishment · export as .xlsx and .pdf',
                          style: TextStyle(
                            color: AppColors.textGray,
                            fontSize: 11.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textGray,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _DialogLabel('Report Scope'),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    _ScopeOption(
                      label: 'Monthly Report',
                      subtitle:
                          'Daily breakdown + country summary for one month',
                      selected: _scope == 'monthly',
                      onTap: () => setState(() => _scope = 'monthly'),
                      isFirst: true,
                    ),
                    const Divider(color: AppColors.cardBorder, height: 1),
                    _ScopeOption(
                      label: 'Annual Summary',
                      subtitle: '12-month summary per establishment',
                      selected: _scope == 'annual',
                      onTap: () => setState(() => _scope = 'annual'),
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_scope == 'monthly') ...[
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
              ],
              const _DialogLabel('Year'),
              const SizedBox(height: 6),
              _DropdownField<String>(
                hint: 'Select year',
                value: _selectedYear,
                items: widget.years,
                itemLabel: (y) => y,
                onChanged: (v) => setState(() => _selectedYear = v),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textGray, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: _canGenerate
                        ? () => widget.onGenerate(
                            month: _scope == 'annual'
                                ? 12
                                : _monthIndex(_selectedMonth!),
                            year: int.parse(_selectedYear!),
                            scope: _scope,
                          )
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
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
                            color: _canGenerate ? Colors.black : Colors.black45,
                          ),
                          const SizedBox(width: 5),
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

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(10) : Radius.zero,
        bottom: isLast ? const Radius.circular(10) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Radio<String>(
                value: label == 'Monthly Report' ? 'monthly' : 'annual',
                groupValue: selected
                    ? (label == 'Monthly Report' ? 'monthly' : 'annual')
                    : null,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primaryCyan,
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
                      color: selected
                          ? AppColors.textWhite
                          : AppColors.textGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected
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
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 13),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGray,
            size: 20,
          ),
          style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
          dropdownColor: AppColors.cardBackground,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemLabel(item),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13,
                    ),
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
    required this.isNarrow,
    required this.months,
    required this.years,
    required this.businessNameOptions,
    required this.selectedMonth,
    required this.selectedYear,
    required this.selectedBusinessName,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onBusinessNameChanged,
    required this.onClear,
  });

  final bool isNarrow;
  final List<String> months;
  final List<String> years;
  final List<String> businessNameOptions;
  final String selectedMonth;
  final String selectedYear;
  final String selectedBusinessName;
  final void Function(String?) onMonthChanged;
  final void Function(String?) onYearChanged;
  final void Function(String?) onBusinessNameChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final monthValue = selectedMonth.isEmpty ? 'All Months' : selectedMonth;
    final yearValue = selectedYear.isEmpty ? 'All Years' : selectedYear;
    final nameValue =
        selectedBusinessName.isEmpty ? 'All' : selectedBusinessName;

    if (isNarrow) {
      return SizedBox(
        width: double.infinity,
        child: Container(
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
                children: [
                  Expanded(
                    child: _FilterDropdown(
                      label: 'Month',
                      value: monthValue,
                      items: months,
                      onChanged: onMonthChanged,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _FilterDropdown(
                      label: 'Year',
                      value: yearValue,
                      items: years,
                      onChanged: onYearChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _FilterDropdown(
                label: 'Business',
                value: nameValue,
                items: businessNameOptions,
                onChanged: onBusinessNameChanged,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 58,
        children: [
          _FilterDropdown(
            label: 'Month',
            value: monthValue,
            items: months,
            onChanged: onMonthChanged,
          ),
          _FilterDropdown(
            label: 'Year',
            value: yearValue,
            items: years,
            onChanged: onYearChanged,
          ),
          _FilterDropdown(
            label: 'Business',
            value: nameValue,
            items: businessNameOptions,
            onChanged: onBusinessNameChanged,
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
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
              dropdownColor: AppColors.cardBackground,
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                        ),
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

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.isNarrow,
    required this.onGenerateTap,
  });

  final bool isNarrow;
  final VoidCallback onGenerateTap;

  @override
  Widget build(BuildContext context) {
    final generateBtn = _HeaderButton(
      icon: Icons.description_rounded,
      label: isNarrow ? 'Generate' : 'Generate Report',
      isPrimary: true,
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
          'Generate and download reports',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );



    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [titleBlock, generateBtn],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.isPrimary = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;

    if (isPrimary) {
      bg = AppColors.primaryCyan;
      border = AppColors.primaryCyan;
      fg = Colors.white;
    } else {
      bg = AppColors.cardBackground;
      border = AppColors.cardBorder;
      fg = AppColors.textGray;
    }

    return GestureDetector(
      onTap: onTap,
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
            Icon(icon, color: fg, size: 16),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
