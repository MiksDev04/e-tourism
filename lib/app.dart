import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/router/app_router.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'dart:async';

// ─── App ──────────────────────────────────────────────────────────────────────

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionService.instance,
      builder: (context, child) {
        return MaterialApp(
          title: _getDynamicTitle(),
          debugShowCheckedModeBanner: false,

          // ── Theme ──────────────────────────────────────────────────────────────
          theme: _buildTheme(),

          // ── Routing ────────────────────────────────────────────────────────────
          initialRoute: AppRouter.initialRoute,
          onGenerateRoute: AppRouter.onGenerateRoute,
          builder: (context, child) {
            return Column(
              children: [
                Expanded(child: child ?? const SizedBox.shrink()),
                const SyncBannerOverlay(),
              ],
            );
          },
        );
      },
    );
  }

  static String _getDynamicTitle() {
    final session = SessionService.instance.current;
    if (session == null) return 'San Pablo Tourism';
    if (session.role == 'admin') return 'San Pablo Tourism Admin';
    if (session.role == 'business') return 'San Pablo Tourism Business';
    return 'San Pablo Tourism';
  }

  static ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      colorScheme: ColorScheme.dark(
        surface: AppColors.backgroundDark,
        primary: AppColors.primaryCyan,
        secondary: AppColors.primaryBlue,
        error: AppColors.accentRed,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.textWhite),
        bodySmall: TextStyle(color: AppColors.textGray),
      ),
      dividerColor: AppColors.cardBorder,
    );
  }
}

// ─── Sync Banner ──────────────────────────────────────────────────────────────

class SyncBannerOverlay extends StatefulWidget {
  const SyncBannerOverlay({super.key});

  @override
  State<SyncBannerOverlay> createState() => _SyncBannerOverlayState();
}

class _SyncBannerOverlayState extends State<SyncBannerOverlay> {
  Timer? _hideTimer;
  bool _showBanner = false;
  SyncState _currentState = const SyncState(status: SyncStatus.idle);
  StreamSubscription<SyncState>? _subscription;

  @override
  void initState() {
    super.initState();

    // Listen to the stream here — NOT inside build — so the timer can
    // set _showBanner = false without the StreamBuilder immediately
    // reading the last-emitted value and restarting the whole cycle.
    _subscription = SyncService.instance.syncStateStream.listen(_onSyncState);

    // Handle a state that was already active before this widget mounted.
    final initial = SyncService.instance.currentState;
    if (initial.status != SyncStatus.idle) {
      _onSyncState(initial);
    }
  }

  void _onSyncState(SyncState state) {
    if (!mounted) return;
    setState(() {
      _currentState = state;
      switch (state.status) {
        case SyncStatus.syncing:
          // Only show the banner if there are actually local items pending to be synced online.
          _showBanner = state.pendingCount > 0;
          _hideTimer?.cancel();
          _hideTimer = null;
          break;

        case SyncStatus.error:
          // If we were already showing the banner (pushed something) or have pending items.
          if (_showBanner || state.pendingCount > 0) {
            _showBanner = true;
          }
          _hideTimer?.cancel();
          _hideTimer = null;
          break;

        case SyncStatus.synced:
          // Only show success snackbar if we were actually showing the "syncing" state.
          if (_showBanner) {
            _hideTimer?.cancel();
            _hideTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _showBanner = false);
            });
          }
          break;

        case SyncStatus.idle:
          _showBanner = false;
          _hideTimer?.cancel();
          _hideTimer = null;
          break;
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When the timer fires it sets _showBanner = false. Because we're no
    // longer using StreamBuilder here, the build won't re-read the last
    // stream value and accidentally restart the timer.
    if (!_showBanner || _currentState.status == SyncStatus.idle) {
      return const SizedBox.shrink();
    }

    Color bgColor = AppColors.primaryBlue;
    String message = 'Syncing offline data...';
    IconData icon = Icons.sync;

    if (_currentState.status == SyncStatus.error) {
      bgColor = AppColors.accentRed;
      message = 'Sync Error: ${_currentState.errorMessage ?? "Unknown"}';
      icon = Icons.error_outline;
    } else if (_currentState.status == SyncStatus.synced) {
      bgColor = AppColors.primaryCyan;
      message = 'Data synced successfully';
      icon = Icons.check_circle_outline;
    }

    return Material(
      color: bgColor,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          width: double.infinity,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_currentState.pendingCount > 0 &&
                  _currentState.status != SyncStatus.synced) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentState.pendingCount} left',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
