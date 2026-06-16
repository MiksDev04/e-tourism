import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ---------------------------------------------------------------------------
/// LocalDatabase
/// ---------------------------------------------------------------------------
/// Singleton that owns the SQLite connection for the entire app.
///
/// Usage:
///   final db = await LocalDatabase.instance.database;
///   await db.insert(LocalDatabase.tableLocalProfiles, {...});
///
/// Versioning:
///   Bump [_kDbVersion] and add a block inside [_onUpgrade] whenever the
///   schema changes.  Never alter existing [_onCreate] SQL — migrations only.
/// ---------------------------------------------------------------------------
class LocalDatabase {
  LocalDatabase._internal();

  static final LocalDatabase instance = LocalDatabase._internal();

  static Database? _db;

  // ── file name ──────────────────────────────────────────────────────────────
  static const String _kDbName = 'tourism_local.db';

  // ── schema version ─────────────────────────────────────────────────────────
  static const int _kDbVersion = 1;

  // ── table names ────────────────────────────────────────────────────────────
  static const String tableLocalProfiles   = 'local_profiles';
  static const String tableLocalBusinesses = 'local_businesses';
  static const String tableGuestRecords    = 'local_guest_records';
  static const String tableGuestBreakdowns = 'local_guest_breakdowns';

  // ── sync status constants ──────────────────────────────────────────────────
  /// Record exists on Backend and matches local copy.
  static const String syncSynced        = 'synced';
  /// Created offline, not yet pushed to Backend.
  static const String syncPendingCreate = 'pending_create';
  /// Edited offline, not yet pushed to Backend.
  static const String syncPendingUpdate = 'pending_update';

  // ── database accessor ──────────────────────────────────────────────────────
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  // ── init ───────────────────────────────────────────────────────────────────
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = join(dbPath, _kDbName);

    return openDatabase(
      fullPath,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: onDatabaseDowngradeDelete,
      // Enforce foreign-key constraints on every connection.
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  /// Returns the full filesystem path to the SQLite database file.
  /// Useful for logging or diagnostics on desktop platforms.
  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _kDbName);
  }

  // ── onCreate — full schema at current version ──────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute(_sqlCreateLocalProfiles);
      await txn.execute(_sqlCreateLocalBusinesses);
      await txn.execute(_sqlCreateGuestRecords);
      await txn.execute(_sqlCreateGuestBreakdowns);

      await txn.execute(_sqlIndexGuestRecordsBusiness);
      await txn.execute(_sqlIndexGuestBreakdownsRecord);
      await txn.execute(_sqlIndexGuestRecordsSyncStatus);
    });
  }

  // ── onUpgrade — add migration blocks here for future versions ─────────────
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration logic for future versions goes here.
  }

  // ── helper: close (mainly for tests) ──────────────────────────────────────
  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  // ── helper: delete database (dev/debug only) ───────────────────────────────
  Future<void> deleteDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    final fullPath = join(dbPath, _kDbName);
    await deleteDatabase(fullPath);
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // SQL — table definitions
  // ---------------------------------------------------------------------------

  /// Cached login credentials.
  /// One row per staff account that has ever logged in on this device.
  /// password_hash = SHA-256( password + userId ) — never stored in plain text.
  static const String _sqlCreateLocalProfiles = '''
    CREATE TABLE $tableLocalProfiles (
      id            TEXT PRIMARY KEY,
      username      TEXT NOT NULL,
      full_name     TEXT,
      email         TEXT,
      phone         TEXT,
      role          TEXT,
      password_hash TEXT NOT NULL
    )
  ''';

  /// Cached business data for the logged-in profile.
  /// Refreshed from Backend on every successful online login.
  static const String _sqlCreateLocalBusinesses = '''
    CREATE TABLE $tableLocalBusinesses (
      id                  TEXT PRIMARY KEY,
      profile_id          TEXT NOT NULL,
      business_name       TEXT,
      status              TEXT,
      permit_number       TEXT,
      registration_number TEXT,
      street              TEXT,
      total_rooms         INTEGER,
      region              TEXT,
      city_municipality   TEXT,
      province            TEXT,
      barangay            TEXT,
      tradename           TEXT,
      business_line       TEXT,
      owner_first_name    TEXT,
      owner_last_name     TEXT,
      owner_middle_name   TEXT,
      business_type       TEXT,
      FOREIGN KEY (profile_id) REFERENCES $tableLocalProfiles (id)
        ON DELETE CASCADE
    )
  ''';

  /// Guest records with sync tracking.
  /// sync_status drives the push phase of SyncService.
  /// All datetimes are stored as ISO 8601 strings (UTC).
  static const String _sqlCreateGuestRecords = '''
    CREATE TABLE $tableGuestRecords (
      id                  TEXT PRIMARY KEY,
      business_id         TEXT NOT NULL,
      check_in            TEXT NOT NULL,
      check_out           TEXT NOT NULL,
      total_guests        INTEGER NOT NULL,
      rooms_occupied      INTEGER NOT NULL,
      purpose_of_visit    TEXT NOT NULL,
      transportation_mode TEXT NOT NULL,
      status              TEXT NOT NULL DEFAULT 'active',
      is_deleted          INTEGER NOT NULL DEFAULT 0,
      created_at          TEXT,
      sync_status         TEXT NOT NULL DEFAULT '$syncSynced',
      local_updated_at    TEXT,
      FOREIGN KEY (business_id) REFERENCES $tableLocalBusinesses (id)
        ON DELETE CASCADE
    )
  ''';

  /// Guest breakdowns linked to a guest record.
  /// Always re-written in full together with their parent record.
  static const String _sqlCreateGuestBreakdowns = '''
    CREATE TABLE $tableGuestBreakdowns (
      id                 TEXT PRIMARY KEY,
      guest_record_id    TEXT NOT NULL,
      country            TEXT,
      philippines_region TEXT,
      nationality        TEXT,
      sex                TEXT NOT NULL,
      age_group          TEXT NOT NULL,
      count              INTEGER NOT NULL,
      is_overseas        INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (guest_record_id) REFERENCES $tableGuestRecords (id)
        ON DELETE CASCADE
    )
  ''';

  // ---------------------------------------------------------------------------
  // SQL — indexes
  // ---------------------------------------------------------------------------

  /// Fast look-up of all guest records belonging to a business.
  static const String _sqlIndexGuestRecordsBusiness = '''
    CREATE INDEX idx_guest_records_business_id
      ON $tableGuestRecords (business_id)
  ''';

  /// Fast look-up of all breakdowns belonging to a guest record.
  static const String _sqlIndexGuestBreakdownsRecord = '''
    CREATE INDEX idx_guest_breakdowns_record_id
      ON $tableGuestBreakdowns (guest_record_id)
  ''';

  /// Fast look-up of all unsynced records during the push phase.
  static const String _sqlIndexGuestRecordsSyncStatus = '''
    CREATE INDEX idx_guest_records_sync_status
      ON $tableGuestRecords (sync_status)
  ''';
}