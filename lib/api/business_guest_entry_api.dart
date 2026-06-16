import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

class GuestEntryResult {
  final bool success;
  final String? error;
  final bool syncedToCloud; // true only when cloud API confirmed the write

  const GuestEntryResult._({
    required this.success,
    this.error,
    this.syncedToCloud = false,
  });

  factory GuestEntryResult.ok({bool syncedToCloud = false}) =>
      GuestEntryResult._(success: true, syncedToCloud: syncedToCloud);

  factory GuestEntryResult.err(String error) =>
      GuestEntryResult._(success: false, error: error);
}

class GuestBreakdownData {
  const GuestBreakdownData({
    this.country,
    this.philippinesRegion,
    this.nationality,
    required this.sex,
    required this.ageGroup,
    required this.count,
    required this.isOverseas,
  });

  final String? country;
  final String? philippinesRegion;
  final String? nationality;
  final String sex;
  final String ageGroup;
  final int count;
  final bool isOverseas;
}

class GuestEntryData {
  const GuestEntryData({
    required this.businessId,
    required this.checkIn,
    required this.checkOut,
    required this.totalGuests,
    required this.roomsOccupied,
    required this.purposeOfVisit,
    required this.transportationMode,
    required this.breakdowns,
  });

  final String businessId;
  final DateTime checkIn;
  final DateTime checkOut;
  final int totalGuests;
  final int roomsOccupied;
  final String purposeOfVisit;
  final String transportationMode;
  final List<GuestBreakdownData> breakdowns;
}

class BusinessGuestEntryApi extends BaseApi {
  // ── Fetch business ID ──────────────────────────────────────────────────────
  // Online  → ask Cloud API.
  // Offline → read from cached session (already populated at login time).

  Future<String?> fetchBusinessId() async {
    // Both online and offline we can rely on the cached session for businessId
    return SessionService.instance.current?.businessId;
  }

  // ── Save guest entry + breakdowns ──────────────────────────────────────────

  Future<GuestEntryResult> saveGuestEntry(GuestEntryData data) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      return _saveOnline(data);
    } else {
      return _saveOffline(data);
    }
  }

  // ---------------------------------------------------------------------------
  // ONLINE — push to Node API, then mirror to SQLite as 'synced'.
  // ---------------------------------------------------------------------------
  Future<GuestEntryResult> _saveOnline(GuestEntryData data) async {
    final guestRecordId = _generateId();
    final checkInStr  = _formatDate(data.checkIn);
    final checkOutStr = _formatDate(data.checkOut);
    final now         = DateTime.now().toUtc().toIso8601String();

    // ── Step 1: SQLite first (safe local copy, pending_create) ───────────────
    if (!kIsWeb) {
      try {
        await _upsertLocalRecord(
          recordId:           guestRecordId,
          businessId:         data.businessId,
          checkIn:            checkInStr,
          checkOut:           checkOutStr,
          totalGuests:        data.totalGuests,
          roomsOccupied:      data.roomsOccupied,
          purposeOfVisit:     data.purposeOfVisit,
          transportationMode: data.transportationMode,
          createdAt:          now,
          syncStatus:         LocalDatabase.syncPendingCreate,
          localUpdatedAt:     now,
        );
        await _upsertLocalBreakdowns(guestRecordId, data.breakdowns);
      } catch (e) {
        debugPrint('❌ _saveOnline: local write failed — $e');
        return GuestEntryResult.err('Failed to save guest entry. Please try again.');
      }
    }

    // ── Step 2: Push to Node API ─────────────────────────────────────────────
    try {
      final payload = {
        'id': guestRecordId,
        'businessId': data.businessId,
        'checkIn': checkInStr,
        'checkOut': checkOutStr,
        'totalGuests': data.totalGuests,
        'roomsOccupied': data.roomsOccupied,
        'purposeOfVisit': data.purposeOfVisit,
        'transportationMode': data.transportationMode,
        'breakdowns': data.breakdowns.map((b) => {
          'isOverseas': b.isOverseas,
          'country': b.country,
          'nationality': b.nationality,
          'philippinesRegion': b.philippinesRegion,
          'sex': _mapSex(b.sex),
          'ageGroup': _mapAgeGroup(b.ageGroup),
          'count': b.count,
        }).toList(),
      };

      final response = await post('/api/business/guest-entries', payload);

      if (response.statusCode != 201) {
        throw Exception('Failed to save to cloud: ${response.body}');
      }

      // ── Step 3: Mark synced in SQLite ──────────────────────────────────────
      if (!kIsWeb) {
        final db = await LocalDatabase.instance.database;
        await db.update(
          LocalDatabase.tableGuestRecords,
          {
            'sync_status':      LocalDatabase.syncSynced,
            'local_updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where:     'id = ?',
          whereArgs: [guestRecordId],
        );
      }

      return GuestEntryResult.ok(syncedToCloud: true);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        debugPrint('⚠️ _saveOnline: Unauthorized (401). Queuing for sync.');
        return GuestEntryResult.ok(syncedToCloud: false);
      }
      // API failed — record stays pending_create; SyncService will retry.
      debugPrint('⚠️ _saveOnline: Node API request failed, queued for sync — $e');
      return GuestEntryResult.ok(syncedToCloud: false);
    }
  }

  // ---------------------------------------------------------------------------
  // OFFLINE — write only to SQLite, tagged as 'pending_create'.
  // SyncService will push this to Node API when back online.
  // ---------------------------------------------------------------------------
  Future<GuestEntryResult> _saveOffline(GuestEntryData data) async {
    try {
      final guestRecordId = _generateId();
      final checkInStr    = _formatDate(data.checkIn);
      final checkOutStr   = _formatDate(data.checkOut);
      final now           = DateTime.now().toUtc().toIso8601String();

      await _upsertLocalRecord(
        recordId:           guestRecordId,
        businessId:         data.businessId,
        checkIn:            checkInStr,
        checkOut:           checkOutStr,
        totalGuests:        data.totalGuests,
        roomsOccupied:      data.roomsOccupied,
        purposeOfVisit:     data.purposeOfVisit,
        transportationMode: data.transportationMode,
        createdAt:          now,
        syncStatus:         LocalDatabase.syncPendingCreate,
        localUpdatedAt:     now,
      );
      await _upsertLocalBreakdowns(guestRecordId, data.breakdowns);

      return GuestEntryResult.ok();
    } catch (e) {
      debugPrint('❌ saveGuestEntry (offline) error: $e');
      return GuestEntryResult.err('Failed to save guest entry locally. Please try again.');
    }
  }

  // ---------------------------------------------------------------------------
  // SQLite helpers
  // ---------------------------------------------------------------------------

  Future<void> _upsertLocalRecord({
    required String recordId,
    required String businessId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    required int roomsOccupied,
    required String purposeOfVisit,
    required String transportationMode,
    required String? createdAt,
    required String syncStatus,
    required String? localUpdatedAt,
  }) async {
    final db = await LocalDatabase.instance.database;
    final current = SessionService.instance.current;
    
    // Ensure the profile and business exist locally to satisfy foreign key constraints
    if (current != null) {
      await db.insert(
        LocalDatabase.tableLocalProfiles,
        {
          'id': current.userId,
          'username': current.username ?? current.email,
          'full_name': current.fullName,
          'email': current.email,
          'phone': current.phone,
          'role': current.role,
          'password_hash': 'temp_hash',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      
      await db.insert(
        LocalDatabase.tableLocalBusinesses,
        {
          'id': businessId,
          'profile_id': current.userId,
          'business_name': current.businessName ?? 'Unknown',
          'status': current.status ?? 'approved',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await db.insert(
      LocalDatabase.tableGuestRecords,
      {
        'id':                  recordId,
        'business_id':         businessId,
        'check_in':            checkIn,
        'check_out':           checkOut,
        'total_guests':        totalGuests,
        'rooms_occupied':      roomsOccupied,
        'purpose_of_visit':    purposeOfVisit,
        'transportation_mode': transportationMode,
        'status':              'active',
        'is_deleted':          0,
        'created_at':          createdAt,
        'sync_status':         syncStatus,
        'local_updated_at':    localUpdatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('💾 SQLite: saved record $recordId (status: $syncStatus, business: $businessId)');
  }

  Future<void> _upsertLocalBreakdowns(
    String recordId,
    List<GuestBreakdownData> breakdowns,
  ) async {
    final db = await LocalDatabase.instance.database;

    // Delete old ones first (safe on first insert too — nothing to delete)
    await db.delete(
      LocalDatabase.tableGuestBreakdowns,
      where: 'guest_record_id = ?',
      whereArgs: [recordId],
    );

    for (final b in breakdowns) {
      await db.insert(
        LocalDatabase.tableGuestBreakdowns,
        {
          'id':                 _generateId(),
          'guest_record_id':    recordId,
          'country':            b.country,
          'philippines_region': b.philippinesRegion,
          'nationality':        b.nationality,
          'sex':                _mapSex(b.sex),
          'age_group':          _mapAgeGroup(b.ageGroup),
          'count':              b.count,
          'is_overseas':        b.isOverseas ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Generates a UUID v4-like string without any extra package.
  // ---------------------------------------------------------------------------
  String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  // ---------------------------------------------------------------------------
  // Value mappers (unchanged from original)
  // ---------------------------------------------------------------------------

  String _mapSex(String sex) {
    switch (sex.toLowerCase()) {
      case 'male':   return 'male';
      case 'female': return 'female';
      default:       return 'male';
    }
  }

  String _mapAgeGroup(String ageGroup) {
    switch (ageGroup) {
      case '0–9':               return '0-9';
      case '10–17':             return '10-17';
      case '18–25':             return '18-25';
      case '26–35':             return '26-35';
      case '36–45':             return '36-45';
      case '46–55':             return '46-55';
      case '56+':               return '56+';
      case 'Prefer not to say': return 'prefer_not_to_say';
      default:                  return 'prefer_not_to_say';
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
