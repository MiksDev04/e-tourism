// lib/api/admin_accommodation_api.dart

import 'package:flutter/foundation.dart';
import 'package:app/api/base_api.dart';
import 'package:app/ui/admin/models/accommodation_models.dart';

// ─── Result wrapper ───────────────────────────────────────────────────────────

class AccommodationResult {
  final bool success;
  final String? error;

  const AccommodationResult._({required this.success, this.error});
  factory AccommodationResult.ok() =>
      const AccommodationResult._(success: true);
  factory AccommodationResult.err(String error) =>
      AccommodationResult._(success: false, error: error);
}

// ─── Export row model ─────────────────────────────────────────────────────────

class AccommodationExportRow {
  const AccommodationExportRow({
    required this.businessName,
    required this.tradeName,
    required this.businessLine,
    required this.businessType,
    required this.ownerFirstName,
    required this.ownerMiddleName,
    required this.ownerLastName,
    required this.street,
    required this.region,
    required this.province,
    required this.cityMunicipality,
    required this.barangay,
    required this.phone,
  });

  final String businessName;
  final String tradeName;
  final String businessLine;
  final String businessType;
  final String ownerFirstName;
  final String ownerMiddleName;
  final String ownerLastName;
  final String street;
  final String region;
  final String province;
  final String cityMunicipality;
  final String barangay;
  final String phone;
}

// ─── Ranking row model ────────────────────────────────────────────────────────

class AccommodationRankingRow {
  const AccommodationRankingRow({
    required this.businessId,
    required this.businessName,
    required this.totalGuests,
    required this.rank,
  });

  final String businessId;
  final String businessName;
  final int totalGuests;
  final int rank;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class AdminAccommodationApi extends BaseApi {
  // ── Fetch paginated businesses with joined profile ──────────────────────
  Future<({
    List<Accommodation> data,
    int totalCount,
    int pageCount,
    int? approvedCount,
    int? pendingCount,
    int? rejectedCount,
    int? warningCount,
  })> fetchAll({
    int page = 1,
    int pageSize = 10,
    String? status,
    String? searchQuery,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (status != null && status != 'all') queryParams['status'] = status;
      if (searchQuery != null && searchQuery.isNotEmpty) queryParams['search'] = searchQuery;

      final uri = Uri.parse('/api/admin/accommodations').replace(queryParameters: queryParams);
      final response = await get(uri.toString());
      final body = handleResponse(response);
      final list = body['data'] as List;
      final totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
      final pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;
      final approvedCount = (body['approvedCount'] as num?)?.toInt();
      final pendingCount = (body['pendingCount'] as num?)?.toInt();
      final rejectedCount = (body['rejectedCount'] as num?)?.toInt();
      final warningCount = (body['warningCount'] as num?)?.toInt();
      final data = list
          .map((e) => Accommodation.fromMap(e as Map<String, dynamic>))
          .toList();
      return (
        data: data,
        totalCount: totalCount,
        pageCount: pageCount,
        approvedCount: approvedCount,
        pendingCount: pendingCount,
        rejectedCount: rejectedCount,
        warningCount: warningCount,
      );
    } catch (e) {
      debugPrint('❌ fetchAll error: $e');
      rethrow;
    }
  }

  // ── Fetch total count for a single status ──────────────────────────────
  Future<int> fetchStatusCount(String status) async {
    try {
      final response = await get(
        '/api/admin/accommodations?page=1&pageSize=1&status=$status',
      );
      final body = handleResponse(response);
      return (body['totalCount'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('❌ fetchStatusCount error: $e');
      return 0;
    }
  }

  // ── Fetch rows formatted for export ───────────────────────────────────────
  Future<List<AccommodationExportRow>> fetchExportRows() async {
    try {
      final response = await get('/api/admin/accommodations/export');
      final body = handleResponse(response);
      final list = body['data'] as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;

        final phone = m['phone'] as String? ?? '';

        final rawLines = m['business_line'];
        final businessLine = rawLines is List
            ? rawLines.map((l) => _toTitleCase(l.toString())).join(', ')
            : '';

        return AccommodationExportRow(
          businessName: _val(m['business_name']),
          tradeName: _val(m['tradename']),
          businessLine: businessLine.isEmpty ? '—' : businessLine,
          businessType: _toTitleCase(m['business_type'] as String? ?? ''),
          ownerFirstName: _val(m['owner_first_name']),
          ownerMiddleName: _val(m['owner_middle_name']),
          ownerLastName: _val(m['owner_last_name']),
          street: _val(m['street']),
          region: _val(m['region']),
          province: _val(m['province']),
          cityMunicipality: _val(m['city_municipality']),
          barangay: _val(m['barangay']),
          phone: phone.trim().isEmpty ? '—' : phone.trim(),
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ fetchExportRows error: $e');
      return [];
    }
  }

  // ── Fetch tourist rankings for a given month/year ─────────────────────────
  //
  // Aggregation is now done server-side; the Flutter side receives
  // pre-computed results.
  Future<List<AccommodationRankingRow>> fetchRankings({
    required int month,
    required int year,
  }) async {
    try {
      final response = await get(
        '/api/admin/accommodations/rankings?month=$month&year=$year',
      );
      final body = handleResponse(response);
      final list = body['data'] as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return AccommodationRankingRow(
          businessId: m['business_id'] as String,
          businessName: m['business_name'] as String? ?? '—',
          totalGuests: (m['total_guests'] as num?)?.toInt() ?? 0,
          rank: (m['rank'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ fetchRankings error: $e');
      rethrow;
    }
  }

  // ── Approve ───────────────────────────────────────────────────────────────
  Future<AccommodationResult> approve(
    String businessId, {
    String? remarks,
  }) async {
    try {
      final response = await put(
        '/api/admin/accommodations/$businessId/approve',
        {'remarks': remarks},
      );
      handleResponse(response);
      return AccommodationResult.ok();
    } catch (e) {
      debugPrint('❌ approve error: $e');
      return AccommodationResult.err('Failed to approve. Please try again.');
    }
  }

  // ── Reject ────────────────────────────────────────────────────────────────
  Future<AccommodationResult> reject(
    String businessId, {
    String? remarks,
  }) async {
    try {
      final response = await put(
        '/api/admin/accommodations/$businessId/reject',
        {'remarks': remarks},
      );
      handleResponse(response);
      return AccommodationResult.ok();
    } catch (e) {
      debugPrint('❌ reject error: $e');
      return AccommodationResult.err('Failed to reject. Please try again.');
    }
  }

  // ── Flag as warning ───────────────────────────────────────────────────────
  Future<AccommodationResult> flag(
    String businessId, {
    String? remarks,
  }) async {
    try {
      final response = await put(
        '/api/admin/accommodations/$businessId/flag',
        {'remarks': remarks},
      );
      handleResponse(response);
      return AccommodationResult.ok();
    } catch (e) {
      debugPrint('❌ flag error: $e');
      return AccommodationResult.err('Failed to flag. Please try again.');
    }
  }

  // ── Soft delete ───────────────────────────────────────────────────────────
  // Named deleteAccommodation to avoid conflict with BaseApi.delete()
  Future<AccommodationResult> deleteAccommodation(String businessId) async {
    try {
      final response =
          await super.delete('/api/admin/accommodations/$businessId');
      handleResponse(response);
      return AccommodationResult.ok();
    } catch (e) {
      debugPrint('❌ delete error: $e');
      return AccommodationResult.err('Failed to delete. Please try again.');
    }
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

/// Returns trimmed string or '—' if null/empty.
String _val(dynamic v) {
  final s = (v as String?)?.trim() ?? '';
  return s.isEmpty ? '—' : s;
}

/// Converts snake_case enum string to Title Case.
String _toTitleCase(String s) => s
    .split('_')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');