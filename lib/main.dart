import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app/app.dart';

class _AppLifecycleSyncObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ConnectivityService.instance.isOnline) {
      SyncService.instance.sync();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found: $e");
  }

  // ── sqflite desktop init ───────────────────────────────────────────────────
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // ── Step 1: Load connectivity + session ───────────────────────────────────
  await ConnectivityService.instance.startWatching();
  final session = await SessionService.instance.loadAndCache();

  // ── Step 2: Initialise SQLite BEFORE any sync can run ─────────────────────
  // SyncService reads/writes SQLite the moment it detects connectivity, so the
  // database must exist before we attach any listeners.
  if (!kIsWeb) {
    if (session?.role == 'business') {
      await LocalDatabase.instance.database;
      final dbPath = await LocalDatabase.instance.getDatabaseFilePath();
      debugPrint('SQLite DB path: $dbPath');
    } else {
      debugPrint('Offline sync disabled for ${session?.role ?? 'guest'} role.');
    }
  } else {
    debugPrint('Web platform: skipping local SQLite initialization.');
  }

  // ── Step 3: Attach lifecycle observer + periodic sync BEFORE listeners ─────
  WidgetsBinding.instance.addObserver(_AppLifecycleSyncObserver());

  Timer.periodic(const Duration(minutes: 5), (_) {
    if (ConnectivityService.instance.isOnline) {
      SyncService.instance.sync();
    }
  });

  // ── Step 4: Start connectivity listener (triggers immediate sync if online) ─
  // listenForConnectivity() already handles the initial online check and fires
  // _handleOnlineTransition → sync(). Do NOT call sync() again below — that
  // creates a race condition where sync runs without a valid auth token.
  SyncService.instance.listenForConnectivity();

  // ── Step 5: Window constraints (desktop only) ──────────────────────────────
  if (!kIsWeb) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(375, 500));
    await windowManager.setMaximumSize(const Size(1440, 900));
  }

  debugPaintBaselinesEnabled = false;
  runApp(const App());
}