import 'dart:async';
import 'package:flutter/foundation.dart';
import 'base_api.dart';

enum BusinessLine {
  hotel, resort, motel, pension_inn, youth_hostel, apartment, others;
  String get dbValue => name;
  String get label => switch (this) {
    BusinessLine.hotel        => 'Hotel',
    BusinessLine.resort       => 'Resort',
    BusinessLine.motel        => 'Motel',
    BusinessLine.pension_inn  => 'Pension Inn',
    BusinessLine.youth_hostel => 'Youth Hostel',
    BusinessLine.apartment    => 'Apartment',
    BusinessLine.others       => 'Others',
  };
  static BusinessLine fromDb(String v) => BusinessLine.values.firstWhere(
    (e) => e.dbValue == v, orElse: () => BusinessLine.others);
}

enum BusinessType {
  sole_proprietorship, partnership, corporation;
  String get dbValue => name;
  String get label => switch (this) {
    BusinessType.sole_proprietorship => 'Sole Proprietorship',
    BusinessType.partnership         => 'Partnership',
    BusinessType.corporation         => 'Corporation',
  };
  static BusinessType fromDb(String v) => BusinessType.values.firstWhere(
    (e) => e.dbValue == v, orElse: () => BusinessType.sole_proprietorship);
}

enum BusinessStatus {
  pending, approved, rejected, warning;
  static BusinessStatus fromDb(String v) => BusinessStatus.values.firstWhere(
    (e) => e.name == v, orElse: () => BusinessStatus.pending);
}

class BusinessProfileApi extends BaseApi {
  Future<ProfileModel> fetchProfile() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      return ProfileModel.fromMap(data['user']);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<BusinessModel?> fetchBusiness() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      if (data['business'] == null) return null;
      return BusinessModel.fromMap(data['business']);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updateAccountInfo({
    required String fullName, required String username, required String phone,
  }) async {
    try {
      final response = await put('/api/profile', {
        'full_name': fullName, 'username': username, 'phone': phone,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updateBusinessInfo({
    required String businessId,
    required String businessName,
    String? tradename,
    String? ownerFirstName,
    String? ownerMiddleName,
    String? ownerLastName,
    required BusinessType businessType,
    required List<BusinessLine> businessLine,
    required int totalRooms,
    String? street,
    String? barangay,
    String? cityMunicipality,
    String? province,
    String? region,
    String? permitNumber,
    String? registrationNumber,
  }) async {
    try {
      final response = await put('/api/business', {
        'business_name': businessName,
        'tradename': tradename,
        'owner_first_name': ownerFirstName,
        'owner_middle_name': ownerMiddleName,
        'owner_last_name': ownerLastName,
        'business_type': businessType.dbValue,
        'business_line': businessLine.map((e) => e.dbValue).toList(),
        'total_rooms': totalRooms,
        'street': street,
        'barangay': barangay,
        'city_municipality': cityMunicipality,
        'province': province,
        'region': region,
        'permit_number': permitNumber,
        'registration_number': registrationNumber,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

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
        // OTP-based reset (logged in)
        final profile = await fetchProfile();
        final response = await post('/api/auth/reset-password', {
          'email': profile.email,
          'otp': otp,
          'new_password': newPassword,
        });
        handleResponse(response);
      } else if (oldPassword != null) {
        // Traditional change with old password
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
}

class ProfileModel {
  const ProfileModel({
    required this.id, required this.fullName, required this.username,
    required this.email, required this.phone, required this.role,
  });
  final String id, fullName, username, email, phone, role;
  factory ProfileModel.fromMap(Map<String, dynamic> map) => ProfileModel(
    id: map['id'], fullName: map['full_name'], username: map['username'],
    email: map['email'] ?? '', phone: map['phone'] ?? '', role: map['role'],
  );
  ProfileModel copyWith({String? fullName, String? username, String? email, String? phone}) => ProfileModel(
    id: id, fullName: fullName ?? this.fullName, username: username ?? this.username,
    email: email ?? this.email, phone: phone ?? this.phone, role: role,
  );
}

class BusinessModel {
  const BusinessModel({
    required this.id, required this.userId, required this.businessName,
    this.tradename, this.permitNumber, this.registrationNumber,
    this.street, this.barangay, this.cityMunicipality, this.province, this.region,
    required this.totalRooms, this.permitFileUrl, this.validIdUrl,
    required this.status, this.remarks, required this.businessLine,
    this.ownerFirstName, this.ownerMiddleName, this.ownerLastName,
    required this.businessType,
  });
  final String id, userId, businessName;
  final String? tradename, permitNumber, registrationNumber, street, barangay, cityMunicipality, province, region;
  final int totalRooms;
  final String? permitFileUrl, validIdUrl, remarks, ownerFirstName, ownerMiddleName, ownerLastName;
  final BusinessStatus status;
  final List<BusinessLine> businessLine;
  final BusinessType businessType;

  factory BusinessModel.fromMap(Map<String, dynamic> map) {
    final lineRaw = (map['business_line'] is String 
        ? (map['business_line'] as String).replaceAll('[', '').replaceAll(']', '').split(',')
        : map['business_line'] as List?)?.cast<String>() ?? [];
    
    return BusinessModel(
      id: map['id'], userId: map['user_id'], businessName: map['business_name'],
      tradename: map['tradename'], permitNumber: map['permit_number'],
      registrationNumber: map['registration_number'], street: map['street'],
      barangay: map['barangay'], cityMunicipality: map['city_municipality'],
      province: map['province'], region: map['region'],
      totalRooms: map['total_rooms'] ?? 0, permitFileUrl: map['permit_file_url'],
      validIdUrl: map['valid_id_url'], status: BusinessStatus.fromDb(map['status'] ?? 'pending'),
      remarks: map['remarks'],
      businessLine: lineRaw.map((e) => BusinessLine.fromDb(e.trim().replaceAll('"', ''))).toList(),
      ownerFirstName: map['owner_first_name'], ownerMiddleName: map['owner_middle_name'],
      ownerLastName: map['owner_last_name'],
      businessType: BusinessType.fromDb(map['business_type'] ?? 'sole_proprietorship'),
    );
  }
}

class ProfileApiException implements Exception {
  final String message;
  const ProfileApiException(this.message);
  @override
  String toString() => message;
}