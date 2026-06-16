import 'dart:async';
import 'package:flutter/foundation.dart';
import 'base_api.dart';

class AdminProfileApi extends BaseApi {
  // ────────────────────────────────────────────────────────────────────────────
  //  1. FETCH PROFILE
  // ────────────────────────────────────────────────────────────────────────────

  Future<ProfileModel> fetchProfile() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      return ProfileModel.fromMap(data['user']);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    } catch (e) {
      throw ProfileApiException('Failed to load profile: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  2. UPDATE ACCOUNT INFO
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> updateAccountInfo({
    required String fullName,
    required String username,
    required String phone,
  }) async {
    try {
      final response = await put('/api/profile', {
        'full_name': fullName,
        'username': username,
        'phone': phone,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  3. CHANGE PASSWORD
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> sendPasswordChangeOtp() async {
    try {
      final response = await post('/api/send-email-otp', {});
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> verifyPasswordChangeOtp({required String otp}) async {
    try {
      final profile = await fetchProfile();
      final response = await post('/api/auth/verify-otp', {
        'email': profile.email,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updatePassword({
    required String newPassword,
    required String confirmPassword,
    String? otp,
    String? oldPassword,
  }) async {
    if (newPassword != confirmPassword) {
      throw const ProfileApiException('Passwords do not match.');
    }
    try {
      if (otp != null) {
        final profile = await fetchProfile();
        final response = await post('/api/auth/reset-password', {
          'email': profile.email,
          'otp': otp,
          'new_password': newPassword,
        });
        handleResponse(response);
      } else if (oldPassword != null) {
        final response = await post('/api/change-password', {
          'old_password': oldPassword,
          'new_password': newPassword,
        });
        handleResponse(response);
      } else {
        throw const ProfileApiException('Verification required to change password.');
      }
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  4. CHANGE EMAIL
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> sendEmailChangeOtp() async {
    try {
      final response = await post('/api/send-email-otp', {});
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> verifyEmailChangeOtp({required String otp}) async {
    try {
      final profile = await fetchProfile();
      final response = await post('/api/auth/verify-otp', {
        'email': profile.email,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updateEmail({required String newEmail, required String otp}) async {
    try {
      final response = await put('/api/update-email', {
        'new_email': newEmail,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }
}

class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
  });

  final String id;
  final String fullName;
  final String username;
  final String email;
  final String phone;
  final String role;

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'],
      fullName: map['full_name'],
      username: map['username'],
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'],
    );
  }
}

class ProfileApiException implements Exception {
  final String message;
  const ProfileApiException(this.message);
  @override
  String toString() => message;
}