import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/ui/business/pages/business_guest_records_page.dart';
import 'base_api.dart';

// ─── Result Wrapper ───────────────────────────────────────────────────────────

class ApiResult<T> {
  const ApiResult.success(this.data) : error = null;
  const ApiResult.failure(this.error) : data = null;

  final T? data;
  final String? error;

  bool get isSuccess => error == null;
}

// ─── Business Guest Record API ────────────────────────────────────────────────

class BusinessGuestRecordApi extends BaseApi {
  // ── Fetch Business ID ─────────────────────────────────────────────────────
  //
  // Fallback priority (both online and offline):
  //   1. Node API  (only when online — freshest source of truth)
  //   2. SessionService cache  (always available after any login type)
  //   3. SQLite local_businesses table  (populated by SyncService pull)
  //
  // This triple-fallback means a mid-session connectivity toggle never causes
  // "Business account not found" — we always have at least the cached value.

  Future<String?> fetchBusinessId() async {
    if (!ConnectivityService.instance.isOnline) {
      // ── Offline path ──────────────────────────────────────────────────────
      debugPrint('fetchBusinessId: offline — using local fallbacks');
      return _sessionId() ?? await _localDbId();
    }

    // ── Online path: try HTTP first ────────────────────────────────────
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      final id = data?['business']?['id']?.toString();
      if (id != null) {
        debugPrint('fetchBusinessId: resolved from Node API → $id');
        return id;
      }
      debugPrint(
        'fetchBusinessId: Node API returned null business id — '
        'falling back to local caches',
      );
    } catch (e) {
      debugPrint('fetchBusinessId: Node API threw $e — falling back to local caches');
    }

    // ── Fallback 1: SessionService in-memory cache ─────────────────────────
    final fromSession = _sessionId();
    if (fromSession != null) {
      debugPrint('fetchBusinessId: resolved from SessionService → $fromSession');
      return fromSession;
    }

    // ── Fallback 2: SQLite local_businesses ────────────────────────────────
    final fromDb = await _localDbId();
    debugPrint('fetchBusinessId: resolved from SQLite → $fromDb');
    return fromDb;
  }

  /// Returns the businessId stored in the in-memory session, or null.
  String? _sessionId() => SessionService.instance.current?.businessId;

  /// Returns the first businessId found in the local SQLite businesses table.
  Future<String?> _localDbId() async {
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query(
        LocalDatabase.tableLocalBusinesses,
        columns: ['id'],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['id'] as String?;
    } catch (e) {
      debugPrint('fetchBusinessId (_localDbId): SQLite error — $e');
    }
    return null;
  }

  // ── Fetch All Guest Records for a Business ────────────────────────────────

  Future<ApiResult<List<GuestRecord>>> fetchGuestRecords(
    String businessId,
  ) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _fetchOnline(businessId);
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ fetchGuestRecords: Unauthorized (401). Falling back to local.');
          return _fetchOffline(businessId);
        }
        return ApiResult.failure('Cloud error: ${e.message}');
      } catch (e) {
        debugPrint('⚠️ fetchGuestRecords: Online fetch failed ($e). Falling back to local.');
      }
    }
    return _fetchOffline(businessId);
  }

  // ── Update a Record (stay info + breakdowns) ──────────────────────────────

  Future<ApiResult<void>> updateRecord({
    required String recordId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    required int roomsOccupied,
    required String purposeOfVisit,
    required String transportationMode,
    required List<GuestBreakdownEntry> breakdowns,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _updateOnline(
          recordId:           recordId,
          checkIn:            checkIn,
          checkOut:           checkOut,
          totalGuests:        totalGuests,
          roomsOccupied:      roomsOccupied,
          purposeOfVisit:     purposeOfVisit,
          transportationMode: transportationMode,
          breakdowns:         breakdowns,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          return _updateOffline(
            recordId:           recordId,
            checkIn:            checkIn,
            checkOut:           checkOut,
            totalGuests:        totalGuests,
            roomsOccupied:      roomsOccupied,
            purposeOfVisit:     purposeOfVisit,
            transportationMode: transportationMode,
            breakdowns:         breakdowns,
          );
        }
        return ApiResult.failure('Update failed: ${e.message}');
      } catch (_) {}
    }
    
    return _updateOffline(
      recordId:           recordId,
      checkIn:            checkIn,
      checkOut:           checkOut,
      totalGuests:        totalGuests,
      roomsOccupied:      roomsOccupied,
      purposeOfVisit:     purposeOfVisit,
      transportationMode: transportationMode,
      breakdowns:         breakdowns,
    );
  }

  // ===========================================================================
  // ONLINE — fetch from Node API, then refresh local SQLite cache.
  // ===========================================================================

  Future<ApiResult<List<GuestRecord>>> _fetchOnline(String businessId) async {
    try {
      debugPrint('🔍 _fetchOnline: businessId = $businessId');
      final response = await get('/api/business/guest-records?businessId=$businessId');
      final rows = handleResponse(response) as List? ?? [];
      debugPrint('☁️ _fetchOnline: found ${rows.length} cloud records');

      final cloudRecords = _parseNodeRows(rows);
      final allRecords   = List<GuestRecord>.from(cloudRecords);

      if (!kIsWeb) {
        // MERGE: Add local records that are pending sync OR were synced very recently
        final merged = await _getMergedLocalRecords(businessId, cloudRecords.map((r) => r.id).toSet());
        debugPrint('🧩 _fetchOnline: merged ${merged.length} local records');
        allRecords.addAll(merged);

        // Re-sort so newest stays on top
        allRecords.sort((a, b) => b.checkIn.compareTo(a.checkIn));
      }


      _refreshLocalCache(businessId, rows).catchError(
        (e) => debugPrint('⚠️ Local cache refresh error: $e'),
      );

      return ApiResult.success(allRecords);
    } catch (e) {
      return ApiResult.failure('Failed to load records: $e');
    }
  }

  Future<List<GuestRecord>> _getMergedLocalRecords(String businessId, Set<String> cloudIds) async {
    try {
      final db = await LocalDatabase.instance.database;
      
      // We want:
      // 1. Records with sync_status != synced (pending changes)
      // 2. Records with sync_status == synced BUT updated/synced very recently (grace period)
      final now = DateTime.now().toUtc();
      final graceThreshold = now.subtract(const Duration(minutes: 2)).toIso8601String();

      final allLocalCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ${LocalDatabase.tableGuestRecords}'));
      
      final rows = await db.query(
        LocalDatabase.tableGuestRecords,
        where: 'business_id = ? AND is_deleted = 0 AND (sync_status != ? OR local_updated_at > ?)',
        whereArgs: [businessId, LocalDatabase.syncSynced, graceThreshold],
      );
      
      if (rows.isEmpty && (allLocalCount ?? 0) > 0) {
        debugPrint('🔍 _getMergedLocalRecords: No matches found for biz $businessId, but DB has $allLocalCount total records.');
      }

      final records = <GuestRecord>[];
      for (final row in rows) {
        final recordId = row['id'] as String;
        if (cloudIds.contains(recordId)) continue; // Already in cloud results

        final breakdownRows = await db.query(
          LocalDatabase.tableGuestBreakdowns,
          where:     'guest_record_id = ?',
          whereArgs: [recordId],
        );

        final checkIn  = row['check_in']  as String;
        final checkOut = row['check_out'] as String;

        records.add(GuestRecord(
          id:           recordId,
          checkIn:      checkIn,
          checkOut:     checkOut,
          nights:       _calcNights(checkIn, checkOut),
          guests:       (row['total_guests']       as int?) ?? 0,
          rooms:        (row['rooms_occupied']      as int?) ?? 0,
          purpose:      row['purpose_of_visit']     as String? ?? '',
          transport:    row['transportation_mode']  as String? ?? '',
          status:       (row['status'] as String?) == 'archived'
              ? GuestRecordStatus.archived
              : GuestRecordStatus.active,
          demographics: _buildDemographicsFromLocal(breakdownRows),
        ));
      }
      return records;
    } catch (e) {
      debugPrint('⚠️ _getMergedLocalRecords error: $e');
      return [];
    }
  }

  // ===========================================================================
  // OFFLINE — read entirely from SQLite.
  // ===========================================================================

  Future<ApiResult<List<GuestRecord>>> _fetchOffline(String businessId) async {
    try {
      final db = await LocalDatabase.instance.database;

      final rows = await db.query(
        LocalDatabase.tableGuestRecords,
        where:   'business_id = ? AND is_deleted = 0',
        whereArgs: [businessId],
        orderBy: 'check_in DESC',
      );

      final records = <GuestRecord>[];

      for (final row in rows) {
        final recordId = row['id'] as String;

        final breakdownRows = await db.query(
          LocalDatabase.tableGuestBreakdowns,
          where:     'guest_record_id = ?',
          whereArgs: [recordId],
        );

        final checkIn  = row['check_in']  as String;
        final checkOut = row['check_out'] as String;

        records.add(GuestRecord(
          id:           recordId,
          checkIn:      checkIn,
          checkOut:     checkOut,
          nights:       _calcNights(checkIn, checkOut),
          guests:       (row['total_guests']       as int?) ?? 0,
          rooms:        (row['rooms_occupied']      as int?) ?? 0,
          purpose:      row['purpose_of_visit']     as String? ?? '',
          transport:    row['transportation_mode']  as String? ?? '',
          status:       (row['status'] as String?) == 'archived'
              ? GuestRecordStatus.archived
              : GuestRecordStatus.active,
          demographics: _buildDemographicsFromLocal(breakdownRows),
        ));
      }

      return ApiResult.success(records);
    } catch (e) {
      debugPrint('❌ fetchGuestRecords (offline) error: $e');
      return ApiResult.failure('Failed to load local records.');
    }
  }

  // ===========================================================================
  // ONLINE UPDATE — Node API first, then mirror to SQLite as synced.
  // ===========================================================================

  Future<ApiResult<void>> _updateOnline({
    required String recordId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    required int roomsOccupied,
    required String purposeOfVisit,
    required String transportationMode,
    required List<GuestBreakdownEntry> breakdowns,
  }) async {
    try {
      final businessId = SessionService.instance.current?.businessId;
      final payload = {
        'businessId':         businessId,
        'checkIn':            checkIn,
        'checkOut':           checkOut,
        'totalGuests':        totalGuests,
        'roomsOccupied':      roomsOccupied,
        'purposeOfVisit':     purposeOfVisit,
        'transportationMode': transportationMode,
        'breakdowns':         breakdowns.map((b) => _breakdownEntryToPayload(b)).toList(),
      };

      await put('/api/business/guest-records/$recordId', payload);

      if (!kIsWeb) {
        final db = await LocalDatabase.instance.database;
        await db.update(
          LocalDatabase.tableGuestRecords,
          {
            'check_in':            checkIn,
            'check_out':           checkOut,
            'total_guests':        totalGuests,
            'rooms_occupied':      roomsOccupied,
            'purpose_of_visit':    purposeOfVisit,
            'transportation_mode': transportationMode,
            'sync_status':         LocalDatabase.syncSynced,
            'local_updated_at':    DateTime.now().toUtc().toIso8601String(),
          },
          where:     'id = ?',
          whereArgs: [recordId],
        );
        await _replaceLocalBreakdowns(db, recordId, breakdowns);
      }

      return const ApiResult.success(null);
    } catch (e) {
      return ApiResult.failure('Failed to update record: $e');
    }
  }

  // ===========================================================================
  // OFFLINE UPDATE — SQLite only, tagged pending_update.
  // ===========================================================================

  Future<ApiResult<void>> _updateOffline({
    required String recordId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    required int roomsOccupied,
    required String purposeOfVisit,
    required String transportationMode,
    required List<GuestBreakdownEntry> breakdowns,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final db  = await LocalDatabase.instance.database;

      await db.update(
        LocalDatabase.tableGuestRecords,
        {
          'check_in':            checkIn,
          'check_out':           checkOut,
          'total_guests':        totalGuests,
          'rooms_occupied':      roomsOccupied,
          'purpose_of_visit':    purposeOfVisit,
          'transportation_mode': transportationMode,
          'sync_status':         LocalDatabase.syncPendingUpdate,
          'local_updated_at':    now,
        },
        where:     'id = ?',
        whereArgs: [recordId],
      );

      await _replaceLocalBreakdowns(db, recordId, breakdowns);

      return const ApiResult.success(null);
    } catch (e) {
      debugPrint('❌ updateRecord (offline) error: $e');
      return ApiResult.failure(
        'Failed to save changes locally. Please try again.',
      );
    }
  }

  // ===========================================================================
  // Local cache helpers
  // ===========================================================================

  Future<void> _refreshLocalCache(String businessId, List rows) async {
    if (kIsWeb) {
      debugPrint('⏭ _refreshLocalCache: skipped on web — local SQLite is disabled');
      return;
    }

    final db = await LocalDatabase.instance.database;
    final remoteIds = rows.map((r) => r['id'] as String).toSet();

    // 1. Prune local records that were deleted on the Cloud
    // We only delete local records that are marked as 'synced'. 
    // If they are 'pending_create' or 'pending_update', we keep them.
    final localSynced = await db.query(
      LocalDatabase.tableGuestRecords,
      columns:   ['id', 'local_updated_at'],
      where:     'business_id = ? AND sync_status = ?',
      whereArgs: [businessId, LocalDatabase.syncSynced],
    );

    final now = DateTime.now().toUtc();
    for (final local in localSynced) {
      final id = local['id'] as String;
      if (!remoteIds.contains(id)) {
        // SAFETY: Don't prune if the record was updated/synced in the last 60 seconds.
        // This prevents a race condition where a record is pushed but doesn't 
        // immediately appear in the subsequent GET request due to indexing lag.
        final localUpdatedAtStr = local['local_updated_at'] as String?;
        if (localUpdatedAtStr != null) {
          final updatedAt = DateTime.tryParse(localUpdatedAtStr);
          if (updatedAt != null && now.difference(updatedAt).inSeconds < 60) {
            debugPrint('⏳ Skipping pruning for just-synced record $id (grace period)');
            continue;
          }
        }

        debugPrint('🧹 Pruning local synced record $id (not found on cloud)');
        await db.delete(
          LocalDatabase.tableGuestRecords,
          where:     'id = ?',
          whereArgs: [id],
        );
        await db.delete(
          LocalDatabase.tableGuestBreakdowns,
          where:     'guest_record_id = ?',
          whereArgs: [id],
        );
      }
    }

    // 2. Insert / Update from Cloud
    for (final row in rows) {
      final recordId = row['id'] as String;

      final pending = await db.query(
        LocalDatabase.tableGuestRecords,
        columns:   ['sync_status'],
        where:     'id = ? AND sync_status != ?',
        whereArgs: [recordId, LocalDatabase.syncSynced],
        limit:     1,
      );
      if (pending.isNotEmpty) continue;

      await db.insert(
        LocalDatabase.tableGuestRecords,
        {
          'id':                  recordId,
          'business_id':         businessId,
          'check_in':            row['check_in'],
          'check_out':           row['check_out'],
          'total_guests':        row['total_guests'],
          'rooms_occupied':      row['rooms_occupied'],
          'purpose_of_visit':    row['purpose_of_visit'],
          'transportation_mode': row['transportation_mode'],
          'status':              row['status'] ?? 'active',
          'is_deleted':          0,
          'created_at':          row['created_at'],
          'sync_status':         LocalDatabase.syncSynced,
          'local_updated_at':    null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await db.delete(
        LocalDatabase.tableGuestBreakdowns,
        where:     'guest_record_id = ?',
        whereArgs: [recordId],
      );

      final bds = row['guest_breakdowns'] as List? ?? [];
      for (final b in bds) {
        await db.insert(
          LocalDatabase.tableGuestBreakdowns,
          {
            'id':                 b['id'],
            'guest_record_id':    recordId,
            'country':            b['country'],
            'philippines_region': b['philippines_region'],
            'nationality':        b['nationality'],
            'sex':                b['sex'],
            'age_group':          b['age_group'],
            'count':              b['count'],
            'is_overseas':        (b['is_overseas'] == true || b['is_overseas'] == 1) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<void> _replaceLocalBreakdowns(
    dynamic db,
    String recordId,
    List<GuestBreakdownEntry> breakdowns,
  ) async {
    await db.delete(
      LocalDatabase.tableGuestBreakdowns,
      where:     'guest_record_id = ?',
      whereArgs: [recordId],
    );

    for (int i = 0; i < breakdowns.length; i++) {
      final b             = breakdowns[i];
      final isOverseas    = b.isOverseas;
      final isPhilippines = !isOverseas && b.country == 'Philippines';

      await db.insert(
        LocalDatabase.tableGuestBreakdowns,
        {
          'id':                 '${recordId}_breakdown_$i',
          'guest_record_id':    recordId,
          'country':            isOverseas ? null : b.country,
          'philippines_region': isPhilippines ? b.philippinesRegion : null,
          'nationality':        isPhilippines ? b.nationality : null,
          'sex':                _mapSex(b.sex),
          'age_group':          _mapAgeGroup(b.ageGroup),
          'count':              b.count,
          'is_overseas':        isOverseas ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ===========================================================================
  // Payload Mappers
  // ===========================================================================

  Map<String, dynamic> _localBreakdownRowToPayload(Map<String, dynamic> b) {
    final isOverseas = (b['is_overseas'] as int?) == 1;
    return {
      'isOverseas':        isOverseas,
      'country':            isOverseas ? null : b['country'],
      'nationality':        b['nationality'],
      'philippinesRegion': b['philippines_region'],
      'sex':                b['sex'],
      'ageGroup':          b['age_group'],
      'count':              b['count'],
    };
  }

  Map<String, dynamic> _breakdownEntryToPayload(GuestBreakdownEntry b) {
    final isOverseas    = b.isOverseas;
    final isPhilippines = !isOverseas && b.country == 'Philippines';
    return {
      'isOverseas':        isOverseas,
      'country':            isOverseas ? null : b.country,
      'nationality':        isPhilippines ? b.nationality : null,
      'philippinesRegion': isPhilippines ? b.philippinesRegion : null,
      'sex':                _mapSex(b.sex),
      'ageGroup':          _mapAgeGroup(b.ageGroup),
      'count':              b.count,
    };
  }

  // ===========================================================================
  // Parsing helpers
  // ===========================================================================

  List<GuestRecord> _parseNodeRows(List rows) {
    return rows.map((row) {
      final breakdowns = (row['guest_breakdowns'] as List?) ?? [];
      final checkIn    = row['check_in']  as String;
      final checkOut   = row['check_out'] as String;
      final statusStr  = row['status']    as String? ?? 'active';

      return GuestRecord(
        id:           row['id'] as String,
        checkIn:      checkIn,
        checkOut:     checkOut,
        nights:       _calcNights(checkIn, checkOut),
        guests:       (row['total_guests']       as int?) ?? 0,
        rooms:        (row['rooms_occupied']      as int?) ?? 0,
        purpose:      row['purpose_of_visit']     as String? ?? '',
        transport:    row['transportation_mode']  as String? ?? '',
        status:       statusStr == 'archived'
            ? GuestRecordStatus.archived
            : GuestRecordStatus.active,
        demographics: _buildDemographicsFromNode(breakdowns),
      );
    }).toList();
  }

  GuestDemographics? _buildDemographicsFromNode(List breakdowns) {
    if (breakdowns.isEmpty) return null;

    final ageGroups = <String, int>{};
    final sex       = <String, int>{};
    final countries = <String, int>{};
    final entries   = <GuestBreakdownEntry>[];

    for (final b in breakdowns) {
      final count      = (b['count']       as int?)  ?? 0;
      final isOverseas = (b['is_overseas'] == true || b['is_overseas'] == 1);
      final ageGroup   = b['age_group']    as String? ?? 'Unknown';
      final s          = b['sex']          as String? ?? 'Unknown';

      ageGroups[ageGroup] = (ageGroups[ageGroup] ?? 0) + count;
      sex[s]              = (sex[s]              ?? 0) + count;

      final String countryKey;
      if (isOverseas) {
        countryKey = 'Overseas';
      } else {
        final country = b['country'] as String? ?? 'Unknown';
        final region  = b['philippines_region'] as String?;
        countryKey    = (country == 'Philippines' &&
                region != null && region != 'N/A')
            ? 'PH – $region'
            : country;
      }
      countries[countryKey] = (countries[countryKey] ?? 0) + count;

      entries.add(GuestBreakdownEntry(
        country:           isOverseas ? null : b['country'] as String?,
        nationality:       (!isOverseas && b['country'] == 'Philippines')
            ? b['nationality'] as String?
            : null,
        philippinesRegion: (!isOverseas &&
                b['country'] == 'Philippines' &&
                (b['philippines_region'] as String?) != null &&
                (b['philippines_region'] as String?) != 'N/A')
            ? b['philippines_region'] as String?
            : null,
        sex:        b['sex']       as String? ?? '',
        ageGroup:   b['age_group'] as String? ?? '',
        count:      count,
        isOverseas: isOverseas,
      ));
    }

    return GuestDemographics(
      ageGroups:       ageGroups,
      sexDistribution: sex,
      countries:       countries,
      breakdowns:      entries,
    );
  }

  GuestDemographics? _buildDemographicsFromLocal(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return null;

    final ageGroups = <String, int>{};
    final sex       = <String, int>{};
    final countries = <String, int>{};
    final entries   = <GuestBreakdownEntry>[];

    for (final b in rows) {
      final count      = (b['count']       as int?) ?? 0;
      final isOverseas = (b['is_overseas'] as int?) == 1;
      final ageGroup   = b['age_group']    as String? ?? 'Unknown';
      final s          = b['sex']          as String? ?? 'Unknown';

      ageGroups[ageGroup] = (ageGroups[ageGroup] ?? 0) + count;
      sex[s]              = (sex[s]              ?? 0) + count;

      final String countryKey;
      if (isOverseas) {
        countryKey = 'Overseas';
      } else {
        final country = b['country'] as String? ?? 'Unknown';
        final region  = b['philippines_region'] as String?;
        countryKey    = (country == 'Philippines' &&
                region != null && region != 'N/A')
            ? 'PH – $region'
            : country;
      }
      countries[countryKey] = (countries[countryKey] ?? 0) + count;

      entries.add(GuestBreakdownEntry(
        country:           isOverseas ? null : b['country'] as String?,
        nationality:       (!isOverseas && b['country'] == 'Philippines')
            ? b['nationality'] as String?
            : null,
        philippinesRegion: (!isOverseas &&
                b['country'] == 'Philippines' &&
                (b['philippines_region'] as String?) != null &&
                (b['philippines_region'] as String?) != 'N/A')
            ? b['philippines_region'] as String?
            : null,
        sex:        b['sex']       as String? ?? '',
        ageGroup:   b['age_group'] as String? ?? '',
        count:      count,
        isOverseas: isOverseas,
      ));
    }

    return GuestDemographics(
      ageGroups:       ageGroups,
      sexDistribution: sex,
      countries:       countries,
      breakdowns:      entries,
    );
  }

  // ===========================================================================
  // Value mappers
  // ===========================================================================

  String _calcNights(String checkIn, String checkOut) {
    try {
      final inDate  = DateTime.parse(checkIn);
      final outDate = DateTime.parse(checkOut);
      final n       = outDate.difference(inDate).inDays;
      return '$n night${n == 1 ? '' : 's'}';
    } catch (_) {
      return '—';
    }
  }

  String _mapSex(String sex) {
    switch (sex.toLowerCase()) {
      case 'male':   return 'male';
      case 'female': return 'female';
      default:       return 'male';
    }
  }

  String _mapAgeGroup(String ageGroup) {
    final normalised = ageGroup.trim().replaceAll('–', '-');
    switch (normalised) {
      case '0-9':
      case '1-9':               return '1-9';
      case '10-17':             return '10-17';
      case '18-25':             return '18-25';
      case '26-35':             return '26-35';
      case '36-45':             return '36-45';
      case '46-55':             return '46-55';
      case '56+':               return '56+';
      case 'prefer_not_to_say':
      case 'prefer not to say': return 'prefer_not_to_say';
      default:                  return 'prefer_not_to_say';
    }
  }
}