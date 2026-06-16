import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../database/local_database.dart';
import 'session_service.dart';
import 'connectivity_service.dart';
import '../../api/login_api.dart';

export 'connectivity_service.dart';

// =============================================================================
// OFFLINE AUTH SERVICE
// =============================================================================

class OfflineAuthService {
  OfflineAuthService._internal();
  static final OfflineAuthService instance = OfflineAuthService._internal();

  Future<void> cacheProfile({
    required String id,
    required String username,
    required String password,
    String? fullName,
    String? email,
    String? phone,
    String? role,
    Map<String, dynamic>? business,
  }) async {
    final db = await LocalDatabase.instance.database;
    final hash = _hashPassword(password, id);

    await db.transaction((txn) async {
      final profileData = {
        'id': id,
        'username': username,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'password_hash': hash,
      };
      
      final pCount = await txn.update(
        LocalDatabase.tableLocalProfiles,
        profileData,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (pCount == 0) {
        await txn.insert(LocalDatabase.tableLocalProfiles, profileData);
      }

      if (business != null) {
        final bizData = {
          'id': business['id'],
          'profile_id': id,
          'business_name': business['business_name'],
          'status': business['status'],
          'permit_number': business['permit_number'],
          'registration_number': business['registration_number'],
          'street': business['street'],
          'total_rooms': business['total_rooms'],
          'region': business['region'],
          'city_municipality': business['city_municipality'],
          'province': business['province'],
          'barangay': business['barangay'],
          'tradename': business['tradename'],
          'business_line': business['business_line'] is String
              ? business['business_line']
              : jsonEncode(business['business_line']),
          'owner_first_name': business['owner_first_name'],
          'owner_last_name': business['owner_last_name'],
          'owner_middle_name': business['owner_middle_name'],
          'business_type': business['business_type'],
        };

        final bCount = await txn.update(
          LocalDatabase.tableLocalBusinesses,
          bizData,
          where: 'id = ?',
          whereArgs: [business['id']],
        );
        if (bCount == 0) {
          await txn.insert(LocalDatabase.tableLocalBusinesses, bizData);
        }
      }
    });
  }

  Future<Map<String, dynamic>?> verifyOfflineLogin({
    required String username,
    required String password,
  }) async {
    final db = await LocalDatabase.instance.database;

    final rows = await db.query(
      LocalDatabase.tableLocalProfiles,
      where: 'username = ? OR email = ?',
      whereArgs: [username, username],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final profile = rows.first;
    final expectedHash = _hashPassword(password, profile['id'] as String);

    if (profile['password_hash'] != expectedHash) return null;

    return profile;
  }

  String _hashPassword(String password, String userId) {
    final bytes = utf8.encode(password + userId);
    return sha256.convert(bytes).toString();
  }
}

// =============================================================================
// SYNC STATE
// =============================================================================

enum SyncStatus { idle, syncing, synced, error }

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final String? errorMessage;

  const SyncState({
    required this.status,
    this.pendingCount = 0,
    this.errorMessage,
  });
}

// =============================================================================
// SYNC SERVICE
// =============================================================================

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  String get _baseUrl {
    if (kIsWeb) {
      return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    } else if (Platform.isAndroid) {
      return dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
    } else {
      return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    }
  }

  Map<String, String> get _headers {
    final Map<String, String> h = {
      'Content-Type': 'application/json',
      'x-api-key': dotenv.env['API_KEY'] ?? 'tourism_app_v2_secret_key_2026',
    };

    final token = SessionService.instance.current?.token;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }

    return h;
  }

  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStateStream => _controller.stream;

  SyncState _state = const SyncState(status: SyncStatus.idle);
  SyncState get currentState => _state;

  static const _syncDelay = Duration(milliseconds: 500);

  void listenForConnectivity() {
    // 1. Listen for future changes
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        _handleOnlineTransition();
      }
    });

    // 2. Initial check: if already online, trigger sync immediately
    if (ConnectivityService.instance.isOnline) {
      _handleOnlineTransition();
    }
  }

  Future<void> _handleOnlineTransition() async {
    final session = SessionService.instance.current;

    // Session not loaded yet — retry after a short delay.
    if (session == null) {
      debugPrint('⏳ _handleOnlineTransition: session not ready — retrying in 2s');
      Future.delayed(const Duration(seconds: 2), _handleOnlineTransition);
      return;
    }

    // Session loaded but not a business account — stop, no sync needed.
    if (session.role != 'business') {
      debugPrint('⏭ _handleOnlineTransition: skipped — role is ${session.role}');
      return;
    }

    // ── Auto-Cloud-Upgrade ──────────────────────────────────────────────────
    // If we are online but have no token, attempt to get one using stored password.
    if (session.password != null &&
        (session.token == null || session.isOfflineSession)) {
      debugPrint(
        '☁️ SyncService: Online detected. Refreshing token before sync...',
      );
      try {
        await LoginApi().backgroundAuth(
          username: session.username ?? session.email,
          password: session.password!,
        );
      } catch (e) {
        debugPrint('⚠️ SyncService: Auto-auth error: $e');
      }
    }

    try {
      // Fetch profile and business to ensure SQLite has the business record.
      await _pullProfileAndBusiness();

      final current = SessionService.instance.current;
      String? businessId = current?.businessId;

      if (businessId == null && current != null) {
        final db = await LocalDatabase.instance.database;
        final rows = await db.query(
          LocalDatabase.tableLocalBusinesses,
          where: 'profile_id = ?',
          whereArgs: [current.userId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          businessId = rows.first['id'] as String?;
        }
      }

      if (businessId != null) {
        await _pullForBusiness(businessId);
      }
    } catch (e) {
      debugPrint('⚠️ _handleOnlineTransition: initial pulls failed: $e');
    }

    await _clearOfflineSessionFlag();

    // Give a small delay for state to settle before full sync.
    Future.delayed(_syncDelay, sync);
  }

  Future<void> _clearOfflineSessionFlag() async {
    final current = SessionService.instance.current;
    if (current == null || !current.isOfflineSession) return;

    final updated = current.copyWith(isOfflineSession: false);

    await SessionService.instance.save(updated);
    await SessionService.instance.loadAndCache();
    debugPrint('✅ _clearOfflineSessionFlag: isOfflineSession reset to false');
  }

  Future<void> sync() async {
    if (kIsWeb) {
      debugPrint('⏭ sync: skipped on web — local SQLite is disabled');
      return;
    }

    final session = SessionService.instance.current;
    if (session == null || session.role != 'business') {
      debugPrint('⏭ sync: skipped — only for business accounts');
      return;
    }

    if (_state.status == SyncStatus.syncing) return;

    if (!ConnectivityService.instance.isOnline) {
      debugPrint('⏭ sync: skipped — device is offline');
      return;
    }

    final initialPending = await _countPending();
    debugPrint('🔄 sync: starting sync process. Initial pending count: $initialPending');
    _emit(SyncState(status: SyncStatus.syncing, pendingCount: initialPending));

    try {
      await _pullProfileAndBusiness();
      await _pushPendingCreates(); // POST  → /api/business/guest-entries
      await _pushPendingUpdates(); // PUT   → /api/business/guest-records/:id
      await _pullFromBackend();    // GET   → /api/business/guest-records

      final remaining = await _countPending();
      _emit(SyncState(status: SyncStatus.synced, pendingCount: remaining));
    } catch (e) {
      _emit(
        SyncState(
          status: SyncStatus.error,
          errorMessage: e.toString(),
          pendingCount: await _countPending(),
        ),
      );
    }
  }

  Future<int> getPendingCount() => _countPending();

  // ---------------------------------------------------------------------------
  // PUSH PENDING CREATES
  // Uses POST /api/business/guest-entries so the backend treats them as new
  // records. The saved UUID is forwarded as `id` so the cloud uses the same
  // primary key that SQLite already has — avoiding duplicates on re-sync.
  // ---------------------------------------------------------------------------
  Future<void> _pushPendingCreates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingCreates: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableGuestRecords,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingCreate],
    );

    if (records.isNotEmpty) {
      debugPrint('📤 _pushPendingCreates: ${records.length} record(s) to push');
    }

    for (final record in records) {
      final recordId = record['id'] as String;

      try {
        final breakdowns = await db.query(
          LocalDatabase.tableGuestBreakdowns,
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );

        // Build payload and include the local UUID so the backend stores the
        // same ID — keeps SQLite and MySQL in sync without a remapping step.
        final payload = _toApiPayload(record, breakdowns);
        payload['id'] = recordId;

        final response = await http.post(
          Uri.parse('$_baseUrl/api/business/guest-entries'),
          headers: _headers,
          body: jsonEncode(payload),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await db.update(
            LocalDatabase.tableGuestRecords,
            {
              'sync_status': LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
          debugPrint('✅ _pushPendingCreates: synced $recordId');
        } else if (response.statusCode == 401) {
          debugPrint(
            '🔐 _pushPendingCreates: 401 — token expired, refreshing and aborting for retry',
          );
          await _tryRefreshToken();
          return; // Stop batch — next sync will use the fresh token.
        } else {
          debugPrint(
            '❌ _pushPendingCreates: failed for $recordId — '
            '${response.statusCode} ${response.body}',
          );
        }
      } on SocketException catch (e) {
        debugPrint('🌐 _pushPendingCreates: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pushPendingCreates: exception for $recordId — $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PUSH PENDING UPDATES
  // Uses PUT /api/business/guest-records/:id (upsert semantics on the backend).
  // ---------------------------------------------------------------------------
  Future<void> _pushPendingUpdates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingUpdates: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableGuestRecords,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingUpdate],
    );

    if (records.isNotEmpty) {
      debugPrint('📤 _pushPendingUpdates: ${records.length} record(s) to push');
    }

    for (final record in records) {
      final recordId = record['id'] as String;

      try {
        final breakdowns = await db.query(
          LocalDatabase.tableGuestBreakdowns,
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );

        final payload = _toApiPayload(record, breakdowns);

        final response = await http.put(
          Uri.parse('$_baseUrl/api/business/guest-records/$recordId'),
          headers: _headers,
          body: jsonEncode(payload),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await db.update(
            LocalDatabase.tableGuestRecords,
            {
              'sync_status': LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
          debugPrint('✅ _pushPendingUpdates: synced $recordId');
        } else if (response.statusCode == 401) {
          debugPrint(
            '🔐 _pushPendingUpdates: 401 — token expired, refreshing and aborting for retry',
          );
          await _tryRefreshToken();
          return;
        } else {
          debugPrint(
            '❌ _pushPendingUpdates: failed for $recordId — '
            '${response.statusCode} ${response.body}',
          );
        }
      } on SocketException catch (e) {
        debugPrint('🌐 _pushPendingUpdates: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pushPendingUpdates: exception for $recordId — $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PULL FROM BACKEND
  // ---------------------------------------------------------------------------
  Future<void> _pullFromBackend() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pullFromBackend: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final businesses = await db.query(
      LocalDatabase.tableLocalBusinesses,
      columns: ['id'],
    );

    for (final business in businesses) {
      final businessId = business['id'] as String;

      try {
        final response = await http.get(
          Uri.parse(
            '$_baseUrl/api/business/guest-records?businessId=$businessId',
          ),
          headers: _headers,
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final remoteRecords = jsonDecode(response.body) as List<dynamic>;
          final remoteIds =
              remoteRecords.map((r) => r['id'] as String).toSet();

          // 1. Prune local synced records that no longer exist on the cloud.
          final localSynced = await db.query(
            LocalDatabase.tableGuestRecords,
            columns: ['id', 'local_updated_at'],
            where: 'business_id = ? AND sync_status = ?',
            whereArgs: [businessId, LocalDatabase.syncSynced],
          );

          final now = DateTime.now().toUtc();
          for (final local in localSynced) {
            final id = local['id'] as String;
            if (!remoteIds.contains(id)) {
              // Grace period: skip recently-synced records to avoid a race
              // where the POST just succeeded but the GET hasn't caught up yet.
              final localUpdatedAtStr = local['local_updated_at'] as String?;
              if (localUpdatedAtStr != null) {
                final updatedAt = DateTime.tryParse(localUpdatedAtStr);
                if (updatedAt != null &&
                    now.difference(updatedAt).inSeconds < 60) {
                  debugPrint(
                    '⏳ Skipping pruning for just-synced record $id (grace period)',
                  );
                  continue;
                }
              }

              debugPrint(
                '🧹 Pruning local synced record $id (not found on cloud)',
              );
              await db.delete(
                LocalDatabase.tableGuestRecords,
                where: 'id = ?',
                whereArgs: [id],
              );
              await db.delete(
                LocalDatabase.tableGuestBreakdowns,
                where: 'guest_record_id = ?',
                whereArgs: [id],
              );
            }
          }

          // 2. Insert / Update records from cloud (skip any with pending changes).
          for (final remote in remoteRecords) {
            final recordId = remote['id'] as String;

            final pending = await db.query(
              LocalDatabase.tableGuestRecords,
              where: 'id = ? AND sync_status != ?',
              whereArgs: [recordId, LocalDatabase.syncSynced],
              limit: 1,
            );
            if (pending.isNotEmpty) {
              debugPrint('⏳ _pullFromBackend: skipping cloud record $recordId (has local pending changes)');
              continue;
            }

            await db.insert(
              LocalDatabase.tableGuestRecords,
              _fromApiRecord(remote as Map<String, dynamic>),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            await db.delete(
              LocalDatabase.tableGuestBreakdowns,
              where: 'guest_record_id = ?',
              whereArgs: [recordId],
            );

            final breakdowns =
                remote['guest_breakdowns'] as List<dynamic>? ?? [];
            for (final b in breakdowns) {
              await db.insert(
                LocalDatabase.tableGuestBreakdowns,
                _fromApiBreakdown(b as Map<String, dynamic>, recordId),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      } on SocketException catch (e) {
        debugPrint('🌐 _pullFromBackend: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint(
          '❌ _pullFromBackend: failed for business $businessId — $e',
        );
      }
    }
  }

  Future<void> _pullProfileAndBusiness() async {
    if (!await _canReachBackend()) return;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/profile'),
        headers: _headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        final biz = data['business'];

        final db = await LocalDatabase.instance.database;

        if (user != null) {
          final data = {
            'id': user['id'],
            'username': user['username'],
            'full_name': user['full_name'],
            'email': user['email'],
            'phone': user['phone'],
            'role': user['role'],
            'password_hash': 'sync_dummy_hash',
          };
          final count = await db.update(
            LocalDatabase.tableLocalProfiles,
            data,
            where: 'id = ?',
            whereArgs: [user['id']],
          );
          if (count == 0) {
            await db.insert(LocalDatabase.tableLocalProfiles, data);
          }
        }

        if (biz != null) {
          final data = {
            'id': biz['id'],
            'profile_id': biz['user_id'] ?? user['id'],
            'business_name': biz['business_name'],
            'permit_number': biz['permit_number'],
            'registration_number': biz['registration_number'],
            'street': biz['street'],
            'total_rooms': biz['total_rooms'],
            'status': biz['status'],
            'region': biz['region'],
            'city_municipality': biz['city_municipality'],
            'province': biz['province'],
            'barangay': biz['barangay'],
            'tradename': biz['tradename'],
            'business_line': biz['business_line'] is String
                ? biz['business_line']
                : jsonEncode(biz['business_line']),
            'owner_first_name': biz['owner_first_name'],
            'owner_last_name': biz['owner_last_name'],
            'owner_middle_name': biz['owner_middle_name'],
            'business_type': biz['business_type'],
          };
          final count = await db.update(
            LocalDatabase.tableLocalBusinesses,
            data,
            where: 'id = ?',
            whereArgs: [biz['id']],
          );
          if (count == 0) {
            await db.insert(LocalDatabase.tableLocalBusinesses, data);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ _pullProfileAndBusiness failed: $e');
    }
  }

  Future<void> _pullForBusiness(String businessId) async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pullForBusiness: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/business/guest-records?businessId=$businessId',
        ),
        headers: _headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final remoteRecords = jsonDecode(response.body) as List<dynamic>;

        for (final remote in remoteRecords) {
          final recordId = remote['id'] as String;

          final pending = await db.query(
            LocalDatabase.tableGuestRecords,
            where: 'id = ? AND sync_status != ?',
            whereArgs: [recordId, LocalDatabase.syncSynced],
            limit: 1,
          );
          if (pending.isNotEmpty) {
            debugPrint('⏳ _pullForBusiness: skipping cloud record $recordId (has local pending changes)');
            continue;
          }

          await db.insert(
            LocalDatabase.tableGuestRecords,
            _fromApiRecord(remote as Map<String, dynamic>),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          await db.delete(
            LocalDatabase.tableGuestBreakdowns,
            where: 'guest_record_id = ?',
            whereArgs: [recordId],
          );

          final breakdowns =
              remote['guest_breakdowns'] as List<dynamic>? ?? [];
          for (final b in breakdowns) {
            await db.insert(
              LocalDatabase.tableGuestBreakdowns,
              _fromApiBreakdown(b as Map<String, dynamic>, recordId),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    } on SocketException catch (e) {
      debugPrint('🌐 _pullForBusiness: network lost — aborting ($e)');
    } catch (e) {
      debugPrint('❌ _pullForBusiness: failed for business $businessId — $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Attempts a background re-auth and, on success, schedules a fresh sync.
  Future<void> _tryRefreshToken() async {
    final s = SessionService.instance.current;
    if (s?.password == null) return;

    try {
      final success = await LoginApi().backgroundAuth(
        username: s!.username ?? s.email,
        password: s.password!,
      );
      if (success) {
        Future.delayed(const Duration(seconds: 1), sync);
      }
    } catch (e) {
      debugPrint('⚠️ _tryRefreshToken: $e');
    }
  }

  Future<bool> _canReachBackend() async {
    if (!ConnectivityService.instance.isOnline) return false;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 4));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<int> _countPending() async {
    if (kIsWeb) return 0;

    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM ${LocalDatabase.tableGuestRecords}
      WHERE sync_status != ?
      ''',
      [LocalDatabase.syncSynced],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  void _emit(SyncState state) {
    _state = state;
    _controller.add(state);
  }

  // ---------------------------------------------------------------------------
  // Payload Mappers
  // ---------------------------------------------------------------------------

  /// Converts a SQLite row + its breakdowns into the JSON body expected by
  /// both POST /api/business/guest-entries and PUT /api/business/guest-records/:id.
  Map<String, dynamic> _toApiPayload(
    Map<String, dynamic> record,
    List<Map<String, dynamic>> breakdowns,
  ) {
    return {
      'businessId': record['business_id'],
      'checkIn': record['check_in'],
      'checkOut': record['check_out'],
      'totalGuests': record['total_guests'],
      'roomsOccupied': record['rooms_occupied'],
      'purposeOfVisit': record['purpose_of_visit'],
      'transportationMode': record['transportation_mode'],
      'status': record['status'],
      'breakdowns': breakdowns
          .map(
            (b) => {
              'isOverseas': b['is_overseas'] == 1,
              'country': b['country'],
              'nationality': b['nationality'],
              'philippinesRegion': b['philippines_region'],
              'sex': b['sex'],
              'ageGroup': b['age_group'],
              'count': b['count'],
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _fromApiRecord(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'business_id': row['business_id'],
      'check_in': row['check_in'],
      'check_out': row['check_out'],
      'total_guests': row['total_guests'],
      'rooms_occupied': row['rooms_occupied'],
      'purpose_of_visit': row['purpose_of_visit'],
      'transportation_mode': row['transportation_mode'],
      'status': row['status'] ?? 'active',
      'is_deleted': (row['is_deleted'] == true) ? 1 : 0,
      'created_at': row['created_at'],
      'sync_status': LocalDatabase.syncSynced,
      'local_updated_at': null,
    };
  }

  Map<String, dynamic> _fromApiBreakdown(
    Map<String, dynamic> row,
    String recordId,
  ) {
    return {
      'id': row['id'],
      'guest_record_id': row['guest_record_id'] ?? recordId,
      'country': row['country'],
      'philippines_region': row['philippines_region'],
      'nationality': row['nationality'],
      'sex': row['sex'],
      'age_group': row['age_group'],
      'count': row['count'],
      'is_overseas': (row['is_overseas'] == true) ? 1 : 0,
    };
  }
}