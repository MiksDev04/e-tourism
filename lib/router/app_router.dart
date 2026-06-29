import 'package:flutter/material.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/router/app_routes.dart';

import 'package:app/ui/shared/pages/login_page.dart';
import 'package:app/ui/shared/pages/register_page.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:app/ui/admin/pages/admin_dashboard_page.dart';
import 'package:app/ui/admin/pages/admin_accommodations_page.dart';
import 'package:app/ui/admin/pages/admin_reports_page.dart';
import 'package:app/ui/admin/pages/admin_messages_page.dart';
import 'package:app/ui/admin/pages/admin_compliance_page.dart';
import 'package:app/ui/admin/pages/admin_profile_page.dart';
import 'package:app/ui/business/pages/business_dashboard_page.dart';
import 'package:app/ui/business/pages/business_guest_entry_page.dart';
import 'package:app/ui/business/pages/business_guest_records_page.dart';
import 'package:app/ui/business/pages/business_messages_page.dart';
import 'package:app/ui/business/pages/business_profile_page.dart';

import 'package:app/ui/shared/layouts/admin_layout.dart';
import 'package:app/ui/shared/layouts/business_layout.dart';

// ─── Offline-allowed routes ───────────────────────────────────────────────────
//
// Business users in offline mode may only visit these routes.
// Everything else shows OfflineRestrictedPage.

const _offlineAllowedRoutes = {
  AppRoutes.businessDashboard,
  AppRoutes.businessGuestEntry,
  AppRoutes.businessGuestRecord,
};

// ─── Route Metadata ───────────────────────────────────────────────────────────

class _RouteMeta {
  final String title;
  final int index;
  const _RouteMeta(this.title, this.index);
}

const _adminRouteMeta = {
  AppRoutes.adminDashboard: _RouteMeta('Dashboard', 0),
  AppRoutes.adminAccommodations: _RouteMeta('Accommodations', 1),
  AppRoutes.adminReports: _RouteMeta('Reports', 2),
  AppRoutes.adminMessages: _RouteMeta('Messages', 3),
  AppRoutes.adminCompliance: _RouteMeta('Compliance', 4),
  AppRoutes.adminProfile: _RouteMeta('Profile', 5),
};

const _businessRouteMeta = {
  AppRoutes.businessDashboard: _RouteMeta('Dashboard', 0),
  AppRoutes.businessGuestEntry: _RouteMeta('Guest Entry', 1),
  AppRoutes.businessGuestRecord: _RouteMeta('Guest Records', 2),
  AppRoutes.businessMessages: _RouteMeta('Messages', 4),
  AppRoutes.businessProfile: _RouteMeta('Profile', 5),
};

// ─── Route Permissions ────────────────────────────────────────────────────────

abstract final class _RoutePermissions {
  static const Map<String, Set<String>> _map = {
    AppRoutes.login: {},
    AppRoutes.register: {},
    AppRoutes.adminDashboard: {'admin'},
    AppRoutes.adminAccommodations: {'admin'},
    AppRoutes.adminMessages: {'admin'},
    AppRoutes.adminReports: {'admin'},
    AppRoutes.adminCompliance: {'admin'},
    AppRoutes.adminProfile: {'admin'},
    AppRoutes.businessDashboard: {'business'},
    AppRoutes.businessGuestEntry: {'business'},
    AppRoutes.businessGuestRecord: {'business'},
    AppRoutes.businessMessages: {'business'},
    AppRoutes.businessProfile: {'business'},
  };

  /// Returns null if allowed, or a sentinel string if blocked.
  static String? guard(String routeName) {
    final allowed = _map[routeName];
    if (allowed == null) return null;
    if (allowed.isEmpty) return null; // public route

    final session = SessionService.instance.current;
    if (session == null) return '__login__';
    if (!allowed.contains(session.role)) return '__denied__';

    // ── Offline guard ──────────────────────────────────────────────────────
    // Admin never uses offline mode, so we only check business sessions.
    if (session.isOfflineSession &&
        !_offlineAllowedRoutes.contains(routeName)) {
      return '__offline__';
    }

    return null;
  }
}

// ─── Router ───────────────────────────────────────────────────────────────────

abstract final class AppRouter {
  static String get initialRoute {
    final session = SessionService.instance.current;
    if (session == null) return AppRoutes.login;
    return session.role == 'admin'
        ? AppRoutes.adminDashboard
        : AppRoutes.businessDashboard;
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final routeName = settings.name ?? '';

    // ── Auth + offline guard ─────────────────────────────────────────────────
    final guardResult = _RoutePermissions.guard(routeName);

    if (guardResult == '__login__') {
      return _fade(
        const LoginPage(),
        const RouteSettings(name: AppRoutes.login),
      );
    }
    if (guardResult == '__denied__') {
      return _fade(
        _wrapError(
          routeName,
          const ErrorPage(statusCode: 403),
        ),
        settings,
      );
    }
    if (guardResult == '__offline__') {
      return _fade(
        Builder(
          builder: (context) => _wrapError(
            routeName,
            ErrorPage(
              statusCode: 503,
              onRetry: () => Navigator.pushReplacementNamed(
                context,
                AppRouter.initialRoute,
              ),
            ),
          ),
        ),
        settings,
      );
    }

    // ── Root / empty route (browser back button to initial /) ──────────────
    if (routeName.isEmpty || routeName == '/') {
      final session = SessionService.instance.current;
      if (session == null) {
        return _fade(const LoginPage(), const RouteSettings(name: AppRoutes.login));
      }
      return _fade(
        session.role == 'admin'
            ? const AdminDashboardPage()
            : const BusinessDashboardPage(),
        RouteSettings(
          name: session.role == 'admin'
              ? AppRoutes.adminDashboard
              : AppRoutes.businessDashboard,
        ),
      );
    }

    // ── Normal routing ───────────────────────────────────────────────────────
    return switch (routeName) {
      AppRoutes.login => _fade(const LoginPage(), settings),
      AppRoutes.register => _fade(const RegisterPage(), settings),
      AppRoutes.adminDashboard => _fade(const AdminDashboardPage(), settings),
      AppRoutes.adminAccommodations => _fade(
        const AdminAccommodationsPage(),
        settings,
      ),
      AppRoutes.adminMessages => _fade(const AdminMessagesPage(), settings),
      AppRoutes.adminReports => _fade(const AdminReportsPage(), settings),
      AppRoutes.adminProfile => _fade(const AdminProfilePage(), settings),
      AppRoutes.adminCompliance => _fade(const AdminCompliancePage(), settings),
      AppRoutes.businessDashboard => _fade(
        const BusinessDashboardPage(),
        settings,
      ),
      AppRoutes.businessGuestEntry => _fade(
        const BusinessGuestEntryPage(),
        settings,
      ),
      AppRoutes.businessGuestRecord => _fade(
        const BusinessGuestRecordsPage(),
        settings,
      ),
      AppRoutes.businessMessages => _fade(
        const BusinessMessagesPage(),
        settings,
      ),
      AppRoutes.businessProfile => _fade(const BusinessProfilePage(), settings),
      _ => _notFound(settings),
    };
  }

  static PageRouteBuilder<dynamic> _fade(Widget page, RouteSettings settings) =>
      PageRouteBuilder(
        settings: settings,
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 180),
      );

  static Route<dynamic> _notFound(RouteSettings settings) => MaterialPageRoute(
    settings: settings,
    builder: (context) => _wrapError(
      settings.name ?? '',
      ErrorPage(
        statusCode: 404,
        onRetry: () => Navigator.pushReplacementNamed(
          context,
          AppRouter.initialRoute,
        ),
      ),
    ),
  );

  /// Wraps an ErrorPage in the appropriate layout if the user is logged in.
  static Widget _wrapError(String routeName, Widget errorPage) {
    final session = SessionService.instance.current;
    if (session == null) return Scaffold(body: errorPage);

    if (session.role == 'admin') {
      final meta = _adminRouteMeta[routeName] ?? const _RouteMeta('Error', -1);
      return AdminLayout(
        title: meta.title,
        selectedIndex: meta.index,
        onNavSelected: (_) {},
        child: errorPage,
      );
    } else {
      final meta =
          _businessRouteMeta[routeName] ?? const _RouteMeta('Error', -1);
      return BusinessLayout(
        title: meta.title,
        selectedIndex: meta.index,
        onNavSelected: (_) {},
        child: errorPage,
      );
    }
  }
}
