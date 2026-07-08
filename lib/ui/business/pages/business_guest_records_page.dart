import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_service.dart';
import '../../shared/layouts/business_layout.dart';
import '../../shared/widgets/paginator.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../widgets/edit_guest_dialog.dart';
import '../../../api/business_guest_record_api.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _displayCountry(GuestBreakdownEntry b) {
  if (b.isOverseas) return '—';
  return b.country ?? 'Unspecified';
}

String _displayNationality(GuestBreakdownEntry b) {
  if (b.isOverseas) return '—';
  return b.nationality ?? '—';
}

String _displayYesNo(bool value) => value ? 'Yes' : 'No';

Map<String, int> _isOverseasSummary(List<GuestBreakdownEntry> breakdowns) {
  var yes = 0;
  var no  = 0;
  for (final b in breakdowns) {
    if (b.isOverseas) {
      yes += b.count;
    } else {
      no += b.count;
    }
  }
  return {'Yes': yes, 'No': no};
}

Map<String, int> _countrySummary(List<GuestBreakdownEntry> breakdowns) {
  final summary = <String, int>{};
  for (final b in breakdowns) {
    if (b.isOverseas) continue;
    final label = b.country ?? 'Unspecified';
    summary[label] = (summary[label] ?? 0) + b.count;
  }

  final ordered = <String, int>{};
  for (final label in const ['Philippines', 'Others', 'Unspecified']) {
    if (summary.containsKey(label)) ordered[label] = summary[label]!;
  }
  for (final e in summary.entries) {
    ordered.putIfAbsent(e.key, () => e.value);
  }
  return ordered;
}

// ─── Models ───────────────────────────────────────────────────────────────────

enum GuestRecordStatus { active, archived }

class GuestBreakdownEntry {
  const GuestBreakdownEntry({
    this.country,
    this.nationality,
    this.philippinesRegion,
    required this.sex,
    required this.ageGroup,
    required this.count,
    required this.isOverseas,
  });

  final String? country;
  final String? nationality;
  final String? philippinesRegion;
  final String sex;
  final String ageGroup;
  final int count;
  final bool isOverseas;
}

class GuestDemographics {
  const GuestDemographics({
    required this.ageGroups,
    required this.sexDistribution,
    required this.countries,
    required this.breakdowns,
  });

  final Map<String, int> ageGroups;
  final Map<String, int> sexDistribution;
  final Map<String, int> countries;
  final List<GuestBreakdownEntry> breakdowns;
}

class GuestRecord {
  const GuestRecord({
    required this.id,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.guests,
    required this.rooms,
    required this.purpose,
    required this.transport,
    required this.status,
    required this.demographics,
  });

  final String id;
  final String checkIn;
  final String checkOut;
  final String nights;
  final int guests;
  final int rooms;
  final String purpose;
  final String transport;
  final GuestRecordStatus status;
  final GuestDemographics? demographics;
}

// ─── Filter Options ───────────────────────────────────────────────────────────

enum _Filter { active, archived }

// ─── Guest Records Page ───────────────────────────────────────────────────────

class BusinessGuestRecordsPage extends StatefulWidget {
  const BusinessGuestRecordsPage({super.key});

  @override
  State<BusinessGuestRecordsPage> createState() =>
      _BusinessGuestRecordsPageState();
}

class _BusinessGuestRecordsPageState extends State<BusinessGuestRecordsPage> {
  final _api = BusinessGuestRecordApi();

  String? _businessId;
  List<GuestRecord> _records = [];
  bool _isLoading = true;
  String? _loadError;

  // ── Connectivity state ────────────────────────────────────────────────────
  bool _isOffline       = false;
  StreamSubscription<bool>? _connectivitySub;

  _Filter _activeFilter = _Filter.active;
  bool _showFilters = false;
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  DateTime? _checkInFrom;
  DateTime? _checkOutTo;
  String? _selectedPurpose;
  String? _selectedTransport;

  final List<String> _purposeOptions = [
    'All', 'Leisure', 'Business', 'Education', 'Medical', 'Religious', 'Others',
  ];
  final List<String> _transportOptions = [
    'All', 'Private Car', 'Bus', 'Van', 'Motorcycle', 'Tricycle', 'Others',
  ];

  static const List<int> _pageSizeOptions = [10, 20, 30];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService.instance.isOnline;
    _subscribeToConnectivity();
    _init();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeToConnectivity() {
    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted) return;

      if (isOnline && _isOffline) {
        // Just came back online — auto-refresh data immediately
        setState(() {
          _isOffline = false;
        });
        _init(); // Re-run init to attempt online fetch
      } else if (!isOnline && !_isOffline) {
        // Just went offline — show the offline strip.
        setState(() {
          _isOffline = true;
        });
      }
    });
  }

  // ── Init & data loading ───────────────────────────────────────────────────

  Future<void> _init() async {
    final id = await _api.fetchBusinessId();
    if (!mounted) return;

    if (id == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'Business account not found. Please check your connection '
            'and try again.';
      });
      return;
    }

    _businessId = id;
    await _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (_businessId == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final result = await _api.fetchGuestRecords(
      _businessId!,
      page: _currentPage + 1,
      pageSize: _pageSize,
      status: _activeFilter == _Filter.active ? 'active' : 'archived',
      checkInFrom: _checkInFrom?.toIso8601String().split('T').first,
      checkOutTo: _checkOutTo?.toIso8601String().split('T').first,
      purpose: _selectedPurpose,
      transport: _selectedTransport,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      final data = result.data!;
      setState(() {
        _records   = data.data;
        _totalPages = data.pageCount;
        _totalItems = data.totalCount;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _loadError = result.error;
      });
    }
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickDate(BuildContext context, bool isCheckIn) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isCheckIn ? _checkInFrom : _checkOutTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            primary: AppColors.primaryCyan,
            onPrimary: Colors.black,
            primaryContainer: AppColors.primaryCyan.withOpacity(0.25),
            onPrimaryContainer: AppColors.primaryCyan,
            surface: AppColors.cardBackground,
            onSurface: AppColors.textWhite,
            onSurfaceVariant: AppColors.textGray,
            outline: AppColors.cardBorder,
            surfaceVariant: AppColors.inputBackground,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.cardBackground,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryCyan),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isCheckIn) {
        _checkInFrom = picked;
      } else {
        _checkOutTo = picked;
      }
      _currentPage = 0;
    });
    _loadRecords();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onEdit(GuestRecord record) async {
    final updated = await showEditGuestDialog(context, record: record);
    if (updated == null || !mounted) return;

    final result = await _api.updateRecord(
      recordId:           updated.id,
      checkIn:            updated.checkIn,
      checkOut:           updated.checkOut,
      totalGuests:        updated.guests,
      roomsOccupied:      updated.rooms,
      purposeOfVisit:     updated.purpose,
      transportationMode: updated.transport,
      breakdowns:         updated.demographics?.breakdowns ?? [],
    );
    if (!mounted) return;

    if (result.isSuccess) {
      _loadRecords();
    } else {
      _showSnack(result.error ?? 'Failed to update.', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false, Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? AppColors.accentRed
            : (color ?? AppColors.primaryCyan),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearAllFilters() {
    setState(() {
      _checkInFrom      = null;
      _checkOutTo       = null;
      _selectedPurpose  = null;
      _selectedTransport = null;
      _currentPage      = 0;
    });
    _loadRecords();
  }

  void _reload() {
    _currentPage = 0;
    _loadRecords();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BusinessLayout(
      title: 'Guest Records',
      selectedIndex: 2,
      onNavSelected: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Connectivity banners (outside scroll so always visible) ──
              if (_isOffline) const _OfflineBanner(),

              // ── Main scrollable content ────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PageHeader(
                        activeFilter: _activeFilter,
                        onFilterChanged: (f) {
                          setState(() => _activeFilter = f);
                          _reload();
                        },
                        showFilters: _showFilters,
                        onFilterToggle: () =>
                            setState(() => _showFilters = !_showFilters),
                        isNarrow: isNarrow,
                        totalRecords: _totalItems,
                      ),
                      const SizedBox(height: 8),
                      if (_showFilters) ...[
                        _FiltersSection(
                          checkInFrom:       _checkInFrom,
                          checkOutTo:        _checkOutTo,
                          selectedPurpose:   _selectedPurpose,
                          selectedTransport: _selectedTransport,
                          purposeOptions:    _purposeOptions,
                          transportOptions:  _transportOptions,
                          onCheckInFromTap:  () => _pickDate(context, true),
                          onCheckOutToTap:   () => _pickDate(context, false),
                          onPurposeChanged:  (v) {
                            setState(() => _selectedPurpose = v);
                            _reload();
                          },
                          onTransportChanged: (v) {
                            setState(() => _selectedTransport = v);
                            _reload();
                          },
                          onClearAll: _clearAllFilters,
                          isNarrow:   isNarrow,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryCyan,
                            ),
                          ),
                        )
                      else if (_loadError != null)
                        _ErrorBanner(
                          message: _loadError!,
                          onRetry: _businessId == null ? _init : _loadRecords,
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GuestTable(
                              records:  _records,
                              isNarrow: isNarrow,
                              onEdit:   _onEdit,
                            ),
                            const SizedBox(height: 12),
                            Paginator(
                              currentPage:     _currentPage,
                              totalPages:      _totalPages,
                              totalItems:      _totalItems,
                              pageSize:        _pageSize,
                              pageSizeOptions: _pageSizeOptions,
                              onPageSizeChanged: (size) {
                                setState(() {
                                  _pageSize    = size;
                                  _currentPage = 0;
                                });
                                _loadRecords();
                              },
                              onPageChanged: (page) {
                                setState(() => _currentPage = page);
                                _loadRecords();
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Offline Banner ───────────────────────────────────────────────────────────
// Shown as a thin strip at the top when the device is offline.
// Non-dismissible — it disappears automatically when connectivity returns.

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF8A9BB5), size: 14),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'You\'re offline — showing locally saved records.',
              style: TextStyle(color: Color(0xFF8A9BB5), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Back-Online Banner ───────────────────────────────────────────────────────
// Shown once when the device comes back online.
// Gives the user a manual "Refresh" tap rather than forcing an auto-reload.

class _OnlineBanner extends StatelessWidget {
  const _OnlineBanner({required this.onRefresh, required this.onDismiss});

  final VoidCallback onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryCyan.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: AppColors.primaryCyan.withOpacity(0.25)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_rounded, color: AppColors.primaryCyan, size: 14),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Back online! Records may have updated.',
              style: TextStyle(color: AppColors.primaryCyan, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryCyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.primaryCyan.withOpacity(0.4)),
              ),
              child: const Text(
                'Refresh',
                style: TextStyle(
                  color: AppColors.primaryCyan,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.primaryCyan,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error Banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.accentRed,
                fontSize: 13.5,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(color: AppColors.primaryCyan),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filters Section ──────────────────────────────────────────────────────────

class _FiltersSection extends StatelessWidget {
  const _FiltersSection({
    required this.checkInFrom,
    required this.checkOutTo,
    required this.selectedPurpose,
    required this.selectedTransport,
    required this.purposeOptions,
    required this.transportOptions,
    required this.onCheckInFromTap,
    required this.onCheckOutToTap,
    required this.onPurposeChanged,
    required this.onTransportChanged,
    required this.onClearAll,
    required this.isNarrow,
  });

  final DateTime? checkInFrom;
  final DateTime? checkOutTo;
  final String? selectedPurpose;
  final String? selectedTransport;
  final List<String> purposeOptions;
  final List<String> transportOptions;
  final VoidCallback onCheckInFromTap;
  final VoidCallback onCheckOutToTap;
  final ValueChanged<String?> onPurposeChanged;
  final ValueChanged<String?> onTransportChanged;
  final VoidCallback onClearAll;
  final bool isNarrow;

  bool get _hasActiveFilters =>
      checkInFrom != null ||
      checkOutTo != null ||
      (selectedPurpose != null && selectedPurpose != 'All') ||
      (selectedTransport != null && selectedTransport != 'All');

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateFilter(
                  label: 'Check-in From',
                  date: checkInFrom,
                  onTap: onCheckInFromTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DateFilter(
                  label: 'Check-out To',
                  date: checkOutTo,
                  onTap: onCheckOutToTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DropFilter(
                  label: 'Purpose',
                  value: selectedPurpose,
                  items: purposeOptions,
                  onChanged: onPurposeChanged,
                  icon: Icons.work_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DropFilter(
                  label: 'Transportation',
                  value: selectedTransport,
                  items: transportOptions,
                  onChanged: onTransportChanged,
                  icon: Icons.directions_car_outlined,
                ),
              ),
            ],
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 10),
            _ClearAllBtn(onTap: onClearAll),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _DateFilter(
            label: 'Check-in From',
            date: checkInFrom,
            onTap: onCheckInFromTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DateFilter(
            label: 'Check-out To',
            date: checkOutTo,
            onTap: onCheckOutToTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DropFilter(
            label: 'Purpose',
            value: selectedPurpose,
            items: purposeOptions,
            onChanged: onPurposeChanged,
            icon: Icons.work_outline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DropFilter(
            label: 'Transportation',
            value: selectedTransport,
            items: transportOptions,
            onChanged: onTransportChanged,
            icon: Icons.directions_car_outlined,
          ),
        ),
        if (_hasActiveFilters) ...[
          const SizedBox(width: 12),
          _ClearAllBtn(onTap: onClearAll),
        ],
      ],
    );
  }
}

// ─── Filter Widgets ───────────────────────────────────────────────────────────

class _DateFilter extends StatelessWidget {
  const _DateFilter({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  String get _display {
    if (date == null) return 'mm/dd/yyyy';
    return '${date!.month.toString().padLeft(2, '0')}/'
        '${date!.day.toString().padLeft(2, '0')}/${date!.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  color: AppColors.textSubtle,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _display,
                    style: TextStyle(
                      color: date != null
                          ? AppColors.textWhite
                          : AppColors.textSubtle,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DropFilter extends StatelessWidget {
  const _DropFilter({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              isExpanded: true,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.textSubtle, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'All',
                      style: TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              dropdownColor: AppColors.cardBackground,
              iconEnabledColor: AppColors.textGray,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 12.5,
              ),
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(e),
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

class _ClearAllBtn extends StatelessWidget {
  const _ClearAllBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.clear_all, color: AppColors.textGray, size: 15),
            SizedBox(width: 5),
            Text(
              'Clear All',
              style: TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.activeFilter,
    required this.onFilterChanged,
    required this.showFilters,
    required this.onFilterToggle,
    required this.isNarrow,
    required this.totalRecords,
  });

  final _Filter activeFilter;
  final ValueChanged<_Filter> onFilterChanged;
  final bool showFilters;
  final VoidCallback onFilterToggle;
  final bool isNarrow;
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    final filterRow = _FilterToggle(
      activeFilter: activeFilter,
      onChanged: onFilterChanged,
    );
    final toggleBtn = _FilterPanelButton(
      isActive: showFilters,
      onTap: onFilterToggle,
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleSubtitle(totalRecords: totalRecords),
          const SizedBox(height: 12),
          Row(children: [filterRow, const SizedBox(width: 10), toggleBtn]),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _TitleSubtitle(totalRecords: totalRecords),
        const Spacer(),
        filterRow,
        const SizedBox(width: 10),
        toggleBtn,
      ],
    );
  }
}

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({required this.totalRecords});
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guest Records ($totalRecords)',
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'View and manage all guest entries',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

class _FilterPanelButton extends StatelessWidget {
  const _FilterPanelButton({required this.isActive, required this.onTap});
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryCyan.withOpacity(0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.primaryCyan : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              color: isActive ? AppColors.primaryCyan : AppColors.textGray,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Filters',
              style: TextStyle(
                color: isActive ? AppColors.primaryCyan : AppColors.textGray,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Toggle (Active / Archived) ───────────────────────────────────────

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.activeFilter, required this.onChanged});

  final _Filter activeFilter;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterTab(
            label: 'Active',
            isActive: activeFilter == _Filter.active,
            onTap: () => onChanged(_Filter.active),
          ),
          _FilterTab(
            label: 'Archived',
            isActive: activeFilter == _Filter.archived,
            onTap: () => onChanged(_Filter.archived),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textGray,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Guest Table ──────────────────────────────────────────────────────────────

class _GuestTable extends StatelessWidget {
  const _GuestTable({
    required this.records,
    required this.isNarrow,
    required this.onEdit,
  });

  final List<GuestRecord> records;
  final bool isNarrow;
  final ValueChanged<GuestRecord> onEdit;

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
          if (!isNarrow) ...[
            _TableHeader(),
            const Divider(color: AppColors.cardBorder, height: 1),
          ],
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No records found.',
                  style: TextStyle(color: AppColors.textGray),
                ),
              ),
            )
          else
            ...records.map((r) {
              final isLast = r == records.last;
              return Column(
                children: [
                  if (isNarrow)
                    _RecordCard(record: r, onEdit: onEdit)
                  else
                    _RecordRow(record: r, onEdit: onEdit),
                  if (!isLast)
                    const Divider(color: AppColors.cardBorder, height: 1),
                ],
              );
            }),
        ],
      ),
    );
  }
}

// ─── Table Header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Check-in')),
          Expanded(flex: 3, child: _HeaderCell('Check-out')),
          Expanded(flex: 2, child: _HeaderCell('Nights')),
          Expanded(flex: 1, child: _HeaderCell('Guests')),
          Expanded(flex: 1, child: _HeaderCell('Rooms')),
          Expanded(flex: 2, child: _HeaderCell('Purpose')),
          Expanded(flex: 2, child: _HeaderCell('Transport')),
          Expanded(flex: 2, child: _HeaderCell('Status')),
          Expanded(flex: 3, child: _HeaderCell('Actions')),
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

// ─── Table Row (wide) ─────────────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.onEdit});

  final GuestRecord record;
  final ValueChanged<GuestRecord> onEdit;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              r.checkIn,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              r.checkOut,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              r.nights,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${r.guests}',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${r.rooms}',
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              r.purpose,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              r.transport,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 0),
                child: _StatusBadge(status: r.status),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _ActionButtons(
              status: r.status,
              onEdit: () => onEdit(r),
              onView: () => _showRecordModal(context, r),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Record Card (narrow) ─────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onEdit});

  final GuestRecord record;
  final ValueChanged<GuestRecord> onEdit;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.checkIn,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.checkOut}  •  ${r.nights}',
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: r.status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _InfoChip(label: 'Guests', value: '${r.guests}'),
              _InfoChip(label: 'Rooms', value: '${r.rooms}'),
              _InfoChip(label: 'Purpose', value: r.purpose),
              _InfoChip(label: 'Transport', value: r.transport),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ActionIconButton(
                icon: Icons.visibility_outlined,
                label: 'View',
                color: AppColors.accentGreen,
                showBorder: true,
                onTap: () => _showRecordModal(context, r),
              ),
              if (r.status == GuestRecordStatus.active) ...[
                const SizedBox(width: 8),
                ActionIconButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: AppColors.primaryCyan,
                  showBorder: true,
                  onTap: () => onEdit(r),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppColors.textSubtle),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final GuestRecordStatus status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == GuestRecordStatus.active;
    final color = isActive ? AppColors.accentGreen : AppColors.textGray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        isActive ? 'active' : 'archived',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.status,
    required this.onEdit,
    required this.onView,
  });

  final GuestRecordStatus status;
  final VoidCallback onEdit;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ActionIconButton(
          icon: Icons.visibility_outlined,
          label: 'View',
          color: AppColors.accentGreen,
          showBorder: true,
          onTap: onView,
        ),
        if (status == GuestRecordStatus.active)
          ActionIconButton(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: AppColors.primaryCyan,
            showBorder: true,
            onTap: onEdit,
          ),
      ],
    );
  }
}

