// ignore_for_file: use_null_aware_elements

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/country_constants.dart';
import '../pages/business_guest_records_page.dart';
import 'dart:async';
import '../../../core/services/offline_service.dart';

// ─── Light input colours ──────────────────────────────────────────────────────

const _kInputFill = Color(0xFFF8FAFC);
const _kInputBorder = Color(0xFFD1D5DB);
const _kInputFocused = Color(0xFF3B82F6);
const _kDropBg = Color(0xFFFFFFFF);
const _kInputText = Color(0xFF111827);
const _kInputHint = Color(0xFF9CA3AF);
const _kReadOnlyFill = Color(0xFFEFF2F5);

/// Uniform height for every input, dropdown, and read-only field.
const _kFieldHeight = 40.0;

// ─── Demographic models (matching entry page) ────────────────────────────────

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

// ─── Conversion: breakdowns → groups ──────────────────────────────────────────

List<GuestGroup> _groupsFromBreakdowns(List<GuestBreakdownEntry> breakdowns) {
  final map = <String, GuestGroup>{};

  for (final b in breakdowns) {
    final originKey = b.isOverseas
        ? 'overseas'
        : '${b.country ?? ''}|${b.nationality ?? ''}|${b.philippinesRegion ?? ''}';

    final group = map.putIfAbsent(originKey, () {
      final g = GuestGroup();
      g.isOverseas = b.isOverseas;
      g.country = b.isOverseas ? null : b.country;
      g.nationality = (b.isOverseas || b.country != 'Philippines')
          ? null
          : b.nationality;
      g.region = (!b.isOverseas && b.country == 'Philippines')
          ? b.philippinesRegion
          : null;
      return g;
    });

    final sex = b.sex.isNotEmpty
        ? '${b.sex[0].toUpperCase()}${b.sex.substring(1).toLowerCase()}'
        : '';
    if (sex.isEmpty) continue;

    final existing = group.ageRows.where((r) => r.ageGroup == b.ageGroup);
    if (existing.isNotEmpty) {
      final row = existing.first;
      if (sex == 'Male') {
        row.male += b.count;
      } else if (sex == 'Female') {
        row.female += b.count;
      }
    } else {
      group.ageRows.add(AgeGroupRow(
        ageGroup: b.ageGroup,
        male: sex == 'Male' ? b.count : 0,
        female: sex == 'Female' ? b.count : 0,
      ));
    }
  }

  return map.values.toList();
}

// ─── Conversion: groups → breakdowns ──────────────────────────────────────────

List<GuestBreakdownEntry> _breakdownsFromGroups(List<GuestGroup> groups) {
  final breakdowns = <GuestBreakdownEntry>[];
  for (final g in groups) {
    for (final row in g.ageRows) {
      if (row.male > 0) {
        breakdowns.add(GuestBreakdownEntry(
          country: g.isOverseas ? null : mapToReportFormat(g.country!),
          nationality: (g.isOverseas || g.country != 'Philippines')
              ? null
              : g.nationality,
          philippinesRegion:
              (!g.isOverseas && g.country == 'Philippines') ? g.region : null,
          sex: 'male',
          ageGroup: row.ageGroup,
          count: row.male,
          isOverseas: g.isOverseas,
        ));
      }
      if (row.female > 0) {
        breakdowns.add(GuestBreakdownEntry(
          country: g.isOverseas ? null : mapToReportFormat(g.country!),
          nationality: (g.isOverseas || g.country != 'Philippines')
              ? null
              : g.nationality,
          philippinesRegion:
              (!g.isOverseas && g.country == 'Philippines') ? g.region : null,
          sex: 'female',
          ageGroup: row.ageGroup,
          count: row.female,
          isOverseas: g.isOverseas,
        ));
      }
    }
  }
  return breakdowns;
}

// ─── Show helper ──────────────────────────────────────────────────────────────

Future<GuestRecord?> showEditGuestDialog(
  BuildContext context, {
  required GuestRecord record,
}) {
  return showDialog<GuestRecord>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => _EditGuestDialog(record: record),
  );
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

class _EditGuestDialog extends StatefulWidget {
  const _EditGuestDialog({required this.record});
  final GuestRecord record;

  @override
  State<_EditGuestDialog> createState() => _EditGuestDialogState();
}

class _EditGuestDialogState extends State<_EditGuestDialog> {
  late final TextEditingController _checkInCtrl;
  late final TextEditingController _checkOutCtrl;
  late final TextEditingController _guestsCtrl;
  late final TextEditingController _roomsCtrl;
  late String _purpose;
  late String _transport;

  // ── Connectivity ──────────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;
  final TextEditingController _purposeOtherCtrl = TextEditingController();
  final TextEditingController _transportOtherCtrl = TextEditingController();
  bool _showPurposeOther = false;
  bool _showTransportOther = false;
  String _lengthOfStay = '0 nights';

  // ── Demographic groups (matching entry page) ──────────────────────────────
  final List<GuestGroup> _groups = [GuestGroup()];
  List<Map<String, String?>> _groupErrors = [{}];

  // Pending age-add controls per group
  String? _pendingAgeGroup;
  final TextEditingController _pendingMaleCtrl = TextEditingController(text: '');
  final TextEditingController _pendingFemaleCtrl = TextEditingController(text: '');
  String? _ageAddError;

  // ── Inline validation state ───────────────────────────────────────────────
  Map<String, String?> _errors = {};

  // ─── Options ────────────────────────────────────────────────────────────────

  static const _purposes = [
    'Leisure',
    'Business',
    'Education',
    'Medical',
    'Religious',
    'Others',
  ];

  static const _transports = [
    'Private Car',
    'Bus',
    'Van',
    'Motorcycle',
    'Tricycle',
    'Others',
  ];

  static const _ageGroupOptions = [
    '0–9',
    '10–17',
    '18–25',
    '26–35',
    '36–45',
    '46–55',
    '56+',
    'Prefer not to say',
  ];

  // ─── Normalise age-group from DB (hyphen) → UI option (en-dash) ───────────

  static String _normaliseAgeGroup(String raw) {
    if (_ageGroupOptions.contains(raw)) return raw;
    final withEndash = raw.trim().replaceAll('-', '–');
    if (_ageGroupOptions.contains(withEndash)) return withEndash;
    if (raw.trim() == '1-9' || raw.trim() == '1–9') return '0–9';
    if (raw.toLowerCase().replaceAll('_', ' ').contains('prefer')) {
      return 'Prefer not to say';
    }
    return '';
  }

  // ─── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final r = widget.record;

    String stripTime(String d) {
      if (d.contains('T')) return d.split('T')[0];
      if (d.contains(' ')) return d.split(' ')[0];
      return d;
    }

    _checkInCtrl = TextEditingController(text: stripTime(r.checkIn));
    _checkOutCtrl = TextEditingController(text: stripTime(r.checkOut));
    _guestsCtrl = TextEditingController(text: r.guests.toString());
    _roomsCtrl = TextEditingController(text: r.rooms.toString());

    if (_purposes.contains(r.purpose)) {
      _purpose = r.purpose;
      _showPurposeOther = r.purpose == 'Others';
    } else {
      _purpose = 'Others';
      _showPurposeOther = true;
      _purposeOtherCtrl.text = r.purpose;
    }

    if (_transports.contains(r.transport)) {
      _transport = r.transport;
      _showTransportOther = r.transport == 'Others';
    } else {
      _transport = 'Others';
      _showTransportOther = true;
      _transportOtherCtrl.text = r.transport;
    }

    _lengthOfStay = r.nights;

    if (r.demographics != null && r.demographics!.breakdowns.isNotEmpty) {
      _groups
        ..clear()
        ..addAll(_groupsFromBreakdowns(r.demographics!.breakdowns));
      // Normalise age groups from DB format
      for (final g in _groups) {
        for (final row in g.ageRows) {
          final normalised = _normaliseAgeGroup(row.ageGroup);
          if (normalised.isNotEmpty && normalised != row.ageGroup) {
            final idx = g.ageRows.indexOf(row);
            g.ageRows[idx] = AgeGroupRow(
              ageGroup: normalised,
              male: row.male,
              female: row.female,
            );
          }
        }
      }
    }

    _groupErrors = List.generate(_groups.length, (_) => {});

    _isOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((isOnline) {
          if (mounted) setState(() => _isOffline = !isOnline);
        });
  }

  @override
  void dispose() {
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _guestsCtrl.dispose();
    _roomsCtrl.dispose();
    _purposeOtherCtrl.dispose();
    _transportOtherCtrl.dispose();
    _pendingMaleCtrl.dispose();
    _pendingFemaleCtrl.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ─── Derived values ───────────────────────────────────────────────────────

  int get _demographicTotal =>
      _groups.fold(0, (sum, g) => sum + g.groupTotal);
  int get _totalGuests => int.tryParse(_guestsCtrl.text.trim()) ?? 0;

  // ─── Nights calculation ──────────────────────────────────────────────────

  void _recalcNights() {
    final checkIn = DateTime.tryParse(_checkInCtrl.text.trim());
    final checkOut = DateTime.tryParse(_checkOutCtrl.text.trim());
    if (checkIn == null || checkOut == null) {
      setState(() => _lengthOfStay = '0 nights');
      return;
    }
    final nights = checkOut.difference(checkIn).inDays.clamp(0, 999);
    setState(() {
      _lengthOfStay = '$nights night${nights == 1 ? '' : 's'}';
    });
  }

  // ─── Group management ────────────────────────────────────────────────────

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

  // ─── Age row management ──────────────────────────────────────────────────

  void _onAddAgeRow(int groupIndex) {
    final g = _groups[groupIndex];
    final male = int.tryParse(_pendingMaleCtrl.text) ?? 0;
    final female = int.tryParse(_pendingFemaleCtrl.text) ?? 0;
    if (_pendingAgeGroup == null) {
      setState(() => _ageAddError = 'Select an age group first.');
      return;
    }
    if (male <= 0 && female <= 0) {
      setState(
          () => _ageAddError = 'Enter at least 1 guest for this age group.');
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
  }

  void _onRemoveAgeRow(int groupIndex, int ageRowIndex) {
    setState(() {
      _groups[groupIndex].ageRows.removeAt(ageRowIndex);
    });
    _clearFieldError('demographicSum');
  }

  // ─── Error clearing ───────────────────────────────────────────────────────

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

  // ─── Validation ───────────────────────────────────────────────────────────

  bool _validateAndSetErrors() {
    final errors = <String, String?>{};
    final groupErrs =
        List.generate(_groups.length, (_) => <String, String?>{});
    bool hasError = false;

    // ── Check-in ────────────────────────────────────────────────────────────
    final checkInText = _checkInCtrl.text.trim();
    final checkIn = DateTime.tryParse(checkInText);

    if (checkInText.isEmpty) {
      errors['checkIn'] = 'Please select a check-in date.';
      hasError = true;
    } else if (checkIn == null) {
      errors['checkIn'] = 'Invalid date — use yyyy-mm-dd format.';
      hasError = true;
    } else if (checkIn.isAfter(DateTime.now())) {
      errors['checkIn'] = 'Check-in date cannot be in the future.';
      hasError = true;
    }

    // ── Check-out ───────────────────────────────────────────────────────────
    final checkOutText = _checkOutCtrl.text.trim();
    final checkOut = DateTime.tryParse(checkOutText);

    if (checkOutText.isEmpty) {
      errors['checkOut'] = 'Please select a check-out date.';
      hasError = true;
    } else if (checkOut == null) {
      errors['checkOut'] = 'Invalid date — use yyyy-mm-dd format.';
      hasError = true;
    } else if (checkIn != null && checkOut.isBefore(checkIn)) {
      errors['checkOut'] =
          'Check-out must be the same day as check-in or later.';
      hasError = true;
    }

    // ── Total Guests ────────────────────────────────────────────────────────
    final guests = int.tryParse(_guestsCtrl.text.trim());
    if (guests == null || guests <= 0) {
      errors['totalGuests'] = 'Enter at least 1 guest.';
      hasError = true;
    } else if (guests > 9999) {
      errors['totalGuests'] = 'Value seems too large (max 9,999).';
      hasError = true;
    }

    // ── Rooms Occupied ──────────────────────────────────────────────────────
    final rooms = int.tryParse(_roomsCtrl.text.trim());
    if (rooms == null || rooms < 0) {
      errors['roomsOccupied'] = 'Enter a valid number of rooms.';
      hasError = true;
    } else if (guests != null && guests > 0 && rooms > guests) {
      errors['roomsOccupied'] = 'Rooms cannot exceed total guests.';
      hasError = true;
    } else if (checkIn != null &&
        checkOut != null &&
        checkOut.difference(checkIn).inDays > 0 &&
        rooms == 0) {
      errors['roomsOccupied'] =
          'At least 1 room is required when staying overnight.';
      hasError = true;
    }

    // ── Purpose ─────────────────────────────────────────────────────────────
    if (_purpose.isEmpty) {
      errors['purpose'] = 'Please select a purpose of visit.';
      hasError = true;
    } else if (_purpose == 'Others' &&
        _purposeOtherCtrl.text.trim().isEmpty) {
      errors['purposeOther'] = 'Please specify the purpose.';
      hasError = true;
    }

    // ── Transport ───────────────────────────────────────────────────────────
    if (_transport.isEmpty) {
      errors['transport'] = 'Please select a mode of transportation.';
      hasError = true;
    } else if (_transport == 'Others' &&
        _transportOtherCtrl.text.trim().isEmpty) {
      errors['transportOther'] = 'Please specify the transportation.';
      hasError = true;
    }

    // ── Group-level validation (matching entry page) ──────────────────────
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

  // ─── Save ─────────────────────────────────────────────────────────────────

  void _save() {
    if (!_validateAndSetErrors()) return;

    final purposeValue =
        _purpose == 'Others' ? _purposeOtherCtrl.text.trim() : _purpose;
    final transportValue =
        _transport == 'Others' ? _transportOtherCtrl.text.trim() : _transport;

    final breakdowns = _breakdownsFromGroups(_groups);

    final ageGroups = <String, int>{};
    final sexDist = <String, int>{};
    final countries = <String, int>{};

    for (final b in breakdowns) {
      if (b.ageGroup.isNotEmpty) {
        ageGroups[b.ageGroup] = (ageGroups[b.ageGroup] ?? 0) + b.count;
      }
      if (b.sex.isNotEmpty) {
        sexDist[b.sex] = (sexDist[b.sex] ?? 0) + b.count;
      }
      final key = b.isOverseas
          ? 'Overseas'
          : (b.country == 'Philippines' &&
                  b.philippinesRegion != null &&
                  b.philippinesRegion != 'N/A')
              ? 'PH – ${b.philippinesRegion}'
              : (b.country ?? '');
      if (key.isNotEmpty) countries[key] = (countries[key] ?? 0) + b.count;
    }

    final demographics = GuestDemographics(
      ageGroups: ageGroups,
      sexDistribution: sexDist,
      countries: countries,
      breakdowns: breakdowns,
    );

    final updated = GuestRecord(
      id: widget.record.id,
      checkIn: _checkInCtrl.text.trim(),
      checkOut: _checkOutCtrl.text.trim(),
      nights: _lengthOfStay,
      guests: _totalGuests,
      rooms: int.tryParse(_roomsCtrl.text.trim()) ?? widget.record.rooms,
      purpose: purposeValue,
      transport: transportValue,
      status: widget.record.status,
      demographics: demographics,
    );

    final messenger = ScaffoldMessenger.of(context);
    final isOnline = ConnectivityService.instance.isOnline;

    Navigator.of(context).pop(updated);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isOnline
              ? 'Guest record updated successfully!'
              : 'Changes saved offline — will sync when you\'re back online.',
        ),
        backgroundColor:
            isOnline ? AppColors.primaryCyan : const Color(0xFFF59E0B),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Clear form ──────────────────────────────────────────────────────────

  void _clearForm() {
    _checkInCtrl.clear();
    _checkOutCtrl.clear();
    _guestsCtrl.clear();
    _roomsCtrl.clear();
    _purposeOtherCtrl.clear();
    _transportOtherCtrl.clear();
    setState(() {
      _purpose = _purposes.first;
      _transport = _transports.first;
      _showPurposeOther = false;
      _showTransportOther = false;
      _lengthOfStay = '0 nights';
      _groups
        ..clear()
        ..add(GuestGroup());
      _groupErrors = [{}];
      _pendingAgeGroup = null;
      _pendingMaleCtrl.clear();
      _pendingFemaleCtrl.clear();
      _ageAddError = null;
      _errors = {};
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
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
            children: [
              _TitleBar(onClose: () => Navigator.of(context).pop()),
              if (_isOffline)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: const Color(0xFF1A1A2E),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFF8A9BB5),
                        size: 14,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You\'re offline — changes will be saved locally and synced later.',
                          style: TextStyle(
                            color: Color(0xFF8A9BB5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 14 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Global submit error ─────────────────────────
                      if (_errors['submit'] != null) ...[
                        _GlobalErrorBanner(message: _errors['submit']!),
                        const SizedBox(height: 12),
                      ],

                      // ── Stay Information ────────────────────────────
                      _SectionCard(
                        title: 'Stay Information',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Check-in / Check-out / Length of Stay ──
                            if (isNarrow) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-in Date *',
                                      errorText: _errors['checkIn'],
                                      child: _DateField(
                                        controller: _checkInCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError:
                                            _errors['checkIn'] != null,
                                        lastDate: DateTime.now(),
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkIn');
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-out Date *',
                                      errorText: _errors['checkOut'],
                                      child: _DateField(
                                        controller: _checkOutCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError:
                                            _errors['checkOut'] != null,
                                        firstDate: DateTime.tryParse(
                                              _checkInCtrl.text.trim(),
                                            ) ??
                                            DateTime(2020),
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _FieldCol(
                                label: 'Length of Stay',
                                child: _ReadOnlyField(value: _lengthOfStay),
                              ),
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-in Date *',
                                      errorText: _errors['checkIn'],
                                      child: _DateField(
                                        controller: _checkInCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError:
                                            _errors['checkIn'] != null,
                                        lastDate: DateTime.now(),
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkIn');
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-out Date *',
                                      errorText: _errors['checkOut'],
                                      child: _DateField(
                                        controller: _checkOutCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError:
                                            _errors['checkOut'] != null,
                                        firstDate: DateTime.tryParse(
                                              _checkInCtrl.text.trim(),
                                            ) ??
                                            DateTime(2020),
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Length of Stay',
                                      child: _ReadOnlyField(
                                        value: _lengthOfStay,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),

                            // ── Total Guests / Rooms ────────────────────
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _FieldCol(
                                    label: 'Total Guests *',
                                    errorText: _errors['totalGuests'],
                                    child: _NumberField(
                                      controller: _guestsCtrl,
                                      hint: 'e.g. 10',
                                      hasError:
                                          _errors['totalGuests'] != null,
                                      onChanged: (_) {
                                        setState(() {});
                                        _clearFieldError('totalGuests');
                                        _clearFieldError('roomsOccupied');
                                        _clearFieldError('demographicSum');
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _FieldCol(
                                    label: 'Rooms Occupied *',
                                    errorText: _errors['roomsOccupied'],
                                    child: _NumberField(
                                      controller: _roomsCtrl,
                                      hint: 'e.g. 3',
                                      hasError:
                                          _errors['roomsOccupied'] != null,
                                      onChanged: (_) => _clearFieldError(
                                          'roomsOccupied'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // ── Purpose / Transport ─────────────────────
                            if (isNarrow) ...[
                              _FieldCol(
                                label: 'Purpose of Visit *',
                                errorText: _errors['purpose'],
                                child: _DropdownField(
                                  value:
                                      _purpose.isEmpty ? null : _purpose,
                                  items: _purposes,
                                  hint: 'Select purpose',
                                  hasError:
                                      _errors['purpose'] != null,
                                  onChanged: (v) {
                                    setState(() {
                                      _purpose = v ?? '';
                                      _showPurposeOther = v == 'Others';
                                      if (!_showPurposeOther) {
                                        _purposeOtherCtrl.clear();
                                      }
                                    });
                                    _clearFieldError('purpose');
                                    _clearFieldError('purposeOther');
                                  },
                                ),
                              ),
                              if (_showPurposeOther) ...[
                                const SizedBox(height: 10),
                                _FieldCol(
                                  label: 'Please specify *',
                                  errorText: _errors['purposeOther'],
                                  child: _PlainTextField(
                                    controller: _purposeOtherCtrl,
                                    hint: 'Specify purpose',
                                    hasError:
                                        _errors['purposeOther'] != null,
                                    onChanged: (_) => _clearFieldError(
                                        'purposeOther'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _FieldCol(
                                label: 'Mode of Transportation *',
                                errorText: _errors['transport'],
                                child: _DropdownField(
                                  value: _transport.isEmpty
                                      ? null
                                      : _transport,
                                  items: _transports,
                                  hint: 'Select transportation',
                                  hasError:
                                      _errors['transport'] != null,
                                  onChanged: (v) {
                                    setState(() {
                                      _transport = v ?? '';
                                      _showTransportOther =
                                          v == 'Others';
                                      if (!_showTransportOther) {
                                        _transportOtherCtrl.clear();
                                      }
                                    });
                                    _clearFieldError('transport');
                                    _clearFieldError('transportOther');
                                  },
                                ),
                              ),
                              if (_showTransportOther) ...[
                                const SizedBox(height: 10),
                                _FieldCol(
                                  label: 'Please specify *',
                                  errorText: _errors['transportOther'],
                                  child: _PlainTextField(
                                    controller: _transportOtherCtrl,
                                    hint: 'Specify transportation',
                                    hasError:
                                        _errors['transportOther'] !=
                                            null,
                                    onChanged: (_) => _clearFieldError(
                                        'transportOther'),
                                  ),
                                ),
                              ],
                            ] else ...[
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _FieldCol(
                                          label: 'Purpose of Visit *',
                                          errorText:
                                              _errors['purpose'],
                                          child: _DropdownField(
                                            value: _purpose.isEmpty
                                                ? null
                                                : _purpose,
                                            items: _purposes,
                                            hint: 'Select purpose',
                                            hasError: _errors[
                                                    'purpose'] !=
                                                null,
                                            onChanged: (v) {
                                              setState(() {
                                                _purpose = v ?? '';
                                                _showPurposeOther =
                                                    v == 'Others';
                                                if (!_showPurposeOther) {
                                                  _purposeOtherCtrl
                                                      .clear();
                                                }
                                              });
                                              _clearFieldError(
                                                  'purpose');
                                              _clearFieldError(
                                                  'purposeOther');
                                            },
                                          ),
                                        ),
                                        if (_showPurposeOther) ...[
                                          const SizedBox(height: 10),
                                          _FieldCol(
                                            label: 'Please specify *',
                                            errorText: _errors[
                                                'purposeOther'],
                                            child: _PlainTextField(
                                              controller:
                                                  _purposeOtherCtrl,
                                              hint: 'Specify purpose',
                                              hasError: _errors[
                                                      'purposeOther'] !=
                                                  null,
                                              onChanged: (_) =>
                                                  _clearFieldError(
                                                    'purposeOther',
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _FieldCol(
                                          label:
                                              'Mode of Transportation *',
                                          errorText:
                                              _errors['transport'],
                                          child: _DropdownField(
                                            value: _transport.isEmpty
                                                ? null
                                                : _transport,
                                            items: _transports,
                                            hint:
                                                'Select transportation',
                                            hasError: _errors[
                                                    'transport'] !=
                                                null,
                                            onChanged: (v) {
                                              setState(() {
                                                _transport = v ?? '';
                                                _showTransportOther =
                                                    v == 'Others';
                                                if (!_showTransportOther) {
                                                  _transportOtherCtrl
                                                      .clear();
                                                }
                                              });
                                              _clearFieldError(
                                                  'transport');
                                              _clearFieldError(
                                                'transportOther',
                                              );
                                            },
                                          ),
                                        ),
                                        if (_showTransportOther) ...[
                                          const SizedBox(height: 10),
                                          _FieldCol(
                                            label: 'Please specify *',
                                            errorText: _errors[
                                                'transportOther'],
                                            child: _PlainTextField(
                                              controller:
                                                  _transportOtherCtrl,
                                              hint:
                                                  'Specify transportation',
                                              hasError: _errors[
                                                      'transportOther'] !=
                                                  null,
                                              onChanged: (_) =>
                                                  _clearFieldError(
                                                    'transportOther',
                                                  ),
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
                      ),
                      const SizedBox(height: 16),

                      // ── Demographic Breakdown (matching entry page) ──
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
                        onAddAgeRow: (int groupIndex) =>
                            _onAddAgeRow(groupIndex),
                        onAgeAddFieldChanged: () {
                          if (_ageAddError != null) {
                            setState(() => _ageAddError = null);
                          }
                        },
                        onRemoveAgeRow:
                            (int groupIndex, int ageRowIndex) =>
                                _onRemoveAgeRow(groupIndex, ageRowIndex),
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
                    ],
                  ),
                ),
              ),
              _Footer(onClear: _clearForm, onSave: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Title bar ────────────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Guest Entry',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Update tourist demographic data',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.textGray,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Global error banner ──────────────────────────────────────────────────────

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
              style:
                  const TextStyle(color: AppColors.accentRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Demographic Card (matching entry page) ───────────────────────────────────

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
              Icon(Icons.lightbulb_outline,
                  color: Color(0xFFD4A017), size: 13),
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

// ─── Guest Group Card (matching entry page) ──────────────────────────────────

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

// ─── Group Header (matching entry page) ──────────────────────────────────────

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

  static const _countryOptions = [
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

  static const _regionOptions = [
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

  static const _nationalityOptions = ['Filipino', 'Foreign'];

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
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Overseas Filipino',
                    style: TextStyle(
                        color: AppColors.textGray, fontSize: 11.5),
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
                  hint: group.isOverseas
                      ? 'N/A (Overseas)'
                      : 'Country',
                  value:
                      group.isOverseas ? null : group.country,
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
                    hint: group.isOverseas
                        ? 'N/A (Overseas)'
                        : 'Country',
                    value:
                        group.isOverseas ? null : group.country,
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

// ─── Age Add Control (matching entry page) ───────────────────────────────────

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

  static const _ageGroupOptions = [
    '0–9',
    '10–17',
    '18–25',
    '26–35',
    '36–45',
    '46–55',
    '56+',
    'Prefer not to say',
  ];

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
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  textAlign: TextAlign.center,
                  onChanged: (_) => onFieldChanged(),
                  style: const TextStyle(
                      color: _kInputText, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Male',
                    hintStyle: const TextStyle(
                        color: _kInputHint, fontSize: 11.5),
                    filled: true,
                    fillColor: _kInputFill,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide:
                          const BorderSide(color: _kInputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide:
                          const BorderSide(color: _kInputBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(7)),
                      borderSide: BorderSide(
                          color: _kInputFocused, width: 1.4),
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
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  textAlign: TextAlign.center,
                  onChanged: (_) => onFieldChanged(),
                  style: const TextStyle(
                      color: _kInputText, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Female',
                    hintStyle: const TextStyle(
                        color: _kInputHint, fontSize: 11.5),
                    filled: true,
                    fillColor: _kInputFill,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide:
                          const BorderSide(color: _kInputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide:
                          const BorderSide(color: _kInputBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(7)),
                      borderSide: BorderSide(
                          color: _kInputFocused, width: 1.4),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                  ),
                  child: const Text(
                    '+ Add',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
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

// ─── Age Breakdown Table (matching entry page) ───────────────────────────────

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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBorder.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(9)),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color:
                            AppColors.cardBorder.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text(r.ageGroup,
                          style: const TextStyle(
                              color: AppColors.textGray,
                              fontSize: 12))),
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
                      child: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.accentRed,
                          size: 15),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Footer total
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.cardBorder.withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(9)),
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

// ─── Section card ─────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─── Field column (label + field + inline error) ──────────────────────────────

class _FieldCol extends StatelessWidget {
  const _FieldCol(
      {required this.label, required this.child, this.errorText});

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

// ─── Inline error ─────────────────────────────────────────────────────────────

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.error_outline_rounded,
            size: 12,
            color: AppColors.accentRed,
          ),
        ),
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

// ─── Add Group button ─────────────────────────────────────────────────────────

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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.onClear, required this.onSave});
  final VoidCallback onClear;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              side:
                  const BorderSide(color: AppColors.cardBorder),
              foregroundColor: AppColors.textGray,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Clear Form',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon:
                  const Icon(Icons.save_outlined, size: 16),
              label: const Text(
                'Save Changes',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED INPUT DECORATION
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _fieldDecoration(
    {String? hint, bool hasError = false}) {
  final borderColor =
      hasError ? AppColors.accentRed : _kInputBorder;
  final focusColor =
      hasError ? AppColors.accentRed : _kInputFocused;
  return InputDecoration(
    hintText: hint,
    hintStyle:
        const TextStyle(color: _kInputHint, fontSize: 13),
    filled: true,
    fillColor: hasError
        ? AppColors.accentRed.withOpacity(0.04)
        : _kInputFill,
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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

// ─── Date field ───────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onPicked,
    this.firstDate,
    this.lastDate,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final VoidCallback? onPicked;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        readOnly: true,
        style:
            const TextStyle(color: _kInputText, fontSize: 13),
        decoration:
            _fieldDecoration(hint: hint, hasError: hasError)
                .copyWith(
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            color: hasError
                ? AppColors.accentRed
                : _kInputHint,
            size: 14,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: _kFieldHeight,
          ),
        ),
        onTap: () async {
          final current =
              DateTime.tryParse(controller.text);
          final now = DateTime.now();
          final resolvedFirst =
              firstDate ?? DateTime(2020);
          final resolvedLast = lastDate ??
              now.add(const Duration(days: 730));
          final safeInitial = (current != null &&
                  !current.isBefore(resolvedFirst) &&
                  !current.isAfter(resolvedLast))
              ? current
              : resolvedFirst;

          final picked = await showDatePicker(
            context: context,
            initialDate: safeInitial,
            firstDate: resolvedFirst,
            lastDate: resolvedLast,
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
          if (picked != null) {
            controller.text =
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}';
            onPicked?.call();
          }
        },
      ),
    );
  }
}

// ─── Read-only field ──────────────────────────────────────────────────────────

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.value});
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
        style: const TextStyle(
            color: Color(0xFF6B7280), fontSize: 13),
      ),
    );
  }
}

// ─── Number field ─────────────────────────────────────────────────────────────

class _NumberField extends StatelessWidget {
  const _NumberField({
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
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly
        ],
        style:
            const TextStyle(color: _kInputText, fontSize: 13),
        decoration:
            _fieldDecoration(hint: hint, hasError: hasError),
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Plain text field ─────────────────────────────────────────────────────────

class _PlainTextField extends StatelessWidget {
  const _PlainTextField({
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
        style:
            const TextStyle(color: _kInputText, fontSize: 13),
        decoration:
            _fieldDecoration(hint: hint, hasError: hasError),
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Full-width dropdown field (Purpose / Transport) ─────────────────────────

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.hasError = false,
  });
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        hasError ? AppColors.accentRed : _kInputBorder;
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.accentRed.withOpacity(0.04)
            : _kInputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: const TextStyle(
                color: _kInputHint, fontSize: 13),
          ),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: hasError
                ? AppColors.accentRed
                : _kInputHint,
            size: 18,
          ),
          style: const TextStyle(
              color: _kInputText, fontSize: 13),
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    style: const TextStyle(
                        color: _kInputText, fontSize: 13),
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

// ─── Compact dropdown for demographic rows ────────────────────────────────────

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
    final effectiveValue =
        (value != null && items.contains(value)) ? value : null;
    final fillColor =
        enabled ? _kInputFill : _kReadOnlyFill;
    final textColor = enabled
        ? _kInputText
        : const Color(0xFF9CA3AF);
    final hintColor = enabled
        ? _kInputHint
        : const Color(0xFFD1D5DB);
    final iconColor = enabled
        ? _kInputHint
        : const Color(0xFFD1D5DB);
    final borderColor = enabled
        ? _kInputBorder
        : const Color(0xFFE5E7EB);

    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          hint: Text(
            hint,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(color: hintColor, fontSize: 12.5),
          ),
          style:
              TextStyle(color: textColor, fontSize: 12.5),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: iconColor,
            size: 16,
          ),
          isExpanded: true,
          isDense: true,
          onChanged: enabled ? onChanged : null,
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: textColor, fontSize: 12.5),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ─── Compact drop with inline error wrapper ───────────────────────────────────

class _CompactDropWithError extends StatelessWidget {
  const _CompactDropWithError(
      {required this.child, this.errorText});

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
