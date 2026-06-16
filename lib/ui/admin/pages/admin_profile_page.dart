// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../shared/layouts/admin_layout.dart';
import '../../../api/admin_profile_api.dart';

// ─── Admin Profile Page ───────────────────────────────────────────────────────

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final _api = AdminProfileApi();

  // Account Info controllers (no email field — email has its own flow)
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loadingProfile = true;
  bool _savingInfo = false;
  String? _fetchError;
  int? _errorCode;

  ProfileModel? _profile;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _fetchError = null;
      _errorCode = null;
    });
    try {
      final profile = await _api.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _fullNameCtrl.text = profile.fullName;
        _usernameCtrl.text = profile.username;
        _phoneCtrl.text = profile.phone;
        _loadingProfile = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _fetchError = 'Network error.';
        _errorCode = 503;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _fetchError = 'Request timed out.';
        _errorCode = 408;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _fetchError = e.toString();
        _errorCode = 500;
      });
    }
  }

  // ── Snackbar ─────────────────────────────────────────────────────────────────

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Save account info ─────────────────────────────────────────────────────────

  Future<void> _saveAccountInfo() async {
    if (_savingInfo) return;
    setState(() => _savingInfo = true);
    try {
      await _api.updateAccountInfo(
        fullName: _fullNameCtrl.text,
        username: _usernameCtrl.text,
        phone: _phoneCtrl.text,
      );
      if (!mounted) return;
      
      // Update local session
      final currentSession = SessionService.instance.current;
      if (currentSession != null) {
        await SessionService.instance.save(currentSession.copyWith(
          fullName: _fullNameCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          phone:    _phoneCtrl.text.trim(),
        ));
      }

      final updated = await _api.fetchProfile();
      if (!mounted) return;
      setState(() => _profile = updated);
      _showSnackbar('Account information saved successfully!');
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      _showSnackbar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _savingInfo = false);
    }
  }

  // ── Change Password flow ──────────────────────────────────────────────────────

  Future<void> _startChangePasswordFlow() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpModal(
        api: _api,
        title: 'Verify Identity',
        subtitle: 'A 6-digit code was sent to your email. Enter it below to change your password.',
        onSendOtp: (api) => api.sendPasswordChangeOtp(),
        onVerifyOtp: (api, otp) => api.verifyPasswordChangeOtp(otp: otp),
        onVerified: (otp) {
          Navigator.of(context).pop();
          _openResetPasswordModal(otp);
        },
      ),
    );
  }

  Future<void> _openResetPasswordModal(String otp) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangePasswordModal(
        api: _api,
        otp: otp,
        onSuccess: () {
          Navigator.of(context).pop();
          _showSnackbar('Password updated successfully!');
        },
      ),
    );
  }

  // ── Change Email flow ─────────────────────────────────────────────────────────

  Future<void> _startChangeEmailFlow() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpModal(
        api: _api,
        title: 'Verify Identity',
        subtitle: 'A 6-digit code was sent to your current email to authorize changing your address.',
        onSendOtp: (api) => api.sendEmailChangeOtp(),
        onVerifyOtp: (api, otp) => api.verifyEmailChangeOtp(otp: otp),
        onVerified: (otp) {
          Navigator.of(context).pop();
          _openEmailModal(otp);
        },
      ),
    );
  }

  Future<void> _openEmailModal(String otp) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangeEmailModal(
        api: _api,
        otp: otp,
        currentEmail: _profile?.email ?? '',
        onSuccess: () async {
          Navigator.of(context).pop();
          // Refresh profile to show updated email
          final updated = await _api.fetchProfile();
          if (!mounted) return;
          setState(() => _profile = updated);
          _showSnackbar(
            'Email updated successfully!',
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Profile',
      selectedIndex: 5,
      onNavSelected: (_) {},
      child: _fetchError != null
          ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _loadProfile)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PageHeader(),
                  const SizedBox(height: 20),
                  if (_loadingProfile)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: CircularProgressIndicator(
                          color: AppColors.primaryCyan,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 530),
                      child: Column(
                        children: [
                          _ProfileCard(profile: _profile),
                          const SizedBox(height: 16),
                          _AccountInfoCard(
                            fullNameCtrl: _fullNameCtrl,
                            usernameCtrl: _usernameCtrl,
                            phoneCtrl: _phoneCtrl,
                            loading: _savingInfo,
                            onSave: _saveAccountInfo,
                          ),
                          const SizedBox(height: 16),
                          _SecureActionCard(
                            icon: Icons.email_outlined,
                            title: 'Email Address',
                            subtitle: _profile?.email ?? '—',
                            subtitleIsEmail: true,
                            buttonIcon: Icons.edit_outlined,
                            buttonLabel: 'Change Email',
                            onPressed: _startChangeEmailFlow,
                          ),
                          const SizedBox(height: 16),
                          _SecureActionCard(
                            icon: Icons.lock_outline_rounded,
                            title: 'Password',
                            subtitle:
                                'Update your account password securely via email OTP',
                            buttonIcon: Icons.lock_reset_rounded,
                            buttonLabel: 'Change Password',
                            onPressed: _startChangePasswordFlow,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ─── Secure Action Card ───────────────────────────────────────────────────────
// Reusable card used for both Email and Password change buttons.

class _SecureActionCard extends StatelessWidget {
  const _SecureActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonIcon,
    required this.buttonLabel,
    required this.onPressed,
    this.subtitleIsEmail = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final IconData buttonIcon;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool subtitleIsEmail;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primaryCyan.withOpacity(0.2),
                        ),
                      ),
                      child: Icon(icon, color: AppColors.primaryCyan, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: subtitleIsEmail
                                  ? AppColors.primaryCyan
                                  : AppColors.textGray,
                              fontSize: 12,
                              fontWeight: subtitleIsEmail
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _GradientButton(
                    icon: buttonIcon,
                    label: buttonLabel,
                    onPressed: onPressed,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryCyan.withOpacity(0.2),
                  ),
                ),
                child: Icon(icon, color: AppColors.primaryCyan, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: subtitleIsEmail
                            ? AppColors.primaryCyan
                            : AppColors.textGray,
                        fontSize: 12,
                        fontWeight: subtitleIsEmail
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _GradientButton(
                icon: buttonIcon,
                label: buttonLabel,
                onPressed: onPressed,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── OTP Modal  (reused for both password-change and email-change flows) ───────
//
// Caller passes:
//   onSendOtp   — which API method fires the OTP
//   onVerifyOtp — which API method verifies it
//   onVerified  — callback when OTP is confirmed (close this, open next modal)

class _OtpModal extends StatefulWidget {
  const _OtpModal({
    required this.api,
    required this.title,
    required this.subtitle,
    required this.onSendOtp,
    required this.onVerifyOtp,
    required this.onVerified,
  });

  final AdminProfileApi api;
  final String title;
  final String subtitle;
  final Future<void> Function(AdminProfileApi api) onSendOtp;
  final Future<void> Function(AdminProfileApi api, String otp) onVerifyOtp;
  final void Function(String otp) onVerified;

  @override
  State<_OtpModal> createState() => _OtpModalState();
}

class _OtpModalState extends State<_OtpModal> {
  final List<TextEditingController> _pinCtrl = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _pinFocus = List.generate(6, (_) => FocusNode());

  bool _sending = true;
  bool _verifying = false;
  bool _resending = false;
  String? _errorMsg;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    for (final c in _pinCtrl) c.dispose();
    for (final f in _pinFocus) f.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _errorMsg = null;
    });
    try {
      await widget.onSendOtp(widget.api);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _otpSent = true;
      });
      _pinFocus[0].requestFocus();
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMsg = e.message;
      });
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _resending = true;
      _errorMsg = null;
    });
    for (final c in _pinCtrl) c.clear();
    try {
      await widget.onSendOtp(widget.api);
      if (!mounted) return;
      setState(() {
        _resending = false;
        _otpSent = true;
      });
      _pinFocus[0].requestFocus();
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _errorMsg = e.message;
      });
    }
  }

  String get _otpValue => _pinCtrl.map((c) => c.text).join();

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _errorMsg = null;
    });
    try {
      final otp = _otpValue;
      await widget.onVerifyOtp(widget.api, otp);
      if (!mounted) return;
      widget.onVerified(otp);
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorMsg = e.message;
      });
    }
  }

  void _onPinChanged(String value, int index) {
    if (value.length == 1 && index < 5) _pinFocus[index + 1].requestFocus();
    if (value.isEmpty && index > 0) _pinFocus[index - 1].requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          final horizontalPadding = isCompact ? 20.0 : 28.0;
          final dialogWidth =
              constraints.hasBoundedWidth && constraints.maxWidth < 400
              ? constraints.maxWidth
              : 400.0;

          return SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(horizontalPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_read_outlined,
                      color: AppColors.primaryCyan,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sending
                        ? 'Sending a 6-digit code to your email…'
                        : widget.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sending spinner
                  if (_sending)
                    const CircularProgressIndicator(
                      color: AppColors.primaryCyan,
                    ),

                  // Pin boxes + actions
                  if (!_sending) ...[
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: isCompact ? 6 : 8,
                      runSpacing: 8,
                      children: List.generate(
                        6,
                        (i) => SizedBox(
                          width: isCompact ? 42 : 46,
                          height: 54,
                          child: TextField(
                            controller: _pinCtrl[i],
                            focusNode: _pinFocus[i],
                            maxLength: 1,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: AppColors.inputBackground,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppColors.inputBorder,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppColors.inputBorder,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppColors.primaryCyan,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (v) => _onPinChanged(v, i),
                          ),
                        ),
                      ),
                    ),

                    if (_errorMsg != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _errorMsg!),
                    ],

                    const SizedBox(height: 22),

                    SizedBox(
                      width: double.infinity,
                      child: _GradientButton(
                        icon: Icons.verified_outlined,
                        label: 'Verify Code',
                        loading: _verifying,
                        enabled: _otpValue.length == 6,
                        onPressed: _verify,
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (isCompact)
                      Column(
                        children: [
                          TextButton(
                            onPressed: _resending ? null : _resendOtp,
                            child: _resending
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.textGray,
                                    ),
                                  )
                                : const Text(
                                    'Resend Code',
                                    style: TextStyle(
                                      color: AppColors.primaryCyan,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _resending ? null : _resendOtp,
                            child: _resending
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.textGray,
                                    ),
                                  )
                                : const Text(
                                    'Resend Code',
                                    style: TextStyle(
                                      color: AppColors.primaryCyan,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          const Text(
                            '·',
                            style: TextStyle(color: AppColors.textSubtle),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Modal: Change Password ───────────────────────────────────────────────────

class _ChangePasswordModal extends StatefulWidget {
  const _ChangePasswordModal({
    required this.api,
    required this.otp,
    required this.onSuccess,
  });

  final AdminProfileApi api;
  final String otp;
  final VoidCallback onSuccess;

  @override
  State<_ChangePasswordModal> createState() => _ChangePasswordModalState();
}

class _ChangePasswordModalState extends State<_ChangePasswordModal> {
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      await widget.api.updatePassword(
        otp: widget.otp,
        newPassword: _newPassCtrl.text,
        confirmPassword: _confirmPassCtrl.text,
      );
      if (!mounted) return;
      widget.onSuccess();
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          final dialogWidth =
              constraints.hasBoundedWidth && constraints.maxWidth < 420
              ? constraints.maxWidth
              : 420.0;

          return SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isCompact ? 20 : 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ModalHeader(
                    icon: Icons.lock_reset_rounded,
                    title: 'Set New Password',
                    subtitle:
                        'Identity verified. Enter your new password below.',
                  ),
                  const Divider(color: AppColors.cardBorder, height: 28),
                  _ModalField(
                    label: 'New Password',
                    icon: Icons.lock_open_outlined,
                    child: _PasswordField(
                      controller: _newPassCtrl,
                      obscure: _obscureNew,
                      hint: 'Min. 8 chars, 1 uppercase, 1 number, 1 special',
                      onToggle: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModalField(
                    label: 'Confirm New Password',
                    icon: Icons.check_circle_outline_rounded,
                    child: _PasswordField(
                      controller: _confirmPassCtrl,
                      obscure: _obscureConfirm,
                      hint: 'Re-enter your new password',
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Min. 8 characters · 1 uppercase · 1 number · 1 special character',
                    style: TextStyle(
                      color: AppColors.textSubtle,
                      fontSize: 10.5,
                    ),
                  ),
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBanner(message: _errorMsg!),
                  ],
                  const SizedBox(height: 22),
                  _ModalActions(
                    loading: _loading,
                    confirmLabel: 'Update Password',
                    confirmIcon: Icons.lock_reset_rounded,
                    onConfirm: _submit,
                    onCancel: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Modal: Change Email ──────────────────────────────────────────────────────

class _ChangeEmailModal extends StatefulWidget {
  const _ChangeEmailModal({
    required this.api,
    required this.otp,
    required this.currentEmail,
    required this.onSuccess,
  });

  final AdminProfileApi api;
  final String otp;
  final String currentEmail;
  final VoidCallback onSuccess;

  @override
  State<_ChangeEmailModal> createState() => _ChangeEmailModalState();
}

class _ChangeEmailModalState extends State<_ChangeEmailModal> {
  final _newEmailCtrl = TextEditingController();

  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _newEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      await widget.api.updateEmail(
        newEmail: _newEmailCtrl.text,
        otp: widget.otp,
      );
      if (!mounted) return;
      widget.onSuccess();
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          final dialogWidth =
              constraints.hasBoundedWidth && constraints.maxWidth < 420
              ? constraints.maxWidth
              : 420.0;

          return SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isCompact ? 20 : 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ModalHeader(
                    icon: Icons.email_outlined,
                    title: 'Change Email Address',
                    subtitle:
                        'Identity verified. Enter your new email address below.',
                  ),
                  const Divider(color: AppColors.cardBorder, height: 28),

                  // Current email (read-only display)
                  _ModalField(
                    label: 'Current Email',
                    icon: Icons.inbox_outlined,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.inputBackground.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.inputBorder.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        widget.currentEmail,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _ModalField(
                    label: 'New Email Address',
                    icon: Icons.email_outlined,
                    child: TextField(
                      controller: _newEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13.5,
                      ),
                      decoration: _inputDecoration().copyWith(
                        hintText: 'Enter new email address',
                        hintStyle: const TextStyle(
                          color: AppColors.textSubtle,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  const Text(
                    'A confirmation link will be sent to your new email. '
                    'The change takes effect after you click it.',
                    style: TextStyle(
                      color: AppColors.textSubtle,
                      fontSize: 10.5,
                    ),
                  ),

                  if (_errorMsg != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBanner(message: _errorMsg!),
                  ],

                  const SizedBox(height: 22),
                  _ModalActions(
                    loading: _loading,
                    confirmLabel: 'Update Email',
                    confirmIcon: Icons.save_outlined,
                    onConfirm: _submit,
                    onCancel: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Shared Modal Widgets ─────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primaryCyan, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
            ],
          );
        }

        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryCyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primaryCyan, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ModalActions extends StatelessWidget {
  const _ModalActions({
    required this.loading,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.onConfirm,
    required this.onCancel,
  });
  final bool loading;
  final String confirmLabel;
  final IconData confirmIcon;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GradientButton(
                icon: confirmIcon,
                label: confirmLabel,
                loading: loading,
                onPressed: onConfirm,
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: loading ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textGray,
                  side: const BorderSide(color: AppColors.inputBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _GradientButton(
                icon: confirmIcon,
                label: confirmLabel,
                loading: loading,
                onPressed: onConfirm,
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: loading ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textGray,
                side: const BorderSide(color: AppColors.inputBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
            ),
          ],
        );
      },
    );
  }
}

class _ModalField extends StatelessWidget {
  const _ModalField({
    required this.label,
    required this.child,
    required this.icon,
  });
  final String label;
  final Widget child;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textGray, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    this.hint,
  });
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
      decoration: _inputDecoration().copyWith(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSubtle, fontSize: 12.5),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.textSubtle,
            size: 18,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Gradient Button ──────────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          color: active ? null : AppColors.inputBackground,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: ElevatedButton(
          onPressed: active ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryCyan,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile Settings',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Manage your account information',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Profile Card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final ProfileModel? profile;

  @override
  Widget build(BuildContext context) {
    final name = profile?.fullName ?? '—';
    final email = profile?.email ?? '—';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return _SectionCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                email,
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _RoleBadge(role: profile?.role ?? 'admin'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  String get _label => role
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryCyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryCyan.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primaryCyan,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: const TextStyle(
              color: AppColors.primaryCyan,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Account Info Card ────────────────────────────────────────────────────────

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({
    required this.fullNameCtrl,
    required this.usernameCtrl,
    required this.phoneCtrl,
    required this.loading,
    required this.onSave,
  });
  final TextEditingController fullNameCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController phoneCtrl;
  final bool loading;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                color: AppColors.primaryCyan,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Account Information',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Full Name',
                  child: _InputField(controller: fullNameCtrl),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _LabeledField(
                  label: 'Username',
                  child: _InputField(controller: usernameCtrl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LabeledField(
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            child: _PhoneInputField(controller: phoneCtrl),
          ),
          const SizedBox(height: 22),
          _GradientButton(
            icon: Icons.save_outlined,
            label: 'Save Changes',
            loading: loading,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}

// ─── Shared Section Card ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

// ─── Labeled Field ────────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.icon,
    this.hint,
  });
  final String label;
  final Widget child;
  final IconData? icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.textGray, size: 14),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 10.5),
          ),
        ],
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

// ─── Input Field ──────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    this.keyboardType = TextInputType.text,
  });
  final TextEditingController controller;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
      decoration: _inputDecoration(),
    );
  }
}

class _PhoneInputField extends StatelessWidget {
  const _PhoneInputField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
      decoration: _inputDecoration(),
    );
  }
}

// ─── Shared Input Decoration ──────────────────────────────────────────────────

InputDecoration _inputDecoration() => InputDecoration(
  filled: true,
  fillColor: AppColors.inputBackground,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.inputBorder),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.inputBorder),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.primaryCyan, width: 1.5),
  ),
  disabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: AppColors.inputBorder.withOpacity(0.4)),
  ),
);
