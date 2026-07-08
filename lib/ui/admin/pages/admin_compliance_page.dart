// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app/core/services/connectivity_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../shared/layouts/admin_layout.dart';
import '../../shared/pages/error_page.dart';
import '../../../api/admin_compliance_api.dart';
import '../../../api/messages_api.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../../shared/widgets/paginator.dart';
import '../widgets/business_tourist_stats_modal.dart';

// ─── Filter Options ───────────────────────────────────────────────────────────

const _activityStatusOptions = [
  'All activity status',
  'Active',
  'Low Activity',
  'Inactive',
  'No Activity',
];

const _businessStatusOptions = ['All Business Statuses', 'Approved', 'Warning'];

const _businessLineOptions = [
  'All Business Lines',
  'Hotel',
  'Resort',
  'Motel',
  'Pension Inn',
  'Youth Hostel',
  'Apartment',
  'Others',
];

// ─── Admin Compliance Page ────────────────────────────────────────────────────

class AdminCompliancePage extends StatefulWidget {
  const AdminCompliancePage({super.key});

  @override
  State<AdminCompliancePage> createState() => _AdminCompliancePageState();
}

class _AdminCompliancePageState extends State<AdminCompliancePage> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<BusinessActivityRecord> _records = [];
  bool _isLoading = true;
  String? _fetchError;
  int? _errorCode;

  String _searchQuery = '';
  String _selectedActivityStatus = 'All activity status';
  String _selectedBusinessStatus = 'All Business Statuses';
  String _selectedBusinessLine = 'All Business Lines';

  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  int _activeCount = 0;
  int _atRiskCount = 0;
  int _inactiveCount = 0;

  bool _isOpeningStats = false;

  static const List<int> _pageSizeOptions = [10, 20, 30];

  final _searchCtrl = TextEditingController();

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _fetchError = null;
      _errorCode = null;
    });
    try {
      final result = await AdminComplianceApi().fetchActivitySummary(
        page: _currentPage + 1,
        pageSize: _pageSize,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        activityStatus: _selectedActivityStatus != 'All activity status' ? _selectedActivityStatus : null,
        businessStatus: _selectedBusinessStatus != 'All Business Statuses' ? _selectedBusinessStatus : null,
        businessLine: _selectedBusinessLine != 'All Business Lines' ? _selectedBusinessLine : null,
      );
      if (mounted) {
        setState(() {
          _records = result.data;
          _totalPages = result.pageCount;
          _totalItems = result.totalCount;
          _activeCount = result.summaryCounts.active;
          _atRiskCount = result.summaryCounts.lowActivity;
          _inactiveCount = result.summaryCounts.inactive;
          _isLoading = false;
        });
      }
    } catch (e) {
      final code = await classifyError(e);
      if (mounted) {
        setState(() {
          _fetchError = e.toString();
          _errorCode = code;
          _isLoading = false;
        });
      }
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _openActionDialog(BusinessActivityRecord record) {
    showDialog(
      context: context,
      builder: (_) => _StatusChangeDialog(
        record: record,
        onConfirm: (newStatus, reason) =>
            _handleStatusChange(record, newStatus, reason),
      ),
    );
  }

  void _openStatsModal(BusinessActivityRecord record) {
    if (_isOpeningStats) return;
    _isOpeningStats = true;
    showDialog(
      context: context,
      builder: (_) => BusinessTouristStatsModal(
        businessId: record.id,
        businessName: record.businessName,
      ),
    ).whenComplete(() {
      _isOpeningStats = false;
    });
  }

  Future<void> _handleStatusChange(
    BusinessActivityRecord record,
    BusinessStatusLevel newStatus,
    String reason,
  ) async {
    final session = SessionService.instance.current;
    final messageContent = buildOfficialMessageLetter(
      recipient: record.businessName,
      subject: 'Business Status Update',
      messageContent: reason,
      senderFullName: session?.fullName ?? 'Tourism Officer',
      senderEmail: session?.email ?? '',
      senderPhone: session?.phone ?? '',
      messageType: MessageType.compliance,
    );
    try {
      await AdminComplianceApi().updateBusinessStatus(
        record.id,
        newStatus,
        reason: reason,
        messageContent: messageContent,
      );
      if (mounted) {
        _load();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Business status updated successfully'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Business line label → raw DB value ────────────────────────────────────
  String _rawBusinessLine(String label) {
    switch (label) {
      case 'Hotel':
        return 'hotel';
      case 'Resort':
        return 'resort';
      case 'Motel':
        return 'motel';
      case 'Pension Inn':
        return 'pension_inn';
      case 'Youth Hostel':
        return 'youth_hostel';
      case 'Apartment':
        return 'apartment';
      case 'Others':
        return 'others';
      default:
        return label.toLowerCase();
    }
  }

  ActivityStatus _activityStatusFromLabel(String label) {
    switch (label) {
      case 'Active':
        return ActivityStatus.active;
      case 'Low Activity':
        return ActivityStatus.lowActivity;
      case 'Inactive':
        return ActivityStatus.inactive;
      case 'No Activity':
      default:
        return ActivityStatus.noActivity;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Compliance',
      selectedIndex: 4,
      onNavSelected: (_) {},
      child: _fetchError != null
          ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _load)
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        return SingleChildScrollView(
          padding: EdgeInsets.all(isNarrow ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PageHeader(
                onRefresh: _load,
                totalAccommodations: _records.length,
              ),
              const SizedBox(height: 20),
              _SummaryCards(
                active: _activeCount,
                atRisk: _atRiskCount,
                inactive: _inactiveCount,
              ),
              const SizedBox(height: 16),
              _FilterRow(
                searchCtrl: _searchCtrl,
                onSearchChanged: (v) {
                  setState(() {
                    _searchQuery = v;
                    _currentPage = 0;
                  });
                  _load();
                },
                selectedActivityStatus: _selectedActivityStatus,
                onActivityStatusChanged: (v) {
                  setState(() {
                    _selectedActivityStatus = v!;
                    _currentPage = 0;
                  });
                  _load();
                },
                selectedBusinessStatus: _selectedBusinessStatus,
                onBusinessStatusChanged: (v) {
                  setState(() {
                    _selectedBusinessStatus = v!;
                    _currentPage = 0;
                  });
                  _load();
                },
                selectedBusinessLine: _selectedBusinessLine,
                onBusinessLineChanged: (v) {
                  setState(() {
                    _selectedBusinessLine = v!;
                    _currentPage = 0;
                  });
                  _load();
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
              else
                _ComplianceTable(
                  rows: _records,
                  onAction: _openActionDialog,
                  onViewStats: _openStatsModal,
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
                    _load();
                  },
                  onPageChanged: (p) {
                    setState(() => _currentPage = p);
                    _load();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.onRefresh,
    required this.totalAccommodations,
  });

  final VoidCallback onRefresh;
  final int totalAccommodations;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 600;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compliance Tracker ($totalAccommodations)',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: isSmall ? 18 : 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitor guest recording activity of registered businesses',
                    style: TextStyle(
                      color: AppColors.textGray, 
                      fontSize: isSmall ? 11 : 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: onRefresh,
              icon: Icon(Icons.refresh_rounded, size: isSmall ? 18 : 20),
              color: AppColors.textGray,
              tooltip: 'Refresh',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cardBackground,
                padding: isSmall ? EdgeInsets.zero : null,
                minimumSize: isSmall ? const Size(34, 34) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: AppColors.cardBorder),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Summary Cards ────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.active,
    required this.atRisk,
    required this.inactive,
  });

  final int active;
  final int atRisk;
  final int inactive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 600;
        return Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.accentGreen,
                borderColor: AppColors.accentGreen,
                value: '$active',
                label: 'Active',
                isSmall: isSmall,
              ),
            ),
            SizedBox(width: isSmall ? 6 : 14),
            Expanded(
              child: _SummaryCard(
                icon: Icons.warning_amber_rounded,
                iconColor: AppColors.accentOrange,
                borderColor: AppColors.accentOrange,
                value: '$atRisk',
                label: 'Low Activity',
                isSmall: isSmall,
              ),
            ),
            SizedBox(width: isSmall ? 6 : 14),
            Expanded(
              child: _SummaryCard(
                icon: Icons.cancel_outlined,
                iconColor: AppColors.accentRed,
                borderColor: AppColors.accentRed,
                value: '$inactive',
                label: 'Inactive',
                isSmall: isSmall,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.borderColor,
    required this.value,
    required this.label,
    this.isSmall = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color borderColor;
  final String value;
  final String label;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 6 : 14,
        vertical: isSmall ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(isSmall ? 8 : 12),
        border: Border.all(color: borderColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: isSmall ? 13 : 16),
          SizedBox(width: isSmall ? 4 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: isSmall ? 8.5 : 11,
                  ),
                ),
                if (!isSmall) const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: isSmall ? 14 : 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filter Row ───────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.selectedActivityStatus,
    required this.onActivityStatusChanged,
    required this.selectedBusinessStatus,
    required this.onBusinessStatusChanged,
    required this.selectedBusinessLine,
    required this.onBusinessLineChanged,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final String selectedActivityStatus;
  final ValueChanged<String?> onActivityStatusChanged;
  final String selectedBusinessStatus;
  final ValueChanged<String?> onBusinessStatusChanged;
  final String selectedBusinessLine;
  final ValueChanged<String?> onBusinessLineChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DropdownFilter(
                      value: selectedActivityStatus,
                      items: _activityStatusOptions,
                      onChanged: onActivityStatusChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DropdownFilter(
                      value: selectedBusinessStatus,
                      items: _businessStatusOptions,
                      onChanged: onBusinessStatusChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DropdownFilter(
                value: selectedBusinessLine,
                items: _businessLineOptions,
                onChanged: onBusinessLineChanged,
              ),
            ],
          );
        } else if (width < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 38,
                      child: _SearchField(
                        controller: searchCtrl,
                        onChanged: onSearchChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _DropdownFilter(
                      value: selectedActivityStatus,
                      items: _activityStatusOptions,
                      onChanged: onActivityStatusChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DropdownFilter(
                      value: selectedBusinessStatus,
                      items: _businessStatusOptions,
                      onChanged: onBusinessStatusChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DropdownFilter(
                      value: selectedBusinessLine,
                      items: _businessLineOptions,
                      onChanged: onBusinessLineChanged,
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          return Row(
            children: [
              SizedBox(
                height: 38,
                width: 200,
                child: _SearchField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownFilter(
                  value: selectedActivityStatus,
                  items: _activityStatusOptions,
                  onChanged: onActivityStatusChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownFilter(
                  value: selectedBusinessStatus,
                  items: _businessStatusOptions,
                  onChanged: onBusinessStatusChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownFilter(
                  value: selectedBusinessLine,
                  items: _businessLineOptions,
                  onChanged: onBusinessLineChanged,
                ),
              ),
            ],
          );
        }
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

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
          hintText: 'Search business...',
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

class _DropdownFilter extends StatelessWidget {
  const _DropdownFilter({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = items.contains(value) ? value : items.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.cardBackground,
          iconEnabledColor: AppColors.textGray,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Compliance Table ─────────────────────────────────────────────────────────

class _ComplianceTable extends StatelessWidget {
  const _ComplianceTable({
    required this.rows,
    required this.onAction,
    required this.onViewStats,
  });

  final List<BusinessActivityRecord> rows;
  final ValueChanged<BusinessActivityRecord> onAction;
  final ValueChanged<BusinessActivityRecord> onViewStats;

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
          const _TableHeader(),
          const Divider(color: AppColors.cardBorder, height: 1),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'No records found.',
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
              itemBuilder: (_, i) => _ComplianceRow(
                record: rows[i],
                onAction: onAction,
                onViewStats: onViewStats,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Table Header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [Expanded(child: _HeaderCell('Business / Details'))],
            ),
          );
        } else {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: _HeaderCell('Business')),
                Expanded(flex: 3, child: _HeaderCell('Business Line')),
                Expanded(flex: 2, child: _HeaderCell('Business Status')),
                Expanded(flex: 3, child: _HeaderCell('Activity Status')),
                Expanded(flex: 3, child: _HeaderCell('Last Activity')),
                Expanded(flex: 4, child: _HeaderCell('Action')),
              ],
            ),
          );
        }
      },
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

// ─── Compliance Row ───────────────────────────────────────────────────────────

class _ComplianceRow extends StatelessWidget {
  const _ComplianceRow({
    required this.record,
    required this.onAction,
    required this.onViewStats,
  });

  final BusinessActivityRecord record;
  final ValueChanged<BusinessActivityRecord> onAction;
  final ValueChanged<BusinessActivityRecord> onViewStats;

  String _formatLastActivity(DateTime? dt) {
    if (dt == null) return '—';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return '1 day ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
    final years = (diff.inDays / 365).floor();
    return years == 1 ? '1 year ago' : '$years years ago';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          // ── Mobile layout ──────────────────────────────────────────────
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.businessName,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        record.businessLineLabel,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (ctx, bc) {
                          final columnWidth = (bc.maxWidth - 8) / 2;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              SizedBox(
                                width: columnWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Activity Status',
                                      style: TextStyle(
                                        color: AppColors.textGray,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    LayoutBuilder(
                                      builder: (ctx2, bc2) => ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: bc2.maxWidth,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: _ActivityBadge(
                                            status: record.activityStatus,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: columnWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Business Status',
                                      style: TextStyle(
                                        color: AppColors.textGray,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    LayoutBuilder(
                                      builder: (ctx2, bc2) => ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: bc2.maxWidth,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: _BusinessStatusBadge(
                                            status: record.businessStatus,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 12,
                            color: AppColors.textSubtle,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatLastActivity(record.lastActivity),
                            style: const TextStyle(
                              color: AppColors.textGray,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Stacked action buttons on mobile
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ActionIconButton(
                      icon: Icons.manage_accounts_rounded,
                      label: 'Manage',
                      color: AppColors.primaryCyan,
                      showBorder: true,
                      onTap: () => onAction(record),
                    ),
                    const SizedBox(height: 8),
                    ActionIconButton(
                      icon: Icons.bar_chart_rounded,
                      label: 'View',
                      color: AppColors.accentGreen,
                      showBorder: true,
                      onTap: () => onViewStats(record),
                    ),
                  ],
                ),
              ],
            ),
          );
        } else {
          // ── Desktop layout ─────────────────────────────────────────────
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    record.businessName,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    record.businessLineLabel,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _BusinessStatusBadge(status: record.businessStatus),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ActivityBadge(status: record.activityStatus),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _formatLastActivity(record.lastActivity),
                    style: TextStyle(
                      color: record.lastActivity != null
                          ? AppColors.textGray
                          : AppColors.textSubtle,
                      fontSize: 13,
                    ),
                  ),
                ),
                // Action column — Manage + View Stats side by side, wraps if narrow
                Expanded(
                  flex: 4,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionIconButton(
                        icon: Icons.manage_accounts_rounded,
                        label: 'Manage',
                        color: AppColors.primaryCyan,
                        showBorder: true,
                        onTap: () => onAction(record),
                      ),
                      ActionIconButton(
                        icon: Icons.bar_chart_rounded,
                        label: 'View',
                        color: AppColors.accentGreen,
                        showBorder: true,
                        onTap: () => onViewStats(record),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

// ─── Status Change Dialog ─────────────────────────────────────────────────────

class _StatusChangeDialog extends StatefulWidget {
  const _StatusChangeDialog({required this.record, required this.onConfirm});

  final BusinessActivityRecord record;
  final Future<void> Function(BusinessStatusLevel, String) onConfirm;

  @override
  State<_StatusChangeDialog> createState() => _StatusChangeDialogState();
}

class _StatusChangeDialogState extends State<_StatusChangeDialog> {
  late BusinessStatusLevel _selected;
  bool _isSaving = false;
  final _reasonCtrl = TextEditingController();
  final _reasonNode = FocusNode();

  bool get _canSetWarning =>
      (widget.record.activityStatus == ActivityStatus.inactive ||
          widget.record.activityStatus == ActivityStatus.noActivity) &&
      widget.record.businessStatus == BusinessStatusLevel.approved;

  bool get _canSetApproved =>
      widget.record.businessStatus == BusinessStatusLevel.warning;

  bool get _hasAction => _canSetWarning || _canSetApproved;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _reasonNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reasonCtrl.addListener(() => setState(() {}));
    if (_canSetWarning) {
      _selected = BusinessStatusLevel.warning;
    } else if (_canSetApproved) {
      _selected = BusinessStatusLevel.approved;
    } else {
      _selected = widget.record.businessStatus;
    }
  }

  Future<void> _confirm() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) return;
    if (_selected == widget.record.businessStatus) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _isSaving = true);
    await widget.onConfirm(_selected, reason);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildActionInfo({
    required String label,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.manage_accounts_rounded,
                      color: AppColors.primaryCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Business Status',
                          style: TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.record.businessName,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textGray,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: AppColors.cardBorder, height: 1),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Current Status',
                    style: TextStyle(color: AppColors.textGray, fontSize: 12),
                  ),
                  const Spacer(),
                  _BusinessStatusBadge(status: widget.record.businessStatus),
                ],
              ),
              const SizedBox(height: 16),
              if (!_hasAction) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.accentOrange.withOpacity(0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: AppColors.accentOrange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No status change is available. Warning can only be set for '
                          'Inactive or No Activity businesses, and only when their '
                          'current status is Approved.',
                          style: TextStyle(
                            color: AppColors.accentOrange,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textGray,
                      side: BorderSide(color: AppColors.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
              if (_hasAction) ...[
                if (_canSetWarning)
                  _buildActionInfo(
                    label: 'Set to Warning',
                    description: 'Flag this business for attention or follow-up.',
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.accentOrange,
                  ),
                if (_canSetApproved)
                  _buildActionInfo(
                    label: 'Revert to Approved',
                    description: 'Remove warning and restore good standing.',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.accentGreen,
                  ),
                const SizedBox(height: 16),
                Text(
                  'Reason for change *',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonCtrl,
                  focusNode: _reasonNode,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Explain why this status is being changed...',
                    hintStyle: const TextStyle(
                      color: AppColors.textSubtle, fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primaryCyan),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textGray,
                          side: BorderSide(color: AppColors.cardBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_isSaving || _reasonCtrl.text.trim().isEmpty)
                            ? null
                            : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryCyan,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: AppColors.primaryCyan.withOpacity(0.25),
                          disabledForegroundColor: Colors.black38,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black54,
                                ),
                              )
                            : const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared Status Chip ───────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.color,
    required this.label,
    required this.icon,
  });

  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Activity Status Badge ────────────────────────────────────────────────────

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge({required this.status});

  final ActivityStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ActivityStatus.active => const _StatusChip(
        color: AppColors.accentGreen,
        label: 'Active',
        icon: Icons.check_circle_outline_rounded,
      ),
      ActivityStatus.lowActivity => const _StatusChip(
        color: AppColors.accentOrange,
        label: 'Low Activity',
        icon: Icons.warning_amber_rounded,
      ),
      ActivityStatus.inactive => const _StatusChip(
        color: AppColors.accentRed,
        label: 'Inactive',
        icon: Icons.cancel_outlined,
      ),
      ActivityStatus.noActivity => const _StatusChip(
        color: AppColors.textSubtle,
        label: 'No Activity',
        icon: Icons.remove_circle_outline_rounded,
      ),
    };
  }
}

// ─── Business Status Badge ────────────────────────────────────────────────────

class _BusinessStatusBadge extends StatelessWidget {
  const _BusinessStatusBadge({required this.status});

  final BusinessStatusLevel status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      BusinessStatusLevel.approved => const _StatusChip(
        color: AppColors.accentGreen,
        label: 'Approved',
        icon: Icons.verified_outlined,
      ),
      BusinessStatusLevel.warning => const _StatusChip(
        color: AppColors.accentOrange,
        label: 'Warning',
        icon: Icons.warning_amber_rounded,
      ),
      BusinessStatusLevel.suspended => const _StatusChip(
        color: AppColors.accentRed,
        label: 'Suspended',
        icon: Icons.block_rounded,
      ),
    };
  }
}
