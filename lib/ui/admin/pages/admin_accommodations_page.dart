// lib/ui/admin/pages/admin_accommodations_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app/core/enums/business_enums.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/accommodation_export_service.dart';
import '../../shared/layouts/admin_layout.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../../shared/widgets/paginator.dart';
import '../widgets/business_details_modal.dart';
import '../models/accommodation_models.dart';
import '../../../api/messages_api.dart';
import '../../../core/services/session_service.dart';
import '../../../api/admin_accommodation_api.dart';

// ─── View mode ────────────────────────────────────────────────────────────────

enum _ViewMode { info, rankings }

// ─── Filter tabs (info mode only) ────────────────────────────────────────────

class _FilterTab {
  const _FilterTab({required this.label, this.status});
  final String label;
  final AccommodationStatus? status;
}

const _filterTabs = [
  _FilterTab(label: 'All'),
  _FilterTab(label: 'Pending', status: AccommodationStatus.pending),
  _FilterTab(label: 'Approved', status: AccommodationStatus.approved),
  _FilterTab(label: 'Rejected', status: AccommodationStatus.rejected),
  _FilterTab(label: 'Warning', status: AccommodationStatus.warning),
];

// ─── Accommodations Page ──────────────────────────────────────────────────────

class AdminAccommodationsPage extends StatefulWidget {
  const AdminAccommodationsPage({super.key});

  @override
  State<AdminAccommodationsPage> createState() =>
      _AdminAccommodationsPageState();
}

class _AdminAccommodationsPageState extends State<AdminAccommodationsPage> {
  final _api = AdminAccommodationApi();
  final _messagesApi = MessagesApi();

  // ── View toggle ───────────────────────────────────────────────────────────
  _ViewMode _viewMode = _ViewMode.info;
  int _rankingsRefreshKey = 0;

  // ── Info mode state ───────────────────────────────────────────────────────
  int _selectedTab = 0;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  int _currentPage = 0;
  int _pageSize = 10;
  bool _isExporting = false;

  static const List<int> _pageSizeOptions = [10, 20, 30];

  List<Accommodation> _accommodations = [];
  Map<String, int>? _statusCounts;
  bool _isLoading = true;
  String? _error;
  int? _errorCode;
  String? _senderId;
  String? _senderName;
  String? _senderEmail;
  String? _senderPhone;

  @override
  void initState() {
    super.initState();
    _loadSession();
    _loadAccommodations();
  }

  Future<void> _loadSession() async {
    final session =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    if (!mounted) return;
    setState(() {
      _senderId = session?.userId;
      _senderName = session?.fullName;
      _senderEmail = session?.email;
      _senderPhone = session?.phone;
    });
  }

  void _handleRefresh() {
    if (_viewMode == _ViewMode.info) {
      _loadAccommodations();
    } else {
      setState(() => _rankingsRefreshKey++);
    }
  }

  // ── Server-side pagination state ──────────────────────────────────────────

  int _totalPages = 0;
  int _totalItems = 0;

  String get _activeStatus => _filterTabs[_selectedTab].status?.name ?? 'all';

  Future<void> _loadAccommodations() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _errorCode = null;
    });
    try {
      final result = await _api.fetchAll(
        page: _currentPage + 1,
        pageSize: _pageSize,
        status: _activeStatus,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (!mounted) return;
      setState(() {
        _accommodations = result.data;
        _totalPages = result.pageCount;
        _totalItems = result.totalCount;
        _isLoading = false;
      });
      // Fire parallel status count requests
      final statusCounts = <String, int>{};
      final results = await Future.wait([
        _api.fetchStatusCount('approved'),
        _api.fetchStatusCount('pending'),
        _api.fetchStatusCount('rejected'),
        _api.fetchStatusCount('warning'),
      ]);
      final labels = ['approved', 'pending', 'rejected', 'warning'];
      for (int i = 0; i < labels.length; i++) {
        statusCounts[labels[i]] = results[i];
      }
      if (!mounted) return;
      setState(() => _statusCounts = statusCounts);
    } catch (e) {
      final code = await classifyError(e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _errorCode = code;
      });
    }
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _showExportDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => _ExportDialog(
        onExportExcel: () async {
          Navigator.of(ctx).pop();
          await _runExport(excel: true);
        },
        onExportPdf: () async {
          Navigator.of(ctx).pop();
          await _runExport(excel: false);
        },
      ),
    );
  }

  Future<void> _runExport({required bool excel}) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final rows = await _api.fetchExportRows();
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No accommodation data to export.'),
            backgroundColor: Color(0xFFFFA000),
          ),
        );
        return;
      }
      if (excel) {
        await AccommodationExportService.exportToExcel(rows, context);
      } else {
        await AccommodationExportService.exportToPdf(rows, context);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Status update ─────────────────────────────────────────────────────────

  Future<void> _updateStatus(
    Accommodation item,
    AccommodationStatus newStatus, {
    String? remarks,
  }) async {
    AccommodationResult result;
    switch (newStatus) {
      case AccommodationStatus.approved:
        result = await _api.approve(item.id, remarks: remarks);
        break;
      case AccommodationStatus.rejected:
        result = await _api.reject(item.id, remarks: remarks);
        break;
      case AccommodationStatus.warning:
        result = await _api.flag(item.id, remarks: remarks);
        break;
      default:
        return;
    }

    if (!mounted) return;

    if (result.success) {
      await _sendDecisionLetter(item, newStatus, remarks: remarks);
      _loadAccommodations();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name} has been ${newStatus.name}.'),
          backgroundColor: newStatus == AccommodationStatus.approved
              ? const Color(0xFF00C48C)
              : const Color(0xFFFF4D6A),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Something went wrong.'),
          backgroundColor: const Color(0xFFFF4D6A),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _sendDecisionLetter(
    Accommodation item,
    AccommodationStatus newStatus, {
    String? remarks,
  }) async {
    if (newStatus != AccommodationStatus.approved) return;

    final senderId = _senderId;
    final senderName = _senderName;
    final senderEmail = _senderEmail;
    final senderPhone = _senderPhone;

    if (senderId == null ||
        senderName == null ||
        senderEmail == null ||
        senderPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Accommodation was updated, but the decision letter could not be sent because the admin session is missing.',
          ),
          backgroundColor: Color(0xFFFFA000),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    const subject = 'Accommodation Application Approved';
    final remarksText = remarks?.trim();
    final remarksSection =
        remarksText?.isNotEmpty == true ? '\n\nRemarks: $remarksText' : '';
    final body =
        'We\'re pleased to let you know your accommodation application has been approved.$remarksSection';
    const messageType = MessageType.announcement;

    try {
      final letter = buildOfficialMessageLetter(
        recipient: item.name,
        subject: subject,
        messageContent: body,
        senderFullName: senderName,
        senderEmail: senderEmail,
        senderPhone: senderPhone,
        messageType: messageType,
      );
      await _messagesApi.sendToSelected(
        senderId: senderId,
        businessIds: [item.id],
        messageType: messageType,
        subject: subject,
        content: letter,
      );
      unawaited(MessageBadgeController.instance.refresh());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Accommodation was updated, but the decision letter failed to send: $e',
          ),
          backgroundColor: const Color(0xFFFFA000),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Accommodations',
      selectedIndex: 1,
      onNavSelected: (_) {},
      child: _error != null && _viewMode == _ViewMode.info
          ? ErrorPage(
              statusCode: _errorCode ?? 500,
              onRetry: _loadAccommodations,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                final isMobile = constraints.maxWidth < 600;
                final padding = EdgeInsets.all(isNarrow ? 16 : 24);

                final header = _PageHeader(
                  onRefresh: _handleRefresh,
                  onExport: _showExportDialog,
                  isExporting: _isExporting,
                  viewMode: _viewMode,
                  onViewModeChanged: (m) => setState(() => _viewMode = m),
                  isNarrow: isMobile,
                );

                // ── Rankings mode ─────────────────────────────────────
                if (_viewMode == _ViewMode.rankings) {
                  return SingleChildScrollView(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        const SizedBox(height: 20),
                        _RankingsView(
                          key: ValueKey(_rankingsRefreshKey),
                          api: _api,
                        ),
                      ],
                    ),
                  );
                }

                // ── Info mode ─────────────────────────────────────────
                return RefreshIndicator(
                  onRefresh: _loadAccommodations,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        const SizedBox(height: 20),
                        _FilterTabBar(
                          selectedTab: _selectedTab,
                          tabs: _filterTabs,
                          totalCount: _totalItems,
                          statusCounts: _statusCounts,
                          onTabSelected: (i) {
                            setState(() {
                              _selectedTab = i;
                              _currentPage = 0;
                            });
                            _loadAccommodations();
                          },
                        ),
                        const SizedBox(height: 14),
                        _SearchBar(
                          controller: _searchCtrl,
                          onChanged: (v) {
                            setState(() {
                              _searchQuery = v;
                              _currentPage = 0;
                            });
                            _loadAccommodations();
                          },
                        ),
                        const SizedBox(height: 14),
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: CircularProgressIndicator(
                                color: AppColors.primaryCyan,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        else if (isNarrow)
                          _AccommodationCardList(
                            rows: _accommodations,
                            onStatusUpdate: _updateStatus,
                          )
                        else
                          _AccommodationTable(
                            rows: _accommodations,
                            onStatusUpdate: _updateStatus,
                          ),
                        if (!_isLoading) ...[
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
                              _loadAccommodations();
                            },
                            onPageChanged: (page) {
                              setState(() => _currentPage = page);
                              _loadAccommodations();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ─── View Toggle ──────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.selected, required this.onChanged});

  final _ViewMode selected;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleOption(
            label: 'Info',
            icon: Icons.list_alt_rounded,
            isActive: selected == _ViewMode.info,
            onTap: () => onChanged(_ViewMode.info),
          ),
          _ToggleOption(
            label: 'Rankings',
            icon: Icons.emoji_events_rounded,
            isActive: selected == _ViewMode.rankings,
            onTap: () => onChanged(_ViewMode.rankings),
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  const _ToggleOption({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? Colors.white : AppColors.textGray,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : AppColors.textGray,
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Export Dialog ────────────────────────────────────────────────────────────

class _ExportDialog extends StatelessWidget {
  const _ExportDialog({required this.onExportExcel, required this.onExportPdf});

  final VoidCallback onExportExcel;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryCyan.withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        color: AppColors.primaryCyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Export Accommodations',
                            style: TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Download the full accommodations list',
                            style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textGray,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: AppColors.cardBorder, height: 1),
                const SizedBox(height: 20),
                _ExportFormatButton(
                  icon: Icons.table_chart_rounded,
                  label: 'Excel Spreadsheet',
                  subtitle: 'Download as .xlsx file',
                  color: const Color(0xFF1D6F42),
                  onTap: onExportExcel,
                ),
                const SizedBox(height: 10),
                _ExportFormatButton(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF Document',
                  subtitle: 'Share or save as .pdf file',
                  color: const Color(0xFFB91C1C),
                  onTap: onExportPdf,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.cardBorder.withOpacity(0.5),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.textSubtle,
                        size: 14,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Exports all records regardless of active filters.',
                          style: TextStyle(
                            color: AppColors.textSubtle,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportFormatButton extends StatefulWidget {
  const _ExportFormatButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ExportFormatButton> createState() => _ExportFormatButtonState();
}

class _ExportFormatButtonState extends State<_ExportFormatButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withOpacity(0.12)
                : widget.color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? widget.color.withOpacity(0.4)
                  : widget.color.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: _hovered
                            ? AppColors.textWhite
                            : AppColors.textGray,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: widget.color.withOpacity(_hovered ? 0.8 : 0.4),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.onRefresh,
    required this.onExport,
    required this.isExporting,
    required this.viewMode,
    required this.onViewModeChanged,
    this.isNarrow = false,
  });

  final VoidCallback onRefresh;
  final VoidCallback onExport;
  final bool isExporting;
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final titleSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Accommodations',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            viewMode == _ViewMode.info
                ? 'Manage registered accommodation establishments'
                : 'Tourist rankings by accommodation',
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );

    final actionSection = Row(
      mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment:
          isNarrow ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
      children: [
        _ViewToggle(
          selected: viewMode,
          onChanged: onViewModeChanged,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            // Export only shown in info mode
            if (viewMode == _ViewMode.info) ...[
              Tooltip(
                message: 'Export',
                child: _ExportIconButton(
                  onTap: isExporting ? null : onExport,
                  isLoading: isExporting,
                ),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppColors.textGray,
              ),
              tooltip: 'Refresh',
            ),
          ],
        ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleSection,
          const SizedBox(height: 16),
          actionSection,
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: titleSection),
        const SizedBox(width: 16),
        actionSection,
      ],
    );
  }
}

class _ExportIconButton extends StatelessWidget {
  const _ExportIconButton({required this.onTap, required this.isLoading});

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

// ─── Rankings View ────────────────────────────────────────────────────────────

class _RankingsView extends StatefulWidget {
  const _RankingsView({super.key, required this.api});
  final AdminAccommodationApi api;

  @override
  State<_RankingsView> createState() => _RankingsViewState();
}

class _RankingsViewState extends State<_RankingsView> {
  static const _monthNames = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  late int _month;
  late int _year;
  List<AccommodationRankingRow> _rankings = [];
  bool _isLoading = false;
  String? _error;

  // Prevents stale responses from overwriting newer results
  int _loadId = 0;

  List<int> get _years {
    final now = DateTime.now().year;
    return [0, ...List.generate(5, (i) => now - 4 + i)];
  }

  int get _totalGuests => _rankings.fold(0, (sum, r) => sum + r.totalGuests);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _load();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await widget.api.fetchRankings(month: _month, year: _year);
      if (!mounted || id != _loadId) return;
      setState(() {
        _rankings = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _onMonthChanged(int? m) {
    if (m == null) return;
    setState(() => _month = m);
    _load();
  }

  void _onYearChanged(int? y) {
    if (y == null) return;
    setState(() => _year = y);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Period selector row ───────────────────────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.filter_list_rounded,
                  color: AppColors.textSubtle,
                  size: 15,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Period:',
                  style: TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 10),
                _StyledDropdown<int>(
                  value: _month,
                  items: List.generate(13, (i) => i),
                  labelBuilder: (m) => m == 0 ? 'All Months' : _monthNames[m - 1],
                  onChanged: _onMonthChanged,
                ),
                const SizedBox(width: 8),
                _StyledDropdown<int>(
                  value: _year,
                  items: _years,
                  labelBuilder: (y) => y == 0 ? 'All Years' : y.toString(),
                  onChanged: _onYearChanged,
                ),
              ],
            ),
            // Total tourists chip — only shown when data is ready
            if (!_isLoading && _rankings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryCyan.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.people_rounded,
                      color: AppColors.primaryCyan,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_commify(_totalGuests)} total tourists',
                      style: const TextStyle(
                        color: AppColors.primaryCyan,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        // ── Rankings content ──────────────────────────────────────
        _buildContent(),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: CircularProgressIndicator(
            color: AppColors.primaryCyan,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppColors.textGray.withOpacity(0.5),
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Failed to load rankings',
                style: TextStyle(color: AppColors.textGray, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _load,
                child: const Text(
                  'Try again',
                  style: TextStyle(color: AppColors.primaryCyan),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_rankings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                color: AppColors.textGray.withOpacity(0.25),
                size: 52,
              ),
              const SizedBox(height: 14),
              Text(
                'No tourist records found',
                style: TextStyle(
                  color: AppColors.textGray.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_month == 0 ? "All Months" : _monthNames[_month - 1]} ${_year == 0 ? "All Years" : _year}',
                style: const TextStyle(
                  color: AppColors.textSubtle,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxGuests = _rankings.first.totalGuests;

    return Column(
      children: _rankings.asMap().entries.map((entry) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: entry.key < _rankings.length - 1 ? 10 : 0,
          ),
          child: _RankingCard(row: entry.value, maxGuests: maxGuests),
        );
      }).toList(),
    );
  }
}

// ─── Styled Dropdown ──────────────────────────────────────────────────────────

class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: AppColors.cardBackground,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGray,
            size: 18,
          ),
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13.5,
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelBuilder(item),
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13.5,
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

// ─── Ranking Card ─────────────────────────────────────────────────────────────

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.row, required this.maxGuests});

  final AccommodationRankingRow row;
  final int maxGuests;

  static const _medals = ['🥇', '🥈', '🥉'];

  Color get _rankColor {
    switch (row.rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return AppColors.textGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTop3 = row.rank <= 3;
    final rankColor = _rankColor;
    final progress = maxGuests > 0 ? row.totalGuests / maxGuests : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isTop3 ? rankColor.withOpacity(0.06) : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3 ? rankColor.withOpacity(0.28) : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          // ── Rank badge ────────────────────────────────────────
          SizedBox(
            width: 48,
            child: Center(
              child: isTop3
                  ? Text(
                      _medals[row.rank - 1],
                      style: const TextStyle(fontSize: 28),
                    )
                  : Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${row.rank}',
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Name + progress bar ───────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.businessName,
                  style: TextStyle(
                    color: isTop3 ? AppColors.textWhite : AppColors.textGray,
                    fontSize: isTop3 ? 14.5 : 14,
                    fontWeight: isTop3 ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.cardBorder.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isTop3
                          ? rankColor.withOpacity(0.65)
                          : AppColors.primaryCyan.withOpacity(0.35),
                    ),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // ── Tourist count ─────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _commify(row.totalGuests),
                style: TextStyle(
                  color: isTop3 ? rankColor : AppColors.textWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'tourists',
                style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Filter Tab Bar ───────────────────────────────────────────────────────────

class _FilterTabBar extends StatelessWidget {
  const _FilterTabBar({
    required this.selectedTab,
    required this.tabs,
    required this.totalCount,
    this.statusCounts,
    required this.onTabSelected,
  });

  final int selectedTab;
  final List<_FilterTab> tabs;
  final int totalCount;
  final Map<String, int>? statusCounts;
  final ValueChanged<int> onTabSelected;

  int _countFor(int i) {
    if (i == selectedTab) return totalCount;
    final status = tabs[i].status;
    if (status == null || statusCounts == null) return 0;
    return statusCounts![status.name] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        if (!isNarrow) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(tabs.length, (i) {
                final isActive = selectedTab == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: tabs[i].label,
                    count: _countFor(i),
                    isActive: isActive,
                    onTap: () => onTabSelected(i),
                  ),
                );
              }),
            ),
          );
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(tabs.length, (i) {
            final isActive = selectedTab == i;
            return _FilterChip(
              label: tabs[i].label,
              count: _countFor(i),
              isActive: isActive,
              onTap: () => onTabSelected(i),
            );
          }),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          color: isActive ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.transparent : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : AppColors.textGray,
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withOpacity(0.25)
                    : AppColors.cardBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textGray,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
        decoration: const InputDecoration(
          hintText: 'Search by name or owner...',
          hintStyle: TextStyle(color: AppColors.textSubtle, fontSize: 13),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.textSubtle,
            size: 18,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

// ─── Accommodation Table (wide screens) ──────────────────────────────────────

class _AccommodationTable extends StatelessWidget {
  const _AccommodationTable({required this.rows, required this.onStatusUpdate});

  final List<Accommodation> rows;
  final Function(Accommodation, AccommodationStatus, {String? remarks})
  onStatusUpdate;

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
          _TableHeader(),
          const Divider(color: AppColors.cardBorder, height: 1),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No accommodations found.',
                style: TextStyle(color: AppColors.textGray),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.cardBorder, height: 1),
              itemBuilder: (_, i) =>
                  _TableRow(item: rows[i], onStatusUpdate: onStatusUpdate),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Business Name'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Type'),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Business Line'),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Owner'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Contact'),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Rooms'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Status'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _HeaderCell('Actions'),
            ),
          ),
        ],
      ),
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

class _TableRow extends StatelessWidget {
  const _TableRow({required this.item, required this.onStatusUpdate});

  final Accommodation item;
  final Function(Accommodation, AccommodationStatus, {String? remarks})
  onStatusUpdate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primaryCyan.withOpacity(0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.primaryCyan,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.businessType.label,
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.businessLineLabel,
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.owner,
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.contact,
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${item.rooms}',
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusBadge(status: item.status),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _ActionButtons(
                  item: item,
                  onStatusUpdate: onStatusUpdate,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Accommodation Card List (narrow screens) ─────────────────────────────────

class _AccommodationCardList extends StatelessWidget {
  const _AccommodationCardList({
    required this.rows,
    required this.onStatusUpdate,
  });

  final List<Accommodation> rows;
  final Function(Accommodation, AccommodationStatus, {String? remarks})
  onStatusUpdate;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'No accommodations found.',
          style: TextStyle(color: AppColors.textGray),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _AccommodationCard(item: rows[i], onStatusUpdate: onStatusUpdate),
    );
  }
}

class _AccommodationCard extends StatelessWidget {
  const _AccommodationCard({required this.item, required this.onStatusUpdate});

  final Accommodation item;
  final Function(Accommodation, AccommodationStatus, {String? remarks})
  onStatusUpdate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryCyan.withOpacity(0.2),
                  ),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: AppColors.primaryCyan,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 12),
          _CardDetail(label: 'Type', value: item.businessType.label),
          const SizedBox(height: 6),
          _CardDetail(label: 'Business Line', value: item.businessLineLabel),
          const SizedBox(height: 6),
          _CardDetail(label: 'Owner', value: item.owner),
          const SizedBox(height: 6),
          _CardDetail(label: 'Contact', value: item.contact),
          const SizedBox(height: 6),
          _CardDetail(label: 'Rooms', value: '${item.rooms}'),
          const SizedBox(height: 12),
          _ActionButtons(item: item, onStatusUpdate: onStatusUpdate),
        ],
      ),
    );
  }
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSubtle,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AccommodationStatus status;

  static _BadgeStyle _styleFor(AccommodationStatus s) {
    switch (s) {
      case AccommodationStatus.approved:
        return _BadgeStyle(label: 'Approved', color: AppColors.accentGreen);
      case AccommodationStatus.pending:
        return _BadgeStyle(label: 'Pending', color: AppColors.accentPurple);
      case AccommodationStatus.rejected:
        return _BadgeStyle(label: 'Rejected', color: AppColors.accentRed);
      case AccommodationStatus.warning:
        return _BadgeStyle(label: 'Warning', color: AppColors.accentOrange);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withOpacity(0.3)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: style.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              style.label,
              style: TextStyle(
                color: style.color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeStyle {
  const _BadgeStyle({required this.label, required this.color});
  final String label;
  final Color color;
}

String _formatRegisteredDate(String? rawValue) {
  final value = rawValue?.trim() ?? '';
  if (value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final local = parsed.toLocal();
  return '${monthNames[local.month - 1]} ${local.day}, ${local.year}';
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.item, required this.onStatusUpdate});

  final Accommodation item;
  final Function(Accommodation, AccommodationStatus, {String? remarks})
  onStatusUpdate;

  Future<void> _showRemarksModal(
    BuildContext context, {
    required AccommodationStatus action,
  }) async {
    final isApprove = action == AccommodationStatus.approved;
    final color = isApprove ? const Color(0xFF00C48C) : const Color(0xFFFF4D6A);
    final icon = isApprove
        ? Icons.check_circle_outline_rounded
        : Icons.cancel_outlined;
    final label = isApprove ? 'Approve' : 'Reject';
    final remarksCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => Material(
        color: Colors.transparent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$label Application',
                              style: const TextStyle(
                                color: AppColors.textWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.name,
                              style: const TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textGray,
                          size: 18,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.cardBorder, height: 1),
                  const SizedBox(height: 20),
                  const Text(
                    'Remarks',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This will be visible to the business owner.',
                    style: TextStyle(
                      color: AppColors.textSubtle,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 4,
                    minLines: 3,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add remarks (optional)...',
                      hintStyle: const TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.cardBorder.withOpacity(0.2),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: color.withOpacity(0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _ModalButton(
                          label: 'Cancel',
                          color: AppColors.textGray,
                          onTap: () => Navigator.of(ctx).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModalButton(
                          label: label,
                          color: color,
                          filled: true,
                          onTap: () => Navigator.of(ctx).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final remarks = remarksCtrl.text.trim();
      onStatusUpdate(item, action, remarks: remarks.isEmpty ? null : remarks);
    }
    remarksCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPending = item.status == AccommodationStatus.pending;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionIconButton(
            icon: Icons.remove_red_eye_outlined,
            tooltip: 'View Details',
            color: AppColors.primaryCyan,
            showBorder: true,
            label: 'View',
            onTap: () {
              showBusinessDetailsModal(
                context,
                BusinessDetails(
                  name: item.name,
                  tradeName: item.tradeName,
                  type: item.businessType.label,
                  businessLine: item.businessLineLabel,
                  rooms: item.rooms,
                  status: item.status,
                  owner: item.owner,
                  permitNumber: item.permitNumber,
                  registrationNumber: item.registrationNumber,
                  registeredDate: _formatRegisteredDate(item.createdAt),
                  address: item.address,
                  street: item.street,
                  barangay: item.barangay,
                  cityMunicipality: item.cityMunicipality,
                  province: item.province,
                  region: item.region,
                  phone: item.contact,
                  email: item.email ?? '—',
                  permitFileUrl: item.permitFileUrl,
                  validIdUrl: item.validIdUrl,
                ),
              );
            },
          ),
          if (isPending) ...[
            const SizedBox(width: 8),
            ActionIconButton(
              icon: Icons.check_circle_outline_rounded,
              tooltip: 'Approve',
              color: const Color(0xFF00C48C),
              onTap: () => _showRemarksModal(
                context,
                action: AccommodationStatus.approved,
              ),
            ),
            const SizedBox(width: 8),
            ActionIconButton(
              icon: Icons.cancel_outlined,
              tooltip: 'Reject',
              color: const Color(0xFFFF4D6A),
              onTap: () => _showRemarksModal(
                context,
                action: AccommodationStatus.rejected,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Modal Button ─────────────────────────────────────────────────────────────

class _ModalButton extends StatefulWidget {
  const _ModalButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  State<_ModalButton> createState() => _ModalButtonState();
}

class _ModalButtonState extends State<_ModalButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.filled
        ? (_hovered ? widget.color : widget.color.withOpacity(0.85))
        : (_hovered
              ? widget.color.withOpacity(0.15)
              : widget.color.withOpacity(0.08));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.filled
                  ? Colors.transparent
                  : widget.color.withOpacity(_hovered ? 0.5 : 0.25),
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.filled ? Colors.white : widget.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

/// Formats an integer with thousands commas (e.g. 12345 → "12,345").
String _commify(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);