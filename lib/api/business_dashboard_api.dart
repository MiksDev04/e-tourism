// ignore_for_file: prefer_null_aware_operators, use_null_aware_elements, inference_failure_on_function_invocation

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class DashboardStats {
  const DashboardStats({
    required this.guestsThisMonth,
    required this.guestsThisYear,
    required this.avgLengthOfStay,
    required this.totalRooms,
  });

  final int guestsThisMonth;
  final int guestsThisYear;
  final double avgLengthOfStay;
  final int totalRooms;
}

class SexDistribution {
  const SexDistribution({
    required this.male,
    required this.female,
    required this.other,
  });

  final int male;
  final int female;
  final int other;

  int get total => male + female + other;
  double get maleRatio => total == 0 ? 0 : male / total;
  double get femaleRatio => total == 0 ? 0 : female / total;
}

class CountryCount {
  const CountryCount({required this.country, required this.count});

  final String country;
  final int count;
}

class RegionCount {
  const RegionCount({required this.region, required this.count});

  final String region;
  final int count;
}

class MonthlyCount {
  const MonthlyCount({required this.month, required this.count});

  final int month; // 1–12
  final int count;
}

class AgeGroupCount {
  const AgeGroupCount({required this.ageGroup, required this.count});

  final String ageGroup;
  final int count;
}

class PurposeCount {
  const PurposeCount({required this.purpose, required this.count});

  final String purpose;
  final int count;
}

class DashboardData {
  const DashboardData({
    required this.stats,
    required this.sexDistribution,
    required this.topCountries,
    required this.topRegions,
    required this.ageGroups,
    required this.purposeOfVisit,
  });

  final DashboardStats stats;
  final SexDistribution sexDistribution;
  final List<CountryCount> topCountries;
  final List<RegionCount> topRegions;
  final List<AgeGroupCount> ageGroups;
  final List<PurposeCount> purposeOfVisit;
}

class BusinessDetails {
  const BusinessDetails({
    required this.address,
    required this.barangay,
    required this.totalRooms,
    required this.businessLine,
  });

  final String address;
  final String barangay;
  final int totalRooms;
  final List<String> businessLine;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class BusinessDashboardApi extends BaseApi {
  BusinessDashboardApi();

  // ── Date helpers ─────────────────────────────────────────────────────────────

  (String start, String end) _dateRange(int month, int year) {
    if (month == 0) {
      return ('$year-01-01', '$year-12-31');
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final mm = month.toString().padLeft(2, '0');
    final dd = lastDay.toString().padLeft(2, '0');
    return ('$year-$mm-01', '$year-$mm-$dd');
  }

  // ===========================================================================
  // PUBLIC — resolveBusinessId
  // ===========================================================================

  Future<String?> resolveBusinessId({bool preferOnline = false}) async {
    if ((preferOnline || ConnectivityService.instance.isOnline) && hasToken) {
      try {
        final online = await _resolveBusinessIdOnline();
        if (online != null && online.isNotEmpty) return online;
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ resolveBusinessId: Unauthorized (401). Falling back to local.');
        }
      } catch (_) {
        // Fall through to local/session fallback.
      }
    }

    final cachedSession =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    final fromSession = cachedSession?.businessId;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;

    return _resolveBusinessIdFromLocalDb();
  }

  Future<String?> _resolveBusinessIdOnline() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      return data?['business']?['id']?.toString();
    } on ApiException catch (e) {
      print('⚠️ resolveBusinessIdOnline: API error ($e). Falling back to local.');
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveBusinessIdFromLocalDb() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableLocalBusinesses,
      columns: ['id'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  // ===========================================================================
  // PUBLIC — fetchBusinessDetails
  // ===========================================================================

  Future<BusinessDetails> fetchBusinessDetails(
    String businessId, {
    bool preferOnline = false,
  }) async {
    final tryOnline = (preferOnline || ConnectivityService.instance.isOnline) && hasToken;

    if (tryOnline) {
      try {
        return await _fetchBusinessDetailsOnline(businessId);
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ fetchBusinessDetails: Unauthorized (401). Falling back to local.');
          return await _fetchBusinessDetailsOffline(businessId);
        }
      } catch (_) {
        // Reconnect policy: fallback to SQLite immediately.
      }
    }

    return _fetchBusinessDetailsOffline(businessId);
  }

  Future<BusinessDetails> _fetchBusinessDetailsOnline(String businessId) async {
    try {
      final response = await get('/api/dashboard/details?businessId=$businessId');
      final data = handleResponse(response) as Map<String, dynamic>?;

      if (data == null) {
        return const BusinessDetails(
          address: '',
          barangay: '',
          totalRooms: 0,
          businessLine: [],
        );
      }

      final street = (data['street'] as String?) ?? '';
      final barangay = (data['barangay'] as String?) ?? '';
      final rawBusinessLine = data['business_line'];
      List<String> businessLine = [];
      if (rawBusinessLine is List) {
        businessLine = rawBusinessLine.map((v) => v.toString()).toList();
      } else if (rawBusinessLine is String) {
        try {
          final decoded = jsonDecode(rawBusinessLine);
          if (decoded is List) {
            businessLine = decoded.map((v) => v.toString()).toList();
          } else {
            businessLine = [rawBusinessLine];
          }
        } catch (_) {
          businessLine = [rawBusinessLine];
        }
      }

      return BusinessDetails(
        address: street,
        barangay: barangay,
        totalRooms: (data['total_rooms'] as int?) ?? 0,
        businessLine: businessLine,
      );
    } catch (_) {
      return const BusinessDetails(
        address: '',
        barangay: '',
        totalRooms: 0,
        businessLine: [],
      );
    }
  }

  Future<BusinessDetails> _fetchBusinessDetailsOffline(
    String businessId,
  ) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableLocalBusinesses,
      where: 'id = ?',
      whereArgs: [businessId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return const BusinessDetails(
        address: '',
        barangay: '',
        totalRooms: 0,
        businessLine: [],
      );
    }

    final row = rows.first;
    final street = (row['street'] as String?) ?? '';
    final barangay = (row['barangay'] as String?) ?? '';
    final rawBusinessLine = row['business_line'] as String?;

    // business_line is stored as a JSON string e.g. '["Hotel","Resort"]'
    List<String> businessLine = [];
    if (rawBusinessLine != null && rawBusinessLine.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBusinessLine);
        if (decoded is List) {
          businessLine = decoded.map((v) => v.toString()).toList();
        }
      } catch (_) {
        businessLine = [rawBusinessLine];
      }
    }

    return BusinessDetails(
      address: street,
      barangay: barangay,
      totalRooms: (row['total_rooms'] as int?) ?? 0,
      businessLine: businessLine,
    );
  }

  // ===========================================================================
  // PUBLIC — fetchDashboardData
  // ===========================================================================

  Future<DashboardData> fetchDashboardData({
    required String businessId,
    required int totalRooms,
    required int month,
    required int year,
    bool preferOnline = false,
  }) async {
    final tryOnline = (preferOnline || ConnectivityService.instance.isOnline) && hasToken;

    if (tryOnline) {
      try {
        return await _fetchDashboardDataOnline(
          businessId: businessId,
          totalRooms: totalRooms,
          month: month,
          year: year,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ fetchDashboardData: Unauthorized (401). Falling back to local.');
          return await _fetchDashboardDataOffline(
            businessId: businessId,
            totalRooms: totalRooms,
            month: month,
            year: year,
          );
        }
      } catch (_) {
        // Reconnect policy: fallback to SQLite immediately.
      }
    }

    return _fetchDashboardDataOffline(
      businessId: businessId,
      totalRooms: totalRooms,
      month: month,
      year: year,
    );
  }

  // ===========================================================================
  // ONLINE — fetch from API
  // ===========================================================================

  Future<DashboardData> _fetchDashboardDataOnline({
    required String businessId,
    required int totalRooms,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final (yearStart, yearEnd) = _dateRange(0, year);

    // Fetch once with the full year range (superset of month range).
    final allRecords = await _fetchGuestRecordsOnline(
      businessId: businessId,
      startDate: yearStart,
      endDate: yearEnd,
    );

    // Filter month records client-side to avoid a second API call.
    final periodStart = DateTime.parse(start);
    final periodEnd = DateTime.parse(end);
    final periodRecords = (month == 0)
        ? allRecords
        : allRecords.where((r) {
            final d = _stringValue(r, 'check_in');
            if (d == null) return false;
            final dt = DateTime.tryParse(d);
            return dt != null && !dt.isBefore(periodStart) && !dt.isAfter(periodEnd);
          }).toList();

    final yearRecords = allRecords;

    final stats = _computeStats(
      periodRecords: periodRecords,
      yearRecords: yearRecords,
      totalRooms: totalRooms,
    );

    final recordIds = periodRecords
        .map((r) => _stringValue(r, 'id'))
        .whereType<String>()
        .toList();

    final breakdowns = await _fetchBreakdownsOnline(recordIds);

    return _computeDashboardData(
      stats: stats,
      breakdowns: breakdowns,
      periodRecords: periodRecords,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchGuestRecordsOnline({
    required String businessId,
    required String startDate,
    required String endDate,
  }) async {
    final response = await get('/api/dashboard/guest-records?businessId=$businessId&startDate=$startDate&endDate=$endDate');
    return List<Map<String, dynamic>>.from(handleResponse(response) as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdownsOnline(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return [];
    final idsParam = recordIds.join(',');
    final response = await get('/api/dashboard/breakdowns?recordIds=$idsParam');
    return List<Map<String, dynamic>>.from(handleResponse(response) as List? ?? []);
  }

  // ===========================================================================
  // OFFLINE — read from SQLite
  // ===========================================================================

  Future<DashboardData> _fetchDashboardDataOffline({
    required String businessId,
    required int totalRooms,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final (yearStart, yearEnd) = _dateRange(0, year);

    // Fetch once with the full year range (superset of month range).
    final allRecords = await _fetchGuestRecordsOffline(
      businessId: businessId,
      startDate: yearStart,
      endDate: yearEnd,
    );

    // Filter month records client-side to avoid a second DB query.
    final periodStart = DateTime.parse(start);
    final periodEnd = DateTime.parse(end);
    final periodRecords = (month == 0)
        ? allRecords
        : allRecords.where((r) {
            final d = _stringValue(r, 'check_in');
            if (d == null) return false;
            final dt = DateTime.tryParse(d);
            return dt != null && !dt.isBefore(periodStart) && !dt.isAfter(periodEnd);
          }).toList();

    final yearRecords = allRecords;

    final stats = _computeStats(
      periodRecords: periodRecords,
      yearRecords: yearRecords,
      totalRooms: totalRooms,
    );

    final recordIds = periodRecords
        .map((r) => _stringValue(r, 'id'))
        .whereType<String>()
        .toList();

    final breakdowns = await _fetchBreakdownsOffline(recordIds);

    return _computeDashboardData(
      stats: stats,
      breakdowns: breakdowns,
      periodRecords: periodRecords,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchGuestRecordsOffline({
    required String businessId,
    required String startDate,
    required String endDate,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableGuestRecords,
      columns: [
        'id',
        'check_in',
        'check_out',
        'total_guests',
        'rooms_occupied',
        'purpose_of_visit',
      ],
      where:
          'business_id = ? AND is_deleted = 0  '
          'AND check_in >= ? AND check_in <= ?',
      whereArgs: [businessId, startDate, endDate],
    );
    // Convert Map<String, Object?> to Map<String, dynamic>
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdownsOffline(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return [];

    final db = await LocalDatabase.instance.database;

    // SQLite doesn't support inFilter so we build a placeholder string.
    final placeholders = recordIds.map((_) => '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT guest_record_id, country, philippines_region, sex, age_group, count '
      'FROM ${LocalDatabase.tableGuestBreakdowns} '
      'WHERE guest_record_id IN ($placeholders)',
      recordIds,
    );

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ===========================================================================
  // SHARED — pure computation (same logic for online and offline)
  // ===========================================================================

  DashboardStats _computeStats({
    required List<Map<String, dynamic>> periodRecords,
    required List<Map<String, dynamic>> yearRecords,
    required int totalRooms,
  }) {
    final guestsThisMonth = periodRecords.fold<int>(
      0,
      (s, r) => s + ((_intValue(r, 'total_guests')) ?? 0),
    );
    final guestsThisYear = yearRecords.fold<int>(
      0,
      (s, r) => s + ((_intValue(r, 'total_guests')) ?? 0),
    );

    double avgStay = 0;
    if (periodRecords.isNotEmpty) {
      double totalNights = 0;
      int totalGuests = 0;

      for (final r in periodRecords) {
        final checkInText = _stringValue(r, 'check_in');
        final checkOutText = _stringValue(r, 'check_out');
        if (checkInText == null || checkOutText == null) continue;
        final checkIn = DateTime.tryParse(checkInText);
        final checkOut = DateTime.tryParse(checkOutText);
        if (checkIn == null || checkOut == null) continue;

        final nights = checkOut.difference(checkIn).inDays;
        final guestCount = (_intValue(r, 'total_guests')) ?? 0;

        totalNights += nights * guestCount; // weight by guests
        totalGuests += guestCount; // count persons, not bookings
      }

      if (totalGuests > 0) avgStay = totalNights / totalGuests;
    }

    return DashboardStats(
      guestsThisMonth: guestsThisMonth,
      guestsThisYear: guestsThisYear,
      avgLengthOfStay: avgStay,
      totalRooms: totalRooms,
    );
  }

  DashboardData _computeDashboardData({
    required DashboardStats stats,
    required List<Map<String, dynamic>> breakdowns,
    required List<Map<String, dynamic>> periodRecords,
  }) {
    // Sex distribution
    int male = 0, female = 0, genderOther = 0;
    for (final b in breakdowns) {
      final sex = _stringValue(b, 'sex')?.toLowerCase() ?? '';
      final cnt = (_intValue(b, 'count')) ?? 0;
      if (sex == 'male') {
        male += cnt;
      } else if (sex == 'female') {
        female += cnt;
      } else {
        genderOther += cnt;
      }
    }

    // Age group distribution
    final ageGroupMap = <String, int>{};
    for (final b in breakdowns) {
      final ageGroup = _stringValue(b, 'age_group')?.trim() ?? '';
      if (ageGroup.isEmpty) continue;
      ageGroupMap[ageGroup] =
          (ageGroupMap[ageGroup] ?? 0) + ((_intValue(b, 'count')) ?? 0);
    }
    final ageGroups =
        ageGroupMap.entries
            .map((e) => AgeGroupCount(ageGroup: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    // Top 5 countries
    final countryMap = <String, int>{};
    for (final b in breakdowns) {
      final country = _stringValue(b, 'country') ?? 'Unknown';
      countryMap[country] =
          (countryMap[country] ?? 0) + ((_intValue(b, 'count')) ?? 0);
    }
    final topCountries =
        (countryMap.entries
                .map((e) => CountryCount(country: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    // Top 5 local regions
    final regionMap = <String, int>{};
    for (final b in breakdowns) {
      final region = _stringValue(b, 'philippines_region');
      if (region != null && region.isNotEmpty) {
        regionMap[region] =
            (regionMap[region] ?? 0) + ((_intValue(b, 'count')) ?? 0);
      }
    }
    final topRegions =
        (regionMap.entries
                .map((e) => RegionCount(region: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    // Purpose of visit
    final purposeMap = <String, int>{};
    for (final record in periodRecords) {
      final purpose = _stringValue(record, 'purpose_of_visit')?.trim() ?? '';
      if (purpose.isEmpty) continue;
      purposeMap[purpose] =
          (purposeMap[purpose] ?? 0) + ((_intValue(record, 'total_guests')) ?? 0);
    }
    final purposeOfVisit =
        (purposeMap.entries
                .map((e) => PurposeCount(purpose: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    return DashboardData(
      stats: stats,
      sexDistribution: SexDistribution(
        male: male,
        female: female,
        other: genderOther,
      ),
      topCountries: topCountries,
      topRegions: topRegions,
      ageGroups: ageGroups,
      purposeOfVisit: purposeOfVisit,
    );
  }

  // ===========================================================================
  // PUBLIC — fetchYearlyComparison
  // ===========================================================================

  Future<Map<int, List<MonthlyCount>>> fetchYearlyComparison({
    required String businessId,
    required List<int> years,
    bool preferOnline = false,
  }) async {
    final tryOnline = (preferOnline || ConnectivityService.instance.isOnline) && hasToken;

    if (tryOnline) {
      try {
        return await _fetchYearlyComparisonOnline(
          businessId: businessId,
          years: years,
        );
      } catch (_) {
        // Reconnect policy: fallback to SQLite immediately.
      }
    }

    return _fetchYearlyComparisonOffline(
      businessId: businessId,
      years: years,
    );
  }

  Future<Map<int, List<MonthlyCount>>> _fetchYearlyComparisonOnline({
    required String businessId,
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchGuestRecordsOnline(
        businessId: businessId,
        startDate: start,
        endDate: end,
      );
      result[year] = _recordsToMonthly(records);
    }

    return result;
  }

  Future<Map<int, List<MonthlyCount>>> _fetchYearlyComparisonOffline({
    required String businessId,
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchGuestRecordsOffline(
        businessId: businessId,
        startDate: start,
        endDate: end,
      );
      result[year] = _recordsToMonthly(records);
    }

    return result;
  }

  List<MonthlyCount> _recordsToMonthly(List<Map<String, dynamic>> records) {
    final monthMap = <int, int>{};
    for (final r in records) {
      final checkInText = _stringValue(r, 'check_in');
      if (checkInText == null) continue;
      final parsed = DateTime.tryParse(checkInText);
      if (parsed == null) continue;
      final m = parsed.month;
      monthMap[m] = (monthMap[m] ?? 0) + ((_intValue(r, 'total_guests')) ?? 0);
    }
    return List.generate(
      12,
      (i) => MonthlyCount(month: i + 1, count: monthMap[i + 1] ?? 0),
    );
  }

  // ===========================================================================
  // PUBLIC — generateCsv
  // ===========================================================================

  Future<String> generateCsv({
    required String businessId,
    required String businessName,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);

    final records = ConnectivityService.instance.isOnline
        ? await _fetchGuestRecordsOnline(
            businessId: businessId,
            startDate: start,
            endDate: end,
          )
        : await _fetchGuestRecordsOffline(
            businessId: businessId,
            startDate: start,
            endDate: end,
          );

    final recordIds = records
        .map((r) => _stringValue(r, 'id'))
        .whereType<String>()
        .toList();

    final breakdowns = ConnectivityService.instance.isOnline
        ? await _fetchBreakdownsOnline(recordIds)
        : await _fetchBreakdownsOffline(recordIds);

    final recordMap = <String, Map<String, dynamic>>{
      for (final r in records)
        if (_stringValue(r, 'id') case final id?) id: r,
    };

    final buf = StringBuffer()
      ..writeln('Business,$businessName')
      ..writeln('Period,${month == 0 ? 'Full Year' : _monthName(month)} $year')
      ..writeln()
      ..writeln(
        'Check In,Check Out,Total Guests,Rooms Occupied,'
        'Country,Region,Sex,Age Group,Count',
      );

    for (final b in breakdowns) {
      final recordId = _stringValue(b, 'guest_record_id');
      if (recordId == null) continue;
      final rec = recordMap[recordId];
      if (rec == null) continue;
      final row = [
        _stringValue(rec, 'check_in') ?? '',
        _stringValue(rec, 'check_out') ?? '',
        _intValue(rec, 'total_guests') ?? 0,
        _intValue(rec, 'rooms_occupied') ?? 0,
        _csvCell(_stringValue(b, 'country') ?? 'Unknown'),
        _csvCell(_stringValue(b, 'philippines_region') ?? ''),
        _stringValue(b, 'sex') ?? '',
        _stringValue(b, 'age_group') ?? '',
        _intValue(b, 'count') ?? 0,
      ];
      buf.writeln(row.join(','));
    }

    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String? _stringValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value == null ? null : value.toString();
  }

  int? _intValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _csvCell(String value) => value.contains(',') ? '"$value"' : value;

  String _monthName(int month) => const [
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
  ][month];
}
