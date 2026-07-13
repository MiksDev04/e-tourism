import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/country_constants.dart';
import '../../../core/services/offline_service.dart';
import '../../shared/layouts/business_layout.dart';
import '../../../api/business_guest_entry_api.dart';

// ─── Light input colours ──────────────────────────────────────────────────────

const _kInputFill = Color(0xFFF8FAFC);
const _kInputBorder = Color(0xFFD1D5DB);
const _kInputFocused = Color(0xFF3B82F6);
const _kDropBg = Color(0xFFFFFFFF);
const _kInputText = Color(0xFF111827);
const _kInputHint = Color(0xFF9CA3AF);
const _kReadOnlyFill = Color(0xFFEFF2F5);

/// Single source-of-truth height for every input, dropdown, and read-only field.
const _kFieldHeight = 40.0;

// ─── Models ───────────────────────────────────────────────────────────────────

class AgeGroupRow {
  AgeGroupRow({required this.ageGroup, this.male = 0, this.female = 0});

  final String ageGroup;
  int male;
  int female;

  int get total => male + female;
}

class GuestGroup {
  GuestGroup()
    : country = null,
      nationality = null,
      region = null,
      isOverseas = false,
      ageRows = [];

  String? country;
  String? nationality;
  String? region;
  bool isOverseas;
  final List<AgeGroupRow> ageRows;

  int get groupTotal => ageRows.fold(0, (sum, r) => sum + r.male + r.female);
}

// ─── Options ──────────────────────────────────────────────────────────────────

const _purposeOptions = [
  'Leisure',
  'Business',
  'Education',
  'Medical',
  'Religious',
  'Others',
];

const _transportOptions = [
  'Private Car',
  'Bus',
  'Van',
  'Motorcycle',
  'Tricycle',
  'Others',
];

const _countryOptions = [
  'Philippines',
  'Argentina',
  'Australia',
  'Austria',
  'Bahrain',
  'Bangladesh',
  'Belgium',
  'Brazil',
  'Brunei',
  'Cambodia',
  'Canada',
  'China',
  'Colombia',
  'CIS',
  'Denmark',
  'Egypt',
  'Finland',
  'France',
  'Germany',
  'Greece',
  'Guam',
  'Hong Kong',
  'India',
  'Indonesia',
  'Iran',
  'Ireland',
  'Israel',
  'Italy',
  'Japan',
  'Jordan',
  'Korea',
  'Kuwait',
  'Laos',
  'Luxembourg',
  'Malaysia',
  'Mexico',
  'Myanmar',
  'Nauru',
  'Nepal',
  'Netherlands',
  'New Zealand',
  'Nigeria',
  'Norway',
  'Pakistan',
  'Papua NG',
  'Peru',
  'Poland',
  'Portugal',
  'Russia',
  'Saudi Arabia',
  'Singapore',
  'South Africa',
  'Spain',
  'Sri Lanka',
  'Sweden',
  'Switzerland',
  'Taiwan',
  'Thailand',
  'Serbia & Montenegro',
  'UAE',
  'United Kingdom',
  'USA',
  'Venezuela',
  'Vietnam',
  'Others',
];

const _regionOptions = [
  'NCR',
  'CAR',
  'Region I',
  'Region II',
  'Region III',
  'Region IV-A (CALABARZON)',
  'Region IV-B (MIMAROPA)',
  'Region V',
  'Region VI',
  'Region VII',
  'Region VIII',
  'Region IX',
  'Region X',
  'Region XI',
  'Region XII',
  'Region XIII',
  'BARMM',
];

const _ageGroupOptions = [
  '0–9',
  '10–17',
  '18–25',
  '26–35',
  '36–45',
  '46–55',
  '56+',
  'Prefer not to say',
];

const _nationalityOptions = ['Filipino', 'Foreign'];

// ─── Guest Entry Page ─────────────────────────────────────────────────────────

class BusinessGuestEntryPage extends StatefulWidget {
  const BusinessGuestEntryPage({super.key});

  @override
  State<BusinessGuestEntryPage> createState() => _BusinessGuestEntryPageState();
}

class _BusinessGuestEntryPageState extends State<BusinessGuestEntryPage> {
  final _api = BusinessGuestEntryApi();
  String? _businessId;

  DateTime? _checkIn;
  DateTime? _checkOut;
  final _totalGuestsCtrl = TextEditingController();
  final _roomsOccupiedCtrl = TextEditingController();
  String? _purpose;
  String? _transport;
  final _purposeOtherCtrl = TextEditingController();
  final _transportOtherCtrl = TextEditingController();
  bool _showPurposeOther = false;
  bool _showTransportOther = false;
  bool _isSaving = false;

  Map<String, String?> _errors = {};
  List<Map<String, String?>> _groupErrors = [];

  final List<GuestGroup> _groups = [GuestGroup()];

  // Temp controllers for the progressive age-add control per group.
  String? _pendingAgeGroup;
  final _pendingMaleCtrl = TextEditingController(text: '');
  final _pendingFemaleCtrl = TextEditingController(text: '');
  String? _ageAddError;

  // ── Connectivity state ────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _groupErrors = [{}];
    _isOffline = !ConnectivityService.instance.isOnline;
    _subscribeToConnectivity();
    _loadBusinessId();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _totalGuestsCtrl.dispose();
    _roomsOccupiedCtrl.dispose();
    _purposeOtherCtrl.dispose();
    _transportOtherCtrl.dispose();
    _pendingMaleCtrl.dispose();
    _pendingFemaleCtrl.dispose();
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeToConnectivity() {
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged.listen(
      (isOnline) {
        if (!mounted) return;

        if (isOnline && _isOffline) {
          // Just came back online — auto-refresh
          setState(() {
            _isOffline = false;
          });
          _loadBusinessId();
          SyncService.instance.sync();
        } else if (!isOnline && !_isOffline) {
          // Just went offline — show the offline strip.
          setState(() {
            _isOffline = true;
          });
        }
      },
    );
  }

  // ── Business ID loading ───────────────────────────────────────────────────

  Future<void> _loadBusinessId() async {
    final id = await _api.fetchBusinessId();
    if (mounted) setState(() => _businessId = id);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get _nightsCount {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays.clamp(0, 999);
  }

  int get _demographicTotal =>
      _groups.fold(0, (sum, g) => sum + g.groupTotal);

  int get _totalGuests => int.tryParse(_totalGuestsCtrl.text) ?? 0;

  void _addGroup() => setState(() {
        _groups.add(GuestGroup());
        _groupErrors.add({});
      });

  void _removeGroup(int index) {
    if (_groups.length <= 1) return;
    setState(() {
      _groups.removeAt(index);
      _groupErrors.removeAt(index);
    });
  }

  void _clearFieldError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = Map.from(_errors)..remove(key));
    }
  }

  void _clearGroupError(int index, String key) {
    if (_groupErrors.length > index && _groupErrors[index].containsKey(key)) {
      setState(() {
        _groupErrors = List.from(_groupErrors);
        _groupErrors[index] = Map.from(_groupErrors[index])..remove(key);
      });
    }
  }

  void _showSnackBar(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? AppColors.primaryCyan,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _checkIn = null;
      _checkOut = null;
      _totalGuestsCtrl.clear();
      _roomsOccupiedCtrl.clear();
      _purpose = null;
      _transport = null;
      _purposeOtherCtrl.clear();
      _transportOtherCtrl.clear();
      _showPurposeOther = false;
      _showTransportOther = false;
      _errors = {};
      _pendingAgeGroup = null;
      _pendingMaleCtrl.clear();
      _pendingFemaleCtrl.clear();
      _ageAddError = null;
      _groups
        ..clear()
        ..add(GuestGroup());
      _groupErrors = [{}];
    });
  }

  bool _validateAndSetErrors() {
    final errors = <String, String?>{};
    final groupErrs =
        List.generate(_groups.length, (_) => <String, String?>{});
    bool hasError = false;

    if (_checkIn == null) {
      errors['checkIn'] = 'Please select a check-in date.';
      hasError = true;
    } else if (_checkIn!.isAfter(DateTime.now())) {
      errors['checkIn'] = 'Check-in date cannot be in the future.';
      hasError = true;
    }

    if (_checkOut == null) {
      errors['checkOut'] = 'Please select a check-out date.';
      hasError = true;
    } else if (_checkIn != null && _checkOut!.isBefore(_checkIn!)) {
      errors['checkOut'] =
          'Check-out must be the same day as check-in or later.';
      hasError = true;
    }

    final guests = int.tryParse(_totalGuestsCtrl.text);
    if (guests == null || guests <= 0) {
      errors['totalGuests'] = 'Enter at least 1 guest.';
      hasError = true;
    } else if (guests > 9999) {
      errors['totalGuests'] = 'Value seems too large.';
      hasError = true;
    }

    final rooms = int.tryParse(_roomsOccupiedCtrl.text);
    if (rooms == null || rooms < 0) {
      errors['roomsOccupied'] = 'Enter a valid number of rooms.';
      hasError = true;
    } else if (guests != null && guests > 0 && rooms > guests) {
      errors['roomsOccupied'] = 'Rooms cannot exceed total guests.';
      hasError = true;
    } else if (_nightsCount > 0 && rooms == 0) {
      errors['roomsOccupied'] =
          'At least 1 room is required when staying overnight.';
      hasError = true;
    }

    if (_purpose == null) {
      errors['purpose'] = 'Please select a purpose of visit.';
      hasError = true;
    } else if (_purpose == 'Others' && _purposeOtherCtrl.text.trim().isEmpty) {
      errors['purposeOther'] = 'Please specify the purpose.';
      hasError = true;
    }

    if (_transport == null) {
      errors['transport'] = 'Please select a mode of transportation.';
      hasError = true;
    } else if (_transport == 'Others' &&
        _transportOtherCtrl.text.trim().isEmpty) {
      errors['transportOther'] = 'Please specify the transportation.';
      hasError = true;
    }

    // ── Group-level validation ─────────────────────────────────────────────
    final seenOriginKeys = <String>{};
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      final gerr = <String, String?>{};

      if (!g.isOverseas) {
        if (g.country == null) {
          gerr['country'] = 'Please select a country.';
          hasError = true;
        } else if (g.country == 'Philippines' && g.nationality == null) {
          gerr['nationality'] = 'Please select nationality.';
          hasError = true;
        }
      }

      if (g.groupTotal <= 0 && gerr.isEmpty) {
        gerr['ageRows'] =
            'Add at least one age group with headcount, or remove this group.';
        hasError = true;
      }

      // Duplicate origin check (only when origin fields are valid)
      if (gerr.isEmpty) {
        final key = g.isOverseas
            ? 'overseas'
            : '${g.country}|${g.country == 'Philippines' ? g.nationality : ''}|${g.country == 'Philippines' ? (g.region ?? '') : ''}';
        if (!seenOriginKeys.add(key)) {
          gerr['duplicate'] = 'Duplicate origin — merge into one group.';
          hasError = true;
        }
      }

      groupErrs[i] = gerr;
    }

    if (!hasError && guests != null && guests > 0) {
      if (_demographicTotal != guests) {
        errors['demographicSum'] =
            'Demographic total ($_demographicTotal) must equal total guests ($guests).';
        hasError = true;
      }
    }

    setState(() {
      _errors = errors;
      _groupErrors = groupErrs;
    });

    return !hasError;
  }

  Future<void> _save() async {
    final isValid = _validateAndSetErrors();
    if (!isValid) return;

    if (_businessId == null) {
      setState(
        () => _errors = {
          'businessId': 'Business account not found. Please try again.',
        },
      );
      return;
    }

    setState(() => _isSaving = true);

    final purposeValue = _purpose == 'Others'
        ? _purposeOtherCtrl.text.trim()
        : _purpose!;
    final transportValue = _transport == 'Others'
        ? _transportOtherCtrl.text.trim()
        : _transport!;

    final breakdowns = <GuestBreakdownData>[];
    for (final g in _groups) {
      for (final row in g.ageRows) {
        if (row.male > 0) {
          breakdowns.add(GuestBreakdownData(
            country: g.isOverseas ? null : mapToReportFormat(g.country!),
            nationality: (g.isOverseas || g.country != 'Philippines')
                ? null
                : g.nationality,
            philippinesRegion:
                (!g.isOverseas && g.country == 'Philippines') ? g.region : null,
            sex: 'Male',
            ageGroup: row.ageGroup,
            count: row.male,
            isOverseas: g.isOverseas,
          ));
        }
        if (row.female > 0) {
          breakdowns.add(GuestBreakdownData(
            country: g.isOverseas ? null : mapToReportFormat(g.country!),
            nationality: (g.isOverseas || g.country != 'Philippines')
                ? null
                : g.nationality,
            philippinesRegion:
                (!g.isOverseas && g.country == 'Philippines') ? g.region : null,
            sex: 'Female',
            ageGroup: row.ageGroup,
            count: row.female,
            isOverseas: g.isOverseas,
          ));
        }
      }
    }

    final result = await _api.saveGuestEntry(
      GuestEntryData(
        businessId: _businessId!,
        checkIn: _checkIn!,
        checkOut: _checkOut!,
        totalGuests: _totalGuests,
        roomsOccupied: int.parse(_roomsOccupiedCtrl.text),
        purposeOfVisit: purposeValue,
        transportationMode: transportValue,
        breakdowns: breakdowns,
      ),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      _clearForm();
      if (result.syncedToCloud) {
        _showSnackBar('Guest entry saved successfully!');
      } else {
        // Either offline, or online but Cloud API failed — record is safe locally.
        _showSnackBar(
          ConnectivityService.instance.isOnline
              ? 'Entry saved — will sync in the background.'
              : 'Entry saved offline — will sync when you\'re back online.',
          color: const Color(0xFFF59E0B), // amber = "pending"
        );
      }
    }
  }

  Future<void> _pickDate(BuildContext context, bool isCheckIn) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = isCheckIn
        ? DateTime(2020)
        : (_checkIn != null ? _checkIn! : today);
    final lastDate = isCheckIn ? today : today.add(const Duration(days: 730));
    final initialDate = isCheckIn
        ? today
        : (_checkIn != null ? _checkIn! : today);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF3B82F6),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF111827),
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (_checkOut != null && _checkOut!.isBefore(picked)) _checkOut = null;
        _clearFieldError('checkIn');
      } else {
        _checkOut = picked;
        _clearFieldError('checkOut');
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return BusinessLayout(
      title: 'Guest Entry',
      selectedIndex: 1,
      onNavSelected: (_) {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Connectivity banners (outside scroll so always visible) ──────
          if (_isOffline) const _OfflineBanner(),

          // ── Main scrollable content ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  : const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _PageHeader(),
                  const SizedBox(height: 20),

                  if (_errors['submit'] != null) ...[
                    _GlobalErrorBanner(message: _errors['submit']!),
                    const SizedBox(height: 12),
                  ],
                  if (_errors['businessId'] != null) ...[
                    _GlobalErrorBanner(message: _errors['businessId']!),
                    const SizedBox(height: 12),
                  ],

                  _StayInfoCard(
                    checkIn: _checkIn,
                    checkOut: _checkOut,
                    nights: _nightsCount,
                    totalGuestsCtrl: _totalGuestsCtrl,
                    roomsOccupiedCtrl: _roomsOccupiedCtrl,
                    purpose: _purpose,
                    transport: _transport,
                    showPurposeOther: _showPurposeOther,
                    showTransportOther: _showTransportOther,
                    purposeOtherCtrl: _purposeOtherCtrl,
                    transportOtherCtrl: _transportOtherCtrl,
                    errors: _errors,
                    onPickCheckIn: () => _pickDate(context, true),
                    onPickCheckOut: () => _pickDate(context, false),
                    onPurposeChanged: (v) {
                      setState(() {
                        _purpose = v;
                        _showPurposeOther = v == 'Others';
                        if (!_showPurposeOther) _purposeOtherCtrl.clear();
                      });
                      _clearFieldError('purpose');
                      _clearFieldError('purposeOther');
                    },
                    onTransportChanged: (v) {
                      setState(() {
                        _transport = v;
                        _showTransportOther = v == 'Others';
                        if (!_showTransportOther) _transportOtherCtrl.clear();
                      });
                      _clearFieldError('transport');
                      _clearFieldError('transportOther');
                    },
                    onGuestsChanged: (_) {
                      setState(() {});
                      _clearFieldError('totalGuests');
                      _clearFieldError('demographicSum');
                    },
                    onRoomsChanged: (_) => _clearFieldError('roomsOccupied'),
                    onPurposeOtherChanged: (_) =>
                        _clearFieldError('purposeOther'),
                    onTransportOtherChanged: (_) =>
                        _clearFieldError('transportOther'),
                  ),
                  const SizedBox(height: 16),

                  _DemographicCard(
                    groups: _groups,
                    total: _totalGuests,
                    currentSum: _demographicTotal,
                    errors: _errors,
                    groupErrors: _groupErrors,
                    pendingAgeGroup: _pendingAgeGroup,
                    pendingMaleCtrl: _pendingMaleCtrl,
                    pendingFemaleCtrl: _pendingFemaleCtrl,
                    ageAddError: _ageAddError,
                    onAddGroup: _addGroup,
                    onRemoveGroup: _removeGroup,
                    onGroupChanged: (int groupIndex, String fieldKey) {
                      setState(() {});
                      _clearGroupError(groupIndex, fieldKey);
                      _clearFieldError('demographicSum');
                    },
                    onAgeGroupChanged: (String? v) {
                      setState(() {
                        _pendingAgeGroup = v;
                        _ageAddError = null;
                      });
                    },
                    onAddAgeRow: (int groupIndex) {
                      final g = _groups[groupIndex];
                      final male =
                          int.tryParse(_pendingMaleCtrl.text) ?? 0;
                      final female =
                          int.tryParse(_pendingFemaleCtrl.text) ?? 0;
                      if (_pendingAgeGroup == null) {
                        setState(() => _ageAddError = 'Select an age group first.');
                        return;
                      }
                      if (male <= 0 && female <= 0) {
                        setState(() => _ageAddError = 'Enter at least 1 guest for this age group.');
                        return;
                      }
                      setState(() {
                        g.ageRows.add(AgeGroupRow(
                          ageGroup: _pendingAgeGroup!,
                          male: male,
                          female: female,
                        ));
                        _pendingAgeGroup = null;
                        _pendingMaleCtrl.clear();
                        _pendingFemaleCtrl.clear();
                        _ageAddError = null;
                      });
                      _clearFieldError('demographicSum');
                    },
                    onAgeAddFieldChanged: () {
                      if (_ageAddError != null) setState(() => _ageAddError = null);
                    },
                    onRemoveAgeRow: (int groupIndex, int ageRowIndex) {
                      setState(() {
                        _groups[groupIndex].ageRows.removeAt(ageRowIndex);
                      });
                      _clearFieldError('demographicSum');
                    },
                    onAgeCountChanged: (int groupIndex, int ageRowIndex, String sex, int value) {
                      final row = _groups[groupIndex].ageRows[ageRowIndex];
                      if (sex == 'male') {
                        row.male = value;
                      } else {
                        row.female = value;
                      }
                      setState(() {});
                      _clearFieldError('demographicSum');
                    },
                  ),
                  const SizedBox(height: 20),

                  _FormActions(
                    isSaving: _isSaving,
                    onClear: () {
                      _clearForm();
                      _showSnackBar('Form cleared.');
                    },
                    onSave: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Offline Banner ───────────────────────────────────────────────────────────
// Shown as a thin strip at the top when the device is offline.
// Non-dismissible — disappears automatically when connectivity returns.

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A2E),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFF8A9BB5), size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\'re offline — entries will be saved locally and synced later.',
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
// Gives the user a manual "Refresh" tap to re-resolve the business ID
// rather than forcing an auto-reload mid-form.

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
          const Icon(
            Icons.wifi_rounded,
            color: AppColors.primaryCyan,
            size: 14,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Back online! Tap Refresh to reconnect your account.',
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
                  color: AppColors.primaryCyan.withOpacity(0.4),
                ),
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

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'New Guest Entry',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Record tourist demographic data',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Global Error Banner ──────────────────────────────────────────────────────

class _GlobalErrorBanner extends StatelessWidget {
  const _GlobalErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.accentRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stay Info Card ───────────────────────────────────────────────────────────

class _StayInfoCard extends StatelessWidget {
  const _StayInfoCard({
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.totalGuestsCtrl,
    required this.roomsOccupiedCtrl,
    required this.purpose,
    required this.transport,
    required this.showPurposeOther,
    required this.showTransportOther,
    required this.purposeOtherCtrl,
    required this.transportOtherCtrl,
    required this.errors,
    required this.onPickCheckIn,
    required this.onPickCheckOut,
    required this.onPurposeChanged,
    required this.onTransportChanged,
    required this.onGuestsChanged,
    required this.onRoomsChanged,
    required this.onPurposeOtherChanged,
    required this.onTransportOtherChanged,
  });

  final DateTime? checkIn;
  final DateTime? checkOut;
  final int nights;
  final TextEditingController totalGuestsCtrl;
  final TextEditingController roomsOccupiedCtrl;
  final String? purpose;
  final String? transport;
  final bool showPurposeOther;
  final bool showTransportOther;
  final TextEditingController purposeOtherCtrl;
  final TextEditingController transportOtherCtrl;
  final Map<String, String?> errors;
  final VoidCallback onPickCheckIn;
  final VoidCallback onPickCheckOut;
  final ValueChanged<String?> onPurposeChanged;
  final ValueChanged<String?> onTransportChanged;
  final ValueChanged<String> onGuestsChanged;
  final ValueChanged<String> onRoomsChanged;
  final ValueChanged<String> onPurposeOtherChanged;
  final ValueChanged<String> onTransportOtherChanged;

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final nightsLabel = '$nights night${nights == 1 ? '' : 's'}';

    return _SectionCard(
      title: 'Stay Information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: 'Check-in Date *',
                    errorText: errors['checkIn'],
                    child: _EntryDateField(
                      value: _fmt(checkIn),
                      hasError: errors['checkIn'] != null,
                      onTap: onPickCheckIn,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Check-out Date *',
                    errorText: errors['checkOut'],
                    child: _EntryDateField(
                      value: _fmt(checkOut),
                      hasError: errors['checkOut'] != null,
                      onTap: onPickCheckOut,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FieldCol(
              label: 'Length of Stay',
              child: _EntryReadOnlyField(value: nightsLabel),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: 'Check-in Date *',
                    errorText: errors['checkIn'],
                    child: _EntryDateField(
                      value: _fmt(checkIn),
                      hasError: errors['checkIn'] != null,
                      onTap: onPickCheckIn,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Check-out Date *',
                    errorText: errors['checkOut'],
                    child: _EntryDateField(
                      value: _fmt(checkOut),
                      hasError: errors['checkOut'] != null,
                      onTap: onPickCheckOut,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Length of Stay',
                    child: _EntryReadOnlyField(value: nightsLabel),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FieldCol(
                  label: 'Total Guests *',
                  errorText: errors['totalGuests'],
                  child: _EntryNumberField(
                    controller: totalGuestsCtrl,
                    hint: 'e.g. 10',
                    hasError: errors['totalGuests'] != null,
                    onChanged: onGuestsChanged,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FieldCol(
                  label: 'Rooms Occupied *',
                  errorText: errors['roomsOccupied'],
                  child: _EntryNumberField(
                    controller: roomsOccupiedCtrl,
                    hint: 'e.g. 3',
                    hasError: errors['roomsOccupied'] != null,
                    onChanged: onRoomsChanged,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (isMobile) ...[
            _FieldCol(
              label: 'Purpose of Visit *',
              errorText: errors['purpose'],
              child: _EntryDropdownField(
                value: purpose,
                items: _purposeOptions,
                hint: 'Select purpose',
                hasError: errors['purpose'] != null,
                onChanged: onPurposeChanged,
              ),
            ),
            if (showPurposeOther) ...[
              const SizedBox(height: 10),
              _FieldCol(
                label: 'Please specify *',
                errorText: errors['purposeOther'],
                child: _EntryTextField(
                  controller: purposeOtherCtrl,
                  hint: 'Specify purpose',
                  hasError: errors['purposeOther'] != null,
                  onChanged: onPurposeOtherChanged,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _FieldCol(
              label: 'Mode of Transportation *',
              errorText: errors['transport'],
              child: _EntryDropdownField(
                value: transport,
                items: _transportOptions,
                hint: 'Select transportation',
                hasError: errors['transport'] != null,
                onChanged: onTransportChanged,
              ),
            ),
            if (showTransportOther) ...[
              const SizedBox(height: 10),
              _FieldCol(
                label: 'Please specify *',
                errorText: errors['transportOther'],
                child: _EntryTextField(
                  controller: transportOtherCtrl,
                  hint: 'Specify transportation',
                  hasError: errors['transportOther'] != null,
                  onChanged: onTransportOtherChanged,
                ),
              ),
            ],
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldCol(
                        label: 'Purpose of Visit *',
                        errorText: errors['purpose'],
                        child: _EntryDropdownField(
                          value: purpose,
                          items: _purposeOptions,
                          hint: 'Select purpose',
                          hasError: errors['purpose'] != null,
                          onChanged: onPurposeChanged,
                        ),
                      ),
                      if (showPurposeOther) ...[
                        const SizedBox(height: 10),
                        _FieldCol(
                          label: 'Please specify *',
                          errorText: errors['purposeOther'],
                          child: _EntryTextField(
                            controller: purposeOtherCtrl,
                            hint: 'Specify purpose',
                            hasError: errors['purposeOther'] != null,
                            onChanged: onPurposeOtherChanged,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldCol(
                        label: 'Mode of Transportation *',
                        errorText: errors['transport'],
                        child: _EntryDropdownField(
                          value: transport,
                          items: _transportOptions,
                          hint: 'Select transportation',
                          hasError: errors['transport'] != null,
                          onChanged: onTransportChanged,
                        ),
                      ),
                      if (showTransportOther) ...[
                        const SizedBox(height: 10),
                        _FieldCol(
                          label: 'Please specify *',
                          errorText: errors['transportOther'],
                          child: _EntryTextField(
                            controller: transportOtherCtrl,
                            hint: 'Specify transportation',
                            hasError: errors['transportOther'] != null,
                            onChanged: onTransportOtherChanged,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Demographic Card ─────────────────────────────────────────────────────────

class _DemographicCard extends StatelessWidget {
  const _DemographicCard({
    required this.groups,
    required this.total,
    required this.currentSum,
    required this.errors,
    required this.groupErrors,
    required this.pendingAgeGroup,
    required this.pendingMaleCtrl,
    required this.pendingFemaleCtrl,
    required this.ageAddError,
    required this.onAddGroup,
    required this.onRemoveGroup,
    required this.onGroupChanged,
    required this.onAgeGroupChanged,
    required this.onAddAgeRow,
    required this.onRemoveAgeRow,
    required this.onAgeAddFieldChanged,
    required this.onAgeCountChanged,
  });

  final List<GuestGroup> groups;
  final int total;
  final int currentSum;
  final Map<String, String?> errors;
  final List<Map<String, String?>> groupErrors;
  final String? pendingAgeGroup;
  final TextEditingController pendingMaleCtrl;
  final TextEditingController pendingFemaleCtrl;
  final String? ageAddError;
  final VoidCallback onAddGroup;
  final ValueChanged<int> onRemoveGroup;
  final void Function(int groupIndex, String fieldKey) onGroupChanged;
  final ValueChanged<String?> onAgeGroupChanged;
  final ValueChanged<int> onAddAgeRow;
  final void Function(int groupIndex, int ageRowIndex) onRemoveAgeRow;
  final VoidCallback onAgeAddFieldChanged;
  final void Function(int groupIndex, int ageRowIndex, String sex, int value) onAgeCountChanged;

  @override
  Widget build(BuildContext context) {
    final totalLabel = total > 0 ? '$total' : '?';
    final sumMatch = total > 0 && currentSum == total;
    final sumColor = currentSum == 0
        ? AppColors.textGray
        : sumMatch
            ? const Color(0xFF00C48C)
            : AppColors.accentRed;
    final sumError = errors['demographicSum'];

    return _SectionCard(
      title: 'Guest Demographic Breakdown',
      subtitle: 'Must sum to $totalLabel total guests',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$currentSum / $totalLabel',
            style: TextStyle(
              color: sumColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sumError != null) ...[
            const SizedBox(height: 4),
            _InlineError(message: sumError),
            const SizedBox(height: 10),
          ],

          ...List.generate(groups.length, (i) {
            final g = groups[i];
            final gErr = i < groupErrors.length
                ? groupErrors[i]
                : <String, String?>{};
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GuestGroupCard(
                group: g,
                groupIndex: i,
                groupErrors: gErr,
                canDelete: groups.length > 1,
                pendingAgeGroup: pendingAgeGroup,
                pendingMaleCtrl: pendingMaleCtrl,
                pendingFemaleCtrl: pendingFemaleCtrl,
                ageAddError: ageAddError,
                onDelete: () => onRemoveGroup(i),
                onChanged: (fk) => onGroupChanged(i, fk),
                onAgeGroupChanged: onAgeGroupChanged,
                onAddAgeRow: () => onAddAgeRow(i),
                onRemoveAgeRow: (ai) => onRemoveAgeRow(i, ai),
                onAgeAddFieldChanged: onAgeAddFieldChanged,
                onAgeCountChanged: (ai, sex, v) =>
                    onAgeCountChanged(i, ai, sex, v),
              ),
            );
          }),

          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.lightbulb_outline, color: Color(0xFFD4A017), size: 13),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Add one group per guest origin (country, nationality, region — or "Overseas Filipino"). '
                  'Inside each group, add only the age brackets that actually apply — pick an age group, enter the Male/Female counts, and hit Add.',
                  style: TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: _AddGroupButton(onTap: onAddGroup),
          ),
        ],
      ),
    );
  }
}

// ─── Guest Group Card ─────────────────────────────────────────────────────────

class _GuestGroupCard extends StatelessWidget {
  const _GuestGroupCard({
    required this.group,
    required this.groupIndex,
    required this.groupErrors,
    required this.canDelete,
    required this.pendingAgeGroup,
    required this.pendingMaleCtrl,
    required this.pendingFemaleCtrl,
    required this.ageAddError,
    required this.onDelete,
    required this.onChanged,
    required this.onAgeGroupChanged,
    required this.onAddAgeRow,
    required this.onRemoveAgeRow,
    required this.onAgeAddFieldChanged,
    required this.onAgeCountChanged,
  });

  final GuestGroup group;
  final int groupIndex;
  final Map<String, String?> groupErrors;
  final bool canDelete;
  final String? pendingAgeGroup;
  final TextEditingController pendingMaleCtrl;
  final TextEditingController pendingFemaleCtrl;
  final String? ageAddError;
  final VoidCallback onDelete;
  final ValueChanged<String> onChanged;
  final ValueChanged<String?> onAgeGroupChanged;
  final VoidCallback onAddAgeRow;
  final void Function(int ageRowIndex) onRemoveAgeRow;
  final VoidCallback onAgeAddFieldChanged;
  final void Function(int ageRowIndex, String sex, int value) onAgeCountChanged;

  @override
  Widget build(BuildContext context) {
    final hasIssue = groupErrors.containsKey('country') ||
        groupErrors.containsKey('nationality') ||
        groupErrors.containsKey('duplicate') ||
        groupErrors.containsKey('ageRows');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: hasIssue
              ? AppColors.accentRed.withOpacity(0.45)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group header: overseas checkbox + origin fields + delete ──
          _GroupHeader(
            group: group,
            groupIndex: groupIndex,
            canDelete: canDelete,
            groupErrors: groupErrors,
            onDelete: onDelete,
            onChanged: onChanged,
          ),

          if (groupErrors['duplicate'] != null) ...[
            const SizedBox(height: 8),
            _InlineError(message: groupErrors['duplicate']!),
          ],
          if (groupErrors['ageRows'] != null) ...[
            const SizedBox(height: 8),
            _InlineError(message: groupErrors['ageRows']!),
          ],

          // ── Age breakdown section ──────────────────────────────────
          const SizedBox(height: 14),
          const Text(
            'AGE BREAKDOWN',
            style: TextStyle(
              color: AppColors.textGray,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.03,
            ),
          ),
          const SizedBox(height: 8),

          // ── Add age row control ──
          _AgeAddControl(
            groupIndex: groupIndex,
            group: group,
            pendingAgeGroup: pendingAgeGroup,
            maleCtrl: pendingMaleCtrl,
            femaleCtrl: pendingFemaleCtrl,
            ageAddError: ageAddError,
            onAgeGroupChanged: onAgeGroupChanged,
            onAddAgeRow: onAddAgeRow,
            onFieldChanged: onAgeAddFieldChanged,
          ),

          // ── Age breakdown table ──
          if (group.ageRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AgeBreakdownTable(
              ageRows: group.ageRows,
              groupIndex: groupIndex,
              onRemoveAgeRow: onRemoveAgeRow,
              onCountChanged: onAgeCountChanged,
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'No age groups added yet — use the control above to add headcounts.',
              style: TextStyle(
                color: AppColors.textSubtle,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Group Header ─────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.groupIndex,
    required this.canDelete,
    required this.groupErrors,
    required this.onDelete,
    required this.onChanged,
  });

  final GuestGroup group;
  final int groupIndex;
  final bool canDelete;
  final Map<String, String?> groupErrors;
  final VoidCallback onDelete;
  final ValueChanged<String> onChanged;

  bool get _isPhilippines =>
      !group.isOverseas && group.country == 'Philippines';

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Overseas checkbox + delete
        Row(
          children: [
            GestureDetector(
              onTap: () {
                group.isOverseas = !group.isOverseas;
                if (group.isOverseas) {
                  group.country = null;
                  group.nationality = null;
                  group.region = null;
                }
                onChanged('isOverseas');
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: group.isOverseas,
                      onChanged: (v) {
                        group.isOverseas = v ?? false;
                        if (group.isOverseas) {
                          group.country = null;
                          group.nationality = null;
                          group.region = null;
                        }
                        onChanged('isOverseas');
                      },
                      activeColor: const Color(0xFF3B82F6),
                      side: const BorderSide(
                          color: AppColors.textGray, width: 1.4),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Overseas Filipino',
                    style: TextStyle(color: AppColors.textGray, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (canDelete)
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.delete_rounded,
                    color: AppColors.accentRed, size: 16),
              ),
          ],
        ),

        const SizedBox(height: 10),

        // Row 2: Origin fields
        if (isMobile)
          Column(
            children: [
              _CompactDropWithError(
                errorText: groupErrors['country'],
                child: _CompactDrop(
                  hint: group.isOverseas ? 'N/A (Overseas)' : 'Country',
                  value: group.isOverseas ? null : group.country,
                  items: _countryOptions,
                  enabled: !group.isOverseas,
                  onChanged: (v) {
                    group.country = v;
                    if (v != 'Philippines') {
                      group.nationality = null;
                      group.region = null;
                    }
                    onChanged('country');
                  },
                ),
              ),
              if (_isPhilippines) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _CompactDropWithError(
                        errorText: groupErrors['nationality'],
                        child: _CompactDrop(
                          hint: 'Nationality',
                          value: group.nationality,
                          items: _nationalityOptions,
                          onChanged: (v) {
                            group.nationality = v;
                            onChanged('nationality');
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CompactDropWithError(
                        errorText: null,
                        child: _CompactDrop(
                          hint: 'Region',
                          value: group.region,
                          items: _regionOptions,
                          onChanged: (v) {
                            group.region = v;
                            onChanged('region');
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          )
        else
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _CompactDropWithError(
                  errorText: groupErrors['country'],
                  child: _CompactDrop(
                    hint: group.isOverseas ? 'N/A (Overseas)' : 'Country',
                    value: group.isOverseas ? null : group.country,
                    items: _countryOptions,
                    enabled: !group.isOverseas,
                    onChanged: (v) {
                      group.country = v;
                      if (v != 'Philippines') {
                        group.nationality = null;
                        group.region = null;
                      }
                      onChanged('country');
                    },
                  ),
                ),
              ),
              if (_isPhilippines) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _CompactDropWithError(
                    errorText: groupErrors['nationality'],
                    child: _CompactDrop(
                      hint: 'Nationality',
                      value: group.nationality,
                      items: _nationalityOptions,
                      onChanged: (v) {
                        group.nationality = v;
                        onChanged('nationality');
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _CompactDropWithError(
                    errorText: null,
                    child: _CompactDrop(
                      hint: 'Region',
                      value: group.region,
                      items: _regionOptions,
                      onChanged: (v) {
                        group.region = v;
                        onChanged('region');
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

// ─── Age Add Control ──────────────────────────────────────────────────────────

class _AgeAddControl extends StatelessWidget {
  const _AgeAddControl({
    required this.groupIndex,
    required this.group,
    required this.pendingAgeGroup,
    required this.maleCtrl,
    required this.femaleCtrl,
    required this.ageAddError,
    required this.onAgeGroupChanged,
    required this.onAddAgeRow,
    required this.onFieldChanged,
  });

  final int groupIndex;
  final GuestGroup group;
  final String? pendingAgeGroup;
  final TextEditingController maleCtrl;
  final TextEditingController femaleCtrl;
  final String? ageAddError;
  final ValueChanged<String?> onAgeGroupChanged;
  final VoidCallback onAddAgeRow;
  final VoidCallback onFieldChanged;

  List<String> get _availableAges {
    final used = group.ageRows.map((r) => r.ageGroup).toSet();
    return _ageGroupOptions.where((a) => !used.contains(a)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_availableAges.isEmpty) {
      return const Text(
        'All age groups have been added for this group.',
        style: TextStyle(
          color: AppColors.textSubtle,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardBackground.withOpacity(0.6),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: double.infinity,
                height: 36,
                child: _CompactDrop(
                  hint: 'Select age group',
                  value: _availableAges.contains(pendingAgeGroup)
                      ? pendingAgeGroup
                      : null,
                  items: _availableAges,
                  onChanged: onAgeGroupChanged,
                ),
              ),
              SizedBox(
                width: 70,
                height: 36,
                child: TextField(
                  controller: maleCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onChanged: (_) => onFieldChanged(),
                  style: const TextStyle(color: _kInputText, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Male',
                    hintStyle: const TextStyle(color: _kInputHint, fontSize: 11.5),
                    filled: true,
                    fillColor: _kInputFill,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: _kInputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: _kInputBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(7)),
                      borderSide: BorderSide(color: _kInputFocused, width: 1.4),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                height: 36,
                child: TextField(
                  controller: femaleCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onChanged: (_) => onFieldChanged(),
                  style: const TextStyle(color: _kInputText, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Female',
                    hintStyle: const TextStyle(color: _kInputHint, fontSize: 11.5),
                    filled: true,
                    fillColor: _kInputFill,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: _kInputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: _kInputBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(7)),
                      borderSide: BorderSide(color: _kInputFocused, width: 1.4),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: onAddAgeRow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                  ),
                  child: const Text(
                    '+ Add',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (ageAddError != null) ...[
          const SizedBox(height: 6),
          _InlineError(message: ageAddError!),
        ],
      ],
    );
  }
}

// ─── Age Breakdown Table ──────────────────────────────────────────────────────

class _AgeBreakdownTable extends StatelessWidget {
  const _AgeBreakdownTable({
    required this.ageRows,
    required this.groupIndex,
    required this.onRemoveAgeRow,
    required this.onCountChanged,
  });

  final List<AgeGroupRow> ageRows;
  final int groupIndex;
  final void Function(int ageRowIndex) onRemoveAgeRow;
  final void Function(int ageRowIndex, String sex, int value) onCountChanged;

  static Widget _buildCountField({
    required int value,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: 42,
      height: 30,
      child: TextField(
        key: ValueKey(value),
        controller: TextEditingController(text: value == 0 ? '' : '$value'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        onChanged: onChanged,
        style: const TextStyle(
            color: _kInputText, fontSize: 12.5, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: const TextStyle(color: _kInputHint, fontSize: 12),
          filled: true,
          fillColor: _kInputFill,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: _kInputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: _kInputBorder),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            borderSide: BorderSide(color: _kInputFocused, width: 1.4),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupTotal =
        ageRows.fold(0, (sum, r) => sum + r.male + r.female);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBorder.withOpacity(0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const Expanded(
                    flex: 3,
                    child: Text('AGE GROUP',
                        style: TextStyle(
                            color: AppColors.textSubtle,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.04))),
                const Expanded(
                    flex: 2,
                    child: Text('M',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSubtle,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.04))),
                const Expanded(
                    flex: 2,
                    child: Text('F',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSubtle,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.04))),
                const Expanded(
                    flex: 2,
                    child: Text('TOTAL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSubtle,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.04))),
                const SizedBox(width: 24),
              ],
            ),
          ),

          // Rows
          ...List.generate(ageRows.length, (i) {
            final r = ageRows[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: AppColors.cardBorder.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text(r.ageGroup,
                          style: const TextStyle(
                              color: AppColors.textGray, fontSize: 12))),
                  Expanded(
                    flex: 2,
                    child: _buildCountField(
                      value: r.male,
                      onChanged: (v) =>
                          onCountChanged(i, 'male', int.tryParse(v) ?? 0),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildCountField(
                      value: r.female,
                      onChanged: (v) =>
                          onCountChanged(i, 'female', int.tryParse(v) ?? 0),
                    ),
                  ),
                  Expanded(
                      flex: 2,
                      child: Text('${r.total}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textSubtle,
                              fontSize: 12,
                              fontWeight: FontWeight.w600))),
                  SizedBox(
                    width: 24,
                    child: GestureDetector(
                      onTap: () => onRemoveAgeRow(i),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.accentRed, size: 15),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Footer total
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.cardBorder.withOpacity(0.2),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const Expanded(
                    flex: 3,
                    child: Text('Group Total',
                        style: TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: SizedBox()),
                const Expanded(flex: 2, child: SizedBox()),
                Expanded(
                    flex: 2,
                    child: Text('$groupTotal',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.primaryCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Group Button ─────────────────────────────────────────────────────────

class _AddGroupButton extends StatelessWidget {
  const _AddGroupButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.white, size: 16),
              SizedBox(width: 7),
              Text(
                'Add Guest Group',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Form Actions ─────────────────────────────────────────────────────────────

class _FormActions extends StatelessWidget {
  const _FormActions({
    required this.onClear,
    required this.onSave,
    required this.isSaving,
  });

  final VoidCallback onClear;
  final VoidCallback onSave;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final saveBtn = SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: isSaving ? null : onSave,
        icon: isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.person_add_rounded,
                size: 17,
                color: Colors.white,
              ),
        label: Text(
          isSaving ? 'Saving...' : 'Save Guest Entry',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );

    final clearBtn = SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: isSaving ? null : onClear,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.cardBorder),
          foregroundColor: AppColors.textGray,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
        child: const Text(
          'Clear Form',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );

    if (isMobile) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: saveBtn),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: clearBtn),
        ],
      );
    }

    return Row(
      children: [
        clearBtn,
        const SizedBox(width: 14),
        Expanded(child: saveBtn),
      ],
    );
  }
}

// ─── Shared Section Card ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
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
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.primaryCyan,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ─── Field Column ─────────────────────────────────────────────────────────────

class _FieldCol extends StatelessWidget {
  const _FieldCol({required this.label, required this.child, this.errorText});

  final String label;
  final Widget child;
  final String? errorText;

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
        const SizedBox(height: 6),
        child,
        if (errorText != null) ...[
          const SizedBox(height: 5),
          _InlineError(message: errorText!),
        ],
      ],
    );
  }
}

// ─── Inline Error ─────────────────────────────────────────────────────────────

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 12, color: AppColors.accentRed),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.accentRed,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Compact Drop with error wrapper ─────────────────────────────────────────

class _CompactDropWithError extends StatelessWidget {
  const _CompactDropWithError({required this.child, this.errorText});
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (errorText == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        const SizedBox(height: 3),
        _InlineError(message: errorText!),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  INPUT WIDGETS — all sized to _kFieldHeight (40 px)
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _lightDecoration({String? hint, bool hasError = false}) {
  final borderColor = hasError ? AppColors.accentRed : _kInputBorder;
  final focusColor = hasError ? AppColors.accentRed : _kInputFocused;
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _kInputHint, fontSize: 13),
    filled: true,
    fillColor: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: focusColor, width: 1.4),
    ),
  );
}

class _EntryDateField extends StatelessWidget {
  const _EntryDateField({
    required this.value,
    required this.onTap,
    this.hasError = false,
  });
  final String value;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: _kFieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasError ? AppColors.accentRed : _kInputBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? 'yyyy-mm-dd' : value,
                style: TextStyle(
                  color: value.isEmpty ? _kInputHint : _kInputText,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              color: hasError ? AppColors.accentRed : _kInputHint,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryReadOnlyField extends StatelessWidget {
  const _EntryReadOnlyField({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kReadOnlyFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kInputBorder),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      ),
    );
  }
}

class _EntryNumberField extends StatelessWidget {
  const _EntryNumberField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _lightDecoration(hint: hint, hasError: hasError),
      ),
    );
  }
}

class _EntryTextField extends StatelessWidget {
  const _EntryTextField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _lightDecoration(hint: hint, hasError: hasError),
      ),
    );
  }
}

class _EntryDropdownField extends StatelessWidget {
  const _EntryDropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = 'Select option',
    this.hasError = false,
  });
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String hint;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError ? AppColors.accentRed : _kInputBorder,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: const TextStyle(color: _kInputHint, fontSize: 13),
          ),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: hasError ? AppColors.accentRed : _kInputHint,
          ),
          style: const TextStyle(color: _kInputText, fontSize: 13),
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    style: const TextStyle(color: _kInputText, fontSize: 13),
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

class _CompactDrop extends StatelessWidget {
  const _CompactDrop({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = (value != null && items.contains(value))
        ? value
        : null;
    final fillColor = enabled ? _kInputFill : _kReadOnlyFill;
    final textColor = enabled ? _kInputText : const Color(0xFF9CA3AF);
    final hintColor = enabled ? _kInputHint : const Color(0xFFD1D5DB);
    final iconColor = enabled ? _kInputHint : const Color(0xFFD1D5DB);
    final borderColor = enabled ? _kInputBorder : const Color(0xFFE5E7EB);

    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          hint: Text(hint, style: TextStyle(color: hintColor, fontSize: 12.5)),
          style: TextStyle(color: textColor, fontSize: 12.5),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: iconColor,
            size: 14,
          ),
          iconSize: 14,
          isExpanded: true,
          isDense: true,
          onChanged: enabled ? onChanged : null,
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    style: TextStyle(color: textColor, fontSize: 12.5),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
