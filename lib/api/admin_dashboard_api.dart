// ignore_for_file: inference_failure_on_function_invocation

import 'dart:convert';
import 'base_api.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class AdminDashboardStats {
  const AdminDashboardStats({
    required this.activeAccommodations,
    required this.touristsThisPeriod,
    required this.pendingRegistrations,
    required this.touristsThisYear,
  });

  final int activeAccommodations;
  final int touristsThisPeriod;
  final int pendingRegistrations;
  final int touristsThisYear;
}

typedef DashboardStats = AdminDashboardStats;

class GenderDistribution {
  const GenderDistribution({
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

typedef SexDistribution = GenderDistribution;

class AgeGroupCount {
  const AgeGroupCount({required this.ageGroup, required this.count});

  final String ageGroup;
  final int count;
}

class NationalityCount {
  const NationalityCount({required this.nationality, required this.count});

  final String nationality;
  final int count;
}

typedef CountryCount = NationalityCount;

class TransportCount {
  const TransportCount({required this.mode, required this.count});

  final String mode;
  final int count;
}

class RegionCount {
  const RegionCount({required this.region, required this.count});

  final String region;
  final int count;
}

class AccommodationTypeCount {
  const AccommodationTypeCount({required this.type, required this.count});

  final String type;
  final int count;
}

class PurposeCount {
  const PurposeCount({required this.purpose, required this.count});

  final String purpose;
  final int count;
}

class ComplianceData {
  const ComplianceData({required this.compliant, required this.nonCompliant});

  final int compliant;
  final int nonCompliant;

  double get rate {
    final total = compliant + nonCompliant;
    return total == 0 ? 0 : compliant / total;
  }
}

class AdminDashboardData {
  const AdminDashboardData({
    required this.stats,
    required this.genderDistribution,
    required this.ageGroups,
    required this.topNationalities,
    required this.transportModes,
    required this.compliance,
    required this.topRegions,
    required this.accommodationTypes,
    required this.purposeOfVisit,
  });

  final AdminDashboardStats stats;
  final GenderDistribution genderDistribution;
  final List<AgeGroupCount> ageGroups;
  final List<NationalityCount> topNationalities;
  final List<TransportCount> transportModes;
  final ComplianceData compliance;
  final List<RegionCount> topRegions;
  final List<AccommodationTypeCount> accommodationTypes;
  final List<PurposeCount> purposeOfVisit;
}

typedef DashboardData = AdminDashboardData;

class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.role,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String role;

  String get displayLabel => '$fullName • Admin';
}

class MonthlyCount {
  const MonthlyCount({required this.month, required this.count});

  final int month; // 1–12
  final int count;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class AdminDashboardApi extends BaseApi {
  (String start, String end) _dateRange(int month, int year) {
    if (month == 0) {
      return ('$year-01-01', '$year-12-31');
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final mm = month.toString().padLeft(2, '0');
    final dd = lastDay.toString().padLeft(2, '0');
    return ('$year-$mm-01', '$year-$mm-$dd');
  }

  Future<AdminProfile?> fetchAdminProfile(String adminId) async {
    final response = await get('/api/profile');
    final data = handleResponse(response);

    if (data != null && data['user'] != null) {
      final user = data['user'];
      return AdminProfile(
        id: user['id'].toString(),
        fullName: (user['full_name'] as String?) ?? '',
        phone: (user['phone'] as String?) ?? '',
        email: (user['email'] as String?) ?? '',
        role: (user['role'] as String?) ?? 'admin',
      );
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchGuestRecords({
    required String startDate,
    required String endDate,
  }) async {
    final response = await get(
      '/api/dashboard/guest-records?startDate=$startDate&endDate=$endDate',
    );
    final data = handleResponse(response);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdowns(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return [];
    final response = await get(
      '/api/dashboard/breakdowns?recordIds=${recordIds.join(',')}',
    );
    final data = handleResponse(response);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<Map<String, int>> _fetchStats() async {
    final response = await get('/api/dashboard/stats');
    final data = handleResponse(response);
    return {
      'active': (data['activeAccommodations'] as num).toInt(),
      'pending': (data['pendingRegistrations'] as num).toInt(),
    };
  }

  List<String> _extractBusinessLines(Object? value) {
    if (value == null) return const [];
    
    List<dynamic> raw = [];
    if (value is List) {
      raw = value;
    } else if (value is String) {
      if (value.startsWith('[')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) raw = decoded;
        } catch (_) {}
      } else {
        return value.split(RegExp(r'[,|\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).map(_toTitleCase).toList();
      }
    }

    return raw.map((e) => (e?.toString() ?? '').trim()).where((e) => e.isNotEmpty).map(_toTitleCase).toList();
  }

  Future<List<AccommodationTypeCount>> _fetchAccommodationTypes(
    List<Map<String, dynamic>> periodRecords,
  ) async {
    final businessIds =
        periodRecords
            .map((record) => record['business_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
    if (businessIds.isEmpty) return const [];

    final response = await get(
      '/api/dashboard/business-lines?businessIds=${businessIds.join(',')}',
    );
    final data = handleResponse(response);
    final businesses = List<Map<String, dynamic>>.from(data as List);

    final linesByBusiness = <String, List<String>>{};
    for (final business in businesses) {
      final id = business['id'].toString();
      linesByBusiness[id] = _extractBusinessLines(business['business_line']);
    }

    final typeMap = <String, int>{};

    for (final record in periodRecords) {
      final businessId = record['business_id']?.toString();
      final lines = linesByBusiness[businessId] ?? const [];
      if (lines.isEmpty) continue;

      final guestCount = (record['total_guests'] as num?)?.toInt() ?? 0;
      for (final type in lines) {
        typeMap[type] = (typeMap[type] ?? 0) + guestCount;
      }
    }

    return typeMap.entries
        .map((e) => AccommodationTypeCount(type: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  Future<AdminDashboardData> fetchDashboardData({
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final (yearStart, yearEnd) = _dateRange(0, year);

    final response = await get(
      '/api/dashboard/summary?startDate=$start&endDate=$end&yearStart=$yearStart&yearEnd=$yearEnd',
    );
    final data = handleResponse(response);

    final periodRecords =
        List<Map<String, dynamic>>.from(data['periodRecords'] as List);
    final yearRecords =
        List<Map<String, dynamic>>.from(data['yearRecords'] as List);

    final touristsThisPeriod = periodRecords.fold<int>(
      0,
      (s, r) => s + (r['total_guests'] as int),
    );
    final touristsThisYear = yearRecords.fold<int>(
      0,
      (s, r) => s + (r['total_guests'] as int),
    );

    final stats = data['stats'] as Map<String, dynamic>;
    final activeAccommodations = (stats['activeAccommodations'] as num).toInt();
    final pendingRegistrations = (stats['pendingRegistrations'] as num).toInt();

    final breakdowns =
        List<Map<String, dynamic>>.from(data['breakdowns'] as List);

    int male = 0, female = 0, other = 0;
    for (final breakdown in breakdowns) {
      final sex = (breakdown['sex'] as String? ?? '').toLowerCase();
      final count = breakdown['count'] as int? ?? 0;
      if (sex == 'male') {
        male += count;
      } else if (sex == 'female') {
        female += count;
      } else {
        other += count;
      }
    }

    final ageGroupMap = <String, int>{};
    for (final breakdown in breakdowns) {
      final ageGroup = (breakdown['age_group'] as String? ?? '').trim();
      if (ageGroup.isEmpty) continue;
      final label = _toTitleCase(ageGroup);
      ageGroupMap[label] =
          (ageGroupMap[label] ?? 0) + (breakdown['count'] as int? ?? 0);
    }
    final ageGroups =
        ageGroupMap.entries
            .map((e) => AgeGroupCount(ageGroup: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    final nationalityMap = <String, int>{};
    for (final breakdown in breakdowns) {
      final country = (breakdown['country'] as String? ?? '').trim();
      if (country.isEmpty) continue;
      final label = _toTitleCase(country);
      nationalityMap[label] =
          (nationalityMap[label] ?? 0) + (breakdown['count'] as int? ?? 0);
    }
    final topNationalities =
        (nationalityMap.entries
                .map(
                  (entry) => NationalityCount(
                    nationality: entry.key,
                    count: entry.value,
                  ),
                )
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    final regionMap = <String, int>{};
    for (final breakdown in breakdowns) {
      final region = (breakdown['philippines_region'] as String? ?? '').trim();
      if (region.isEmpty) continue;
      final label = _toTitleCase(region);
      regionMap[label] =
          (regionMap[label] ?? 0) + (breakdown['count'] as int? ?? 0);
    }
    final topRegions =
        (regionMap.entries
                .map(
                  (entry) => RegionCount(region: entry.key, count: entry.value),
                )
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    final purposeMap = <String, int>{};
    for (final record in periodRecords) {
      final purpose = (record['purpose_of_visit'] as String? ?? '').trim();
      if (purpose.isEmpty) continue;
      final label = _toTitleCase(purpose);
      purposeMap[label] =
          (purposeMap[label] ?? 0) + (record['total_guests'] as int? ?? 0);
    }
    final purposeOfVisit =
        (purposeMap.entries
                .map((e) => PurposeCount(purpose: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    final businessLines =
        List<Map<String, dynamic>>.from(data['businessLines'] as List);
    final linesByBusiness = <String, List<String>>{};
    for (final business in businessLines) {
      final id = business['id'].toString();
      linesByBusiness[id] = _extractBusinessLines(business['business_line']);
    }
    final typeMap = <String, int>{};
    for (final record in periodRecords) {
      final businessId = record['business_id']?.toString();
      final lines = linesByBusiness[businessId] ?? const [];
      if (lines.isEmpty) continue;
      final guestCount = (record['total_guests'] as num?)?.toInt() ?? 0;
      for (final type in lines) {
        typeMap[type] = (typeMap[type] ?? 0) + guestCount;
      }
    }
    final accommodationTypes = typeMap.entries
        .map((e) => AccommodationTypeCount(type: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return AdminDashboardData(
      stats: AdminDashboardStats(
        activeAccommodations: activeAccommodations,
        touristsThisPeriod: touristsThisPeriod,
        pendingRegistrations: pendingRegistrations,
        touristsThisYear: touristsThisYear,
      ),
      genderDistribution: GenderDistribution(
        male: male,
        female: female,
        other: other,
      ),
      ageGroups: ageGroups,
      topNationalities: topNationalities,
      transportModes: const [],
      compliance: ComplianceData(
        compliant: activeAccommodations,
        nonCompliant: pendingRegistrations,
      ),
      topRegions: topRegions,
      accommodationTypes: accommodationTypes,
      purposeOfVisit: purposeOfVisit,
    );
  }

  Future<Map<int, List<MonthlyCount>>> fetchYearlyComparison({
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchGuestRecords(startDate: start, endDate: end);

      final monthMap = <int, int>{};
      for (final record in records) {
        final month = DateTime.parse(record['check_in'] as String).month;
        monthMap[month] =
            (monthMap[month] ?? 0) + (record['total_guests'] as int);
      }

      result[year] = List.generate(
        12,
        (index) =>
            MonthlyCount(month: index + 1, count: monthMap[index + 1] ?? 0),
      );
    }

    return result;
  }

  Future<String> generateCsv({
    required String businessName,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final records = await _fetchGuestRecords(startDate: start, endDate: end);
    final recordIds = records.map((record) => record['id'].toString()).toList();
    final breakdowns = await _fetchBreakdowns(recordIds);

    final recordMap = {
      for (final record in records) record['id'].toString(): record,
    };

    final buffer = StringBuffer()
      ..writeln('Business,$businessName')
      ..writeln('Period,${month == 0 ? 'Full Year' : _monthName(month)} $year')
      ..writeln()
      ..writeln(
        'Check In,Check Out,Total Guests,Rooms Occupied,'
        'Country,Region,Sex,Age Group,Count',
      );

    for (final breakdown in breakdowns) {
      final record = recordMap[breakdown['guest_record_id'].toString()];
      if (record == null) continue;
      final row = [
        record['check_in'],
        record['check_out'],
        record['total_guests'],
        record['rooms_occupied'],
        _csvCell(breakdown['country'] as String? ?? ''),
        _csvCell(breakdown['philippines_region'] as String? ?? ''),
        breakdown['sex'],
        breakdown['age_group'],
        breakdown['count'],
      ];
      buffer.writeln(row.join(','));
    }

    return buffer.toString();
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

  String _toTitleCase(String s) => s
      .split('_')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