// ─── Full Record Modal ────────────────────────────────────────────────────────

void _showRecordModal(BuildContext context, GuestRecord record) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => _RecordDetailModal(record: record),
  );
}

class _RecordDetailModal extends StatelessWidget {
  const _RecordDetailModal({required this.record});
  final GuestRecord record;

  @override
  Widget build(BuildContext context) {
    final demo     = record.demographics;
    final isNarrow = MediaQuery.of(context).size.width < 560;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 40,
        vertical: 32,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.primaryCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Guest Record Details',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textGray,
                      size: 20,
                    ),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ModalSectionLabel('Stay Information'),
                    const SizedBox(height: 10),
                    _StayInfoGrid(record: record),
                    const SizedBox(height: 20),

                    const Divider(color: AppColors.cardBorder, height: 1),
                    const SizedBox(height: 20),

                    const _ModalSectionLabel('Guest Breakdown by Segment'),
                    const SizedBox(height: 10),
                    if (demo == null || demo.breakdowns.isEmpty)
                      const Text(
                        'No demographic data available.',
                        style: TextStyle(
                          color: AppColors.textSubtle,
                          fontSize: 13,
                        ),
                      )
                    else ...[
                      _BreakdownTable(breakdowns: demo.breakdowns),
                      const SizedBox(height: 20),
                      const _ModalSectionLabel('Is Overseas'),
                      const SizedBox(height: 10),
                      _StatGrid(entries: _isOverseasSummary(demo.breakdowns)),
                      const SizedBox(height: 20),
                      const _ModalSectionLabel('Age Groups'),
                      const SizedBox(height: 10),
                      _StatGrid(entries: demo.ageGroups),
                      const SizedBox(height: 20),
                      const _ModalSectionLabel('Sex Distribution'),
                      const SizedBox(height: 10),
                      _StatGrid(entries: demo.sexDistribution),
                      const SizedBox(height: 20),
                      const _ModalSectionLabel('Country / Region'),
                      const SizedBox(height: 10),
                      _StatGrid(entries: _countrySummary(demo.breakdowns)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stay Info Grid ───────────────────────────────────────────────────────────

class _StayInfoGrid extends StatelessWidget {
  const _StayInfoGrid({required this.record});
  final GuestRecord record;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Check-in', record.checkIn),
      ('Check-out', record.checkOut),
      ('Length of Stay', record.nights),
      ('Total Guests', '${record.guests}'),
      ('Rooms Occupied', '${record.rooms}'),
      ('Purpose of Visit', record.purpose),
      ('Mode of Transport', record.transport),
    ];

    const spacing = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((item) {
            return SizedBox(
              width: itemWidth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.$2,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ─── Modal Helpers ────────────────────────────────────────────────────────────

class _ModalSectionLabel extends StatelessWidget {
  const _ModalSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textWhite,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}

// ─── Breakdown Table ──────────────────────────────────────────────────────────

class _BreakdownTable extends StatelessWidget {
  const _BreakdownTable({required this.breakdowns});
  final List<GuestBreakdownEntry> breakdowns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: breakdowns.map((b) {
              final isOverseas  = b.isOverseas;
              final yesNoLabel  = _displayYesNo(isOverseas);
              final yesNoColor  = isOverseas
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF10B981);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayCountry(b),
                            style: const TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: yesNoColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: yesNoColor.withOpacity(0.35),
                            ),
                          ),
                          child: Text(
                            yesNoLabel,
                            style: TextStyle(
                              color: yesNoColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _BreakdownInfoChip(label: 'Is Overseas', value: yesNoLabel),
                        _BreakdownInfoChip(
                          label: 'Nationality',
                          value: _displayNationality(b),
                        ),
                        _BreakdownInfoChip(
                          label: 'Region',
                          value: b.philippinesRegion ?? '—',
                        ),
                        _BreakdownInfoChip(label: 'Sex', value: b.sex),
                        _BreakdownInfoChip(label: 'Age', value: b.ageGroup),
                        _BreakdownInfoChip(label: 'Count', value: '${b.count}'),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        }

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Table(
              border: TableBorder.symmetric(
                inside: BorderSide(color: AppColors.cardBorder, width: 0.5),
              ),
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(1),
                5: FlexColumnWidth(1),
                6: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.inputBackground),
                  children: const [
                    _TCell('Country',     isHeader: true),
                    _TCell('Nationality', isHeader: true),
                    _TCell('Region',      isHeader: true),
                    _TCell('Is Overseas', isHeader: true),
                    _TCell('Sex',         isHeader: true),
                    _TCell('Age Group',   isHeader: true),
                    _TCell('Count',       isHeader: true),
                  ],
                ),
                ...breakdowns.map(
                  (b) => TableRow(
                    children: [
                      _TCell(_displayCountry(b)),
                      _TCell(_displayNationality(b)),
                      _TCell(b.philippinesRegion ?? '—'),
                      _TCellBadge(
                        label: _displayYesNo(b.isOverseas),
                        color: b.isOverseas
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF10B981),
                      ),
                      _TCell(b.sex),
                      _TCell(b.ageGroup),
                      _TCell('${b.count}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BreakdownInfoChip extends StatelessWidget {
  const _BreakdownInfoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TCell extends StatelessWidget {
  const _TCell(this.text, {this.isHeader = false});
  final String text;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        text,
        style: TextStyle(
          color: isHeader ? AppColors.textGray : AppColors.textWhite,
          fontSize: 11.5,
          fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _TCellBadge extends StatelessWidget {
  const _TCellBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.entries});
  final Map<String, int> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text(
        '—',
        style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.entries.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.inputBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: e.key,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                  ),
                ),
                const TextSpan(text: '  ', style: TextStyle(fontSize: 12)),
                TextSpan(
                  text: '${e.value}',
                  style: const TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}