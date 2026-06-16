import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/core/services/offline_service.dart'
    hide ConnectivityService;
import 'package:app/core/database/local_database.dart';
import 'base_api.dart';

enum Role { business, admin }

class LoginResult {
  final bool success;
  final String? error;
  final Role? role;

  const LoginResult._({required this.success, this.error, this.role});

  factory LoginResult.ok(Role role) => LoginResult._(success: true, role: role);
  factory LoginResult.err(String error) =>
      LoginResult._(success: false, error: error);
}

class LoginApiException implements Exception {
  final String message;
  LoginApiException(this.message);
  @override
  String toString() => message;
}

class LoginApi extends BaseApi {
  // ===========================================================================
  // BACKGROUND AUTH (Auto-reconnect)
  // ===========================================================================
  Future<bool> backgroundAuth({
    required String username,
    required String password,
  }) async {
    try {
      final response = await post('/api/auth/login', {
        'username': username,
        'password': password,
      });

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final user = data['user'];
      final biz = data['business'];
      final token = data['token'];

      final current = SessionService.instance.current;
      if (current == null) return false;

      final updated = current.copyWith(
        token: token,
        isOfflineSession: false,
        // Update other fields just in case they changed on server
        fullName: user['full_name'],
        email: user['email'],
        phone: user['phone'],
        businessId: biz?['id']?.toString(),
        businessName: biz?['business_name'],
        status: biz?['status'],
      );

      await SessionService.instance.save(updated);
      await SessionService.instance.loadAndCache();

      // Refresh cache for future offline logins too
      await OfflineAuthService.instance.cacheProfile(
        id: user['id'].toString(),
        username: user['username'],
        password: password,
        fullName: user['full_name'],
        email: user['email'],
        phone: user['phone'],
        role: user['role'],
        business: biz,
      );

      return true;
    } catch (e) {
      debugPrint('⚠️ backgroundAuth error: $e');
      return false;
    }
  }

  // ===========================================================================
  // SIGN IN
  // ===========================================================================

  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    await SessionService.instance.clear();

    // ── OFFLINE ATTEMPT ──────────────────────────────────────────────────────
    if (!await ConnectivityService.instance.isOnlineAsync) {
      try {
        final db = await LocalDatabase.instance.database;

        // 1. First, check if this is a known admin trying to login offline.
        // Admins are NOT allowed to login offline, regardless of password.
        final adminCheck = await db.query(
          LocalDatabase.tableLocalProfiles,
          where: '(username = ? OR email = ?) AND role = ?',
          whereArgs: [username, username, 'admin'],
          limit: 1,
        );

        if (adminCheck.isNotEmpty) {
          return LoginResult.err(
            'Admin login requires an internet connection. Please connect to the internet to sign in.',
          );
        }

        // 2. Otherwise, attempt to verify business user credentials.
        final profile = await OfflineAuthService.instance.verifyOfflineLogin(
          username: username,
          password: password,
        );

        if (profile == null) {
          return LoginResult.err('Invalid username or password (offline).');
        }

        final roleStr = profile['role'] as String? ?? 'business';
        // Redundant but safe: check role again
        if (roleStr == 'admin') {
          return LoginResult.err(
            'Admin login is only supported online. Please connect to the internet to sign in.',
          );
        }

        // Load business data
        await LocalDatabase.instance.database;
        final bizRows = await db.query(
          LocalDatabase.tableLocalBusinesses,
          where: 'profile_id = ?',
          whereArgs: [profile['id']],
          limit: 1,
        );

        final biz = bizRows.isNotEmpty ? bizRows.first : null;

        final session = SessionData(
          userId: profile['id'] as String,
          fullName: profile['full_name'] as String? ?? '',
          username: profile['username'] as String?,
          email: profile['email'] as String? ?? '',
          phone: profile['phone'] as String? ?? '',
          role: roleStr,
          token: null, // No token in offline session
          password: password, // NEW: Save for auto-connect
          isOfflineSession: true,
          businessId: biz?['id'] as String?,
          businessName: biz?['business_name'] as String?,
          permitNumber: biz?['permit_number'] as String?,
          registrationNumber: biz?['registration_number'] as String?,
          street: biz?['street'] as String?,
          totalRooms: biz?['total_rooms'] as int?,
          status: biz?['status'] as String?,
          region: biz?['region'] as String?,
          cityMunicipality: biz?['city_municipality'] as String?,
          province: biz?['province'] as String?,
          barangay: biz?['barangay'] as String?,
          tradename: biz?['tradename'] as String?,
          businessLine: biz?['business_line'] is String
              ? (jsonDecode(biz!['business_line'] as String) as List)
                    .cast<String>()
              : null,
          ownerFirstName: biz?['owner_first_name'] as String?,
          ownerLastName: biz?['owner_last_name'] as String?,
          ownerMiddleName: biz?['owner_middle_name'] as String?,
          businessType: biz?['business_type'] as String?,
        );

        await SessionService.instance.save(session);
        await SessionService.instance.loadAndCache();

        return LoginResult.ok(Role.business);
      } catch (e) {
        debugPrint('❌ Offline login error: $e');
        return LoginResult.err('Offline login failed.');
      }
    }

    // ── ONLINE ATTEMPT ───────────────────────────────────────────────────────
    try {
      final response = await post('/api/auth/login', {
        'username': username,
        'password': password,
      });

      final data = handleResponse(response);
      final user = data['user'];
      final biz = data['business'];
      final token = data['token'];

      final roleStr = user['role'] as String;
      final role = roleStr == 'admin' ? Role.admin : Role.business;

      final session = SessionData(
        userId: user['id'].toString(),
        fullName: user['full_name'] ?? '',
        username: user['username'],
        email: user['email'] ?? '',
        phone: user['phone'] ?? '',
        role: roleStr,
        token: token,
        password: password, // NEW: Save for auto-connect
        isOfflineSession: false,
        businessId: biz?['id']?.toString(),
        businessName: biz?['business_name'],
        permitNumber: biz?['permit_number'],
        registrationNumber: biz?['registration_number'],
        street: biz?['street'],
        totalRooms: biz?['total_rooms'] != null
            ? int.tryParse(biz!['total_rooms'].toString())
            : null,
        permitFileUrl: biz?['permit_file_url'],
        validIdUrl: biz?['valid_id_url'],
        businessType: biz?['business_type'],
        status: biz?['status'],
        remarks: biz?['remarks'],
        region: biz?['region'],
        cityMunicipality: biz?['city_municipality'],
        province: biz?['province'],
        barangay: biz?['barangay'],
        tradename: biz?['tradename'],
        businessLine: biz?['business_line'] is String
            ? (jsonDecode(biz!['business_line']) as List).cast<String>()
            : (biz?['business_line'] as List?)?.cast<String>(),
        ownerFirstName: biz?['owner_first_name'],
        ownerLastName: biz?['owner_last_name'],
        ownerMiddleName: biz?['owner_middle_name'],
      );

      // Cache for future offline login
      await OfflineAuthService.instance.cacheProfile(
        id: user['id'].toString(),
        username: user['username'],
        password: password,
        fullName: user['full_name'],
        email: user['email'],
        phone: user['phone'],
        role: user['role'],
        business: biz,
      );

      await SessionService.instance.save(session);
      await SessionService.instance.loadAndCache();

      return LoginResult.ok(role);
    } on ApiException catch (e) {
      return LoginResult.err(e.message);
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return LoginResult.err('Something went wrong. Please try again.');
    }
  }

  // ===========================================================================
  // FORGOT PASSWORD
  // ===========================================================================

  Future<String> sendForgotPasswordOtp({required String email}) async {
    try {
      final response = await post('/api/auth/forgot-password', {
        'email': email,
      });
      handleResponse(response);
      return email.trim().toLowerCase();
    } on ApiException catch (e) {
      throw LoginApiException(e.message);
    } catch (e) {
      throw LoginApiException('Failed to send reset code. Please try again.');
    }
  }

  Future<void> resendForgotPasswordOtp({required String email}) async {
    await sendForgotPasswordOtp(email: email);
  }

  Future<void> verifyForgotPasswordOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await post('/api/auth/verify-otp', {
        'email': email,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw LoginApiException(e.message);
    } catch (e) {
      throw LoginApiException('Incorrect reset code. Please try again.');
    }
  }

  Future<void> resetPassword({
    required String email, // Need email from previous step
    required String otp, // Need OTP from previous step
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (newPassword != confirmPassword) {
      throw LoginApiException('Passwords do not match.');
    }
    try {
      final response = await post('/api/auth/reset-password', {
        'email': email,
        'otp': otp,
        'new_password': newPassword,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw LoginApiException(e.message);
    } catch (e) {
      throw LoginApiException('Failed to reset password. Please try again.');
    }
  }
}
