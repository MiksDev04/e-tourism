// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:app/api/login_api.dart';
import 'package:app/core/services/connectivity_service.dart';
import '../../../router/app_routes.dart';
import '../../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Login Page
// ─────────────────────────────────────────────────────────────────────────────

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoginScreen());
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0, -0.3),
              radius: 1.2,
              colors: [AppColors.activeNavBg, AppColors.backgroundDark],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _AppLogo(),
                    SizedBox(height: 16),
                    _AppTitle(),
                    SizedBox(height: 40),
                    _LoginCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  App Logo & Title
// ─────────────────────────────────────────────────────────────────────────────

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  static const _logoAsset = 'assets/images/tourism_office_logo.jpg';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.textWhite,
        border: Border.all(color: AppColors.primaryCyan.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
     child: ClipOval(
        child: Image.asset(
          _logoAsset,
          fit: BoxFit.cover,
          semanticLabel: 'Office of the City Tourism Officer logo',
        ),
      ),
    );
  }
}

class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          'San Pablo City',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Tourism Record Management System',
          style: TextStyle(
            color: AppColors.primaryCyan,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Login Card
// ─────────────────────────────────────────────────────────────────────────────

class _LoginCard extends StatefulWidget {
  const _LoginCard();

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  final _api = LoginApi();
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Sign In ────────────────────────────────────────────────────────────────

  Future<void> _handleSignIn() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _errorMessage = 'Please enter your username and password.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _api.login(username: username, password: password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      if (result.role == Role.admin) {
        Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.businessDashboard);
      }
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  // ── Forgot Password Flow ───────────────────────────────────────────────────
  //
  //  Step 1 → _ForgotPasswordStartModal  (username input + Turnstile)
  //  Step 2 → _ForgotOtpModal            (6-pin code verification)
  //  Step 3 → _ResetPasswordModal        (new password, no old password)

  Future<void> _startForgotPasswordFlow() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ForgotPasswordStartModal(
        api: _api,
        onEmailResolved: (String email) {
          Navigator.of(context).pop();
          _openForgotOtpModal(email);
        },
      ),
    );
  }

  Future<void> _openForgotOtpModal(String email) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ForgotOtpModal(
        api: _api,
        email: email,
        onVerified: (otp) {
          Navigator.of(context).pop();
          _openResetPasswordModal(email, otp);
        },
      ),
    );
  }

  Future<void> _openResetPasswordModal(String email, String otp) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetPasswordModal(
        api: _api,
        email: email,
        otp: otp,
        onSuccess: () {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password reset successfully! Please sign in.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            'Sign In',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),

          // Username
          const _FieldLabel(label: 'Username'),
          const SizedBox(height: 8),
          _InputField(
            controller: _usernameController,
            hintText: 'Enter username',
            keyboardType: TextInputType.text,
            prefixIcon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 18),

          // Password label row — label left, "Forgot Password?" right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _FieldLabel(label: 'Password'),
              if (_isOnline)
                GestureDetector(
                  onTap: _startForgotPasswordFlow,
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: AppColors.primaryCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _PasswordField(
            controller: _passwordController,
            obscure: _obscurePassword,
            onToggle: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),

          const SizedBox(height: 18),


          // Error banner
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          _isLoading
              ? const _LoadingButton()
              : _SignInButton(onPressed: _handleSignIn),

          const SizedBox(height: 16),

          Center(
            child: GestureDetector(
              onTap: () =>
                  Navigator.pushReplacementNamed(context, AppRoutes.register),
              child: const Text(
                'Register your accommodation establishment →',
                style: TextStyle(
                  color: AppColors.primaryCyan,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Forgot Password — Step 1 Modal
//  Username input + Cloudflare Turnstile placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordStartModal extends StatefulWidget {
  const _ForgotPasswordStartModal({
    required this.api,
    required this.onEmailResolved,
  });

  final LoginApi api;
  final void Function(String email) onEmailResolved;

  @override
  State<_ForgotPasswordStartModal> createState() =>
      _ForgotPasswordStartModalState();
}

class _ForgotPasswordStartModalState extends State<_ForgotPasswordStartModal> {
  final _emailCtrl = TextEditingController();

  bool _turnstileVerified = false;
  bool _sending = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _errorMsg = null;
    });

    try {
      final email = await widget.api.sendForgotPasswordOtp(
        email: _emailCtrl.text,
      );
      if (!mounted) return;
      widget.onEmailResolved(email);
    } on LoginApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMsg = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _turnstileVerified && !_sending;
    final isCompact = _fpIsCompactDialog(context);

    return Dialog(
      insetPadding: _fpDialogInset(context),
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: _fpDialogWidth(context, 420),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _FpModalHeader(
              icon: Icons.lock_reset_rounded,
              title: 'Forgot Password',
              subtitle:
                  'Enter your email address and complete the security check to receive a reset code.',
            ),
            const Divider(color: AppColors.cardBorder, height: 28),

            // Username field
            _FpModalField(
              label: 'Email Address',
              icon: Icons.email_outlined,
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13.5,
                ),
                decoration: _fpInputDecoration().copyWith(
                  hintText: 'Enter your email address',
                  hintStyle: const TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 12.5,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            const SizedBox(height: 20),

            // Cloudflare Turnstile placeholder
            _TurnstilePlaceholder(
              onVerified: () => setState(() => _turnstileVerified = true),
            ),

            if (_errorMsg != null) ...[
              const SizedBox(height: 14),
              _FpErrorBanner(message: _errorMsg!),
            ],

            const SizedBox(height: 22),

            // Actions
            if (!isCompact)
              Row(
                children: [
                  Expanded(
                    child: _FpGradientButton(
                      icon: Icons.send_outlined,
                      label: 'Send Reset Code',
                      loading: _sending,
                      enabled: canSend && _emailCtrl.text.trim().isNotEmpty,
                      onPressed: _send,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(),
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
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FpGradientButton(
                    icon: Icons.send_outlined,
                    label: 'Send Reset Code',
                    loading: _sending,
                    enabled: canSend && _emailCtrl.text.trim().isNotEmpty,
                    onPressed: _send,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(),
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
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cloudflare Turnstile Placeholder
//
//  Visually matches the real Cloudflare widget appearance.
//  Replace the body of _handleTap() with an actual CF Turnstile WebView
//  call when integrating the real SDK.
//
//  Hook: `onVerified` is called once the challenge is passed.
// ─────────────────────────────────────────────────────────────────────────────

class _TurnstilePlaceholder extends StatefulWidget {
  const _TurnstilePlaceholder({required this.onVerified});

  /// Called once when the challenge is successfully passed.
  /// Replace the simulated delay with a real Turnstile token verification.
  final VoidCallback onVerified;

  @override
  State<_TurnstilePlaceholder> createState() => _TurnstilePlaceholderState();
}

class _TurnstilePlaceholderState extends State<_TurnstilePlaceholder> {
  // States: idle → verifying → verified
  bool _verifying = false;
  bool _verified = false;

  Future<void> _handleTap() async {
    if (_verified || _verifying) return;

    setState(() => _verifying = true);

    // ── INTEGRATION POINT ──────────────────────────────────────────────────
    // Replace this delay with your actual Turnstile WebView / HTTP call.
    // When you get a valid token back, call widget.onVerified().
    // ──────────────────────────────────────────────────────────────────────
    await Future.delayed(const Duration(milliseconds: 1400));

    if (!mounted) return;
    setState(() {
      _verifying = false;
      _verified = true;
    });
    widget.onVerified();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _verified
                ? AppColors.primaryCyan.withOpacity(0.6)
                : AppColors.inputBorder,
            width: _verified ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox area
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _verified
                    ? AppColors.primaryCyan.withOpacity(0.15)
                    : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _verified
                      ? AppColors.primaryCyan
                      : AppColors.inputBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: _verifying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: AppColors.primaryCyan,
                        ),
                      )
                    : _verified
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.primaryCyan,
                        size: 16,
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            const SizedBox(width: 12),

            // Label
            Expanded(
              child: Text(
                _verified
                    ? 'Verified — you\'re human!'
                    : _verifying
                    ? 'Verifying…'
                    : 'I\'m not a robot',
                style: TextStyle(
                  color: _verified ? AppColors.primaryCyan : AppColors.textGray,
                  fontSize: 13,
                  fontWeight: _verified ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),

            // Cloudflare branding placeholder
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // CF logo — simple geometric stand-in
                Container(
                  width: 28,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: const Color(0xFFF6821F).withOpacity(0.15),
                    border: Border.all(
                      color: const Color(0xFFF6821F).withOpacity(0.35),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'CF',
                      style: TextStyle(
                        color: Color(0xFFF6821F),
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Turnstile',
                  style: TextStyle(color: AppColors.textSubtle, fontSize: 8.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Forgot Password — Step 2 Modal  (6-pin OTP)
//  Matches the admin profile _OtpModal design exactly.
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotOtpModal extends StatefulWidget {
  const _ForgotOtpModal({
    required this.api,
    required this.email,
    required this.onVerified,
  });

  final LoginApi api;
  final String email;
  final void Function(String otp) onVerified;

  @override
  State<_ForgotOtpModal> createState() => _ForgotOtpModalState();
}

class _ForgotOtpModalState extends State<_ForgotOtpModal> {
  final List<TextEditingController> _pinCtrl = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _pinFocus = List.generate(6, (_) => FocusNode());

  bool _verifying = false;
  bool _resending = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    // OTP was already sent in Step 1; just focus the first pin box
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _pinFocus[0].requestFocus(),
    );
  }

  @override
  void dispose() {
    for (final c in _pinCtrl) c.dispose();
    for (final f in _pinFocus) f.dispose();
    super.dispose();
  }

  String get _otpValue => _pinCtrl.map((c) => c.text).join();

  void _onPinChanged(String value, int index) {
    if (value.length == 1 && index < 5) _pinFocus[index + 1].requestFocus();
    if (value.isEmpty && index > 0) _pinFocus[index - 1].requestFocus();
    setState(() {});
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _errorMsg = null;
    });
    try {
      final otp = _otpValue;
      await widget.api.verifyForgotPasswordOtp(
        email: widget.email,
        otp: otp,
      );
      if (!mounted) return;
      widget.onVerified(otp);
    } on LoginApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorMsg = 'Incorrect reset code. Please try again.';
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _errorMsg = null;
    });
    for (final c in _pinCtrl) c.clear();
    try {
      await widget.api.resendForgotPasswordOtp(email: widget.email);
      if (!mounted) return;
      setState(() => _resending = false);
      _pinFocus[0].requestFocus();
    } on LoginApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _errorMsg = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mask the email for display: j***@example.com
    final parts = widget.email.split('@');
    final maskedEmail = parts.length == 2
        ? '${parts[0][0]}***@${parts[1]}'
        : widget.email;
    final isCompact = _fpIsCompactDialog(context);
    final pinBoxWidth = isCompact ? 36.0 : 46.0;
    final pinBoxHeight = isCompact ? 48.0 : 54.0;
    final pinFontSize = isCompact ? 20.0 : 22.0;
    final pinHorizontalMargin = isCompact ? 2.0 : 4.0;

    return Dialog(
      insetPadding: _fpDialogInset(context),
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: _fpDialogWidth(context, 400),
        padding: const EdgeInsets.all(28),
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

            const Text(
              'Check Your Email',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A 6-digit reset code was sent to $maskedEmail. '
              'Enter it below to continue.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // 6-pin boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (i) => Container(
                  width: pinBoxWidth,
                  height: pinBoxHeight,
                  margin: EdgeInsets.symmetric(horizontal: pinHorizontalMargin),
                  child: TextField(
                    controller: _pinCtrl[i],
                    focusNode: _pinFocus[i],
                    maxLength: 1,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: pinFontSize,
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
              _FpErrorBanner(message: _errorMsg!),
            ],

            const SizedBox(height: 22),

            // Verify button
            SizedBox(
              width: double.infinity,
              child: _FpGradientButton(
                icon: Icons.verified_outlined,
                label: 'Verify Code',
                loading: _verifying,
                enabled: _otpValue.length == 6,
                onPressed: _verify,
              ),
            ),

            const SizedBox(height: 10),

            // Resend + Cancel
            if (!isCompact)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _resending ? null : _resend,
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
                      style: TextStyle(color: AppColors.textGray, fontSize: 12),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    onPressed: _resending ? null : _resend,
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
                      style: TextStyle(color: AppColors.textGray, fontSize: 12),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Forgot Password — Step 3 Modal  (Set New Password)
//  No old-password field — user authenticated via OTP above.
// ─────────────────────────────────────────────────────────────────────────────

class _ResetPasswordModal extends StatefulWidget {
  const _ResetPasswordModal({
    required this.api,
    required this.email,
    required this.otp,
    required this.onSuccess,
  });

  final LoginApi api;
  final String email;
  final String otp;
  final VoidCallback onSuccess;

  @override
  State<_ResetPasswordModal> createState() => _ResetPasswordModalState();
}

class _ResetPasswordModalState extends State<_ResetPasswordModal> {
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
      await widget.api.resetPassword(
        email: widget.email,
        otp: widget.otp,
        newPassword: _newPassCtrl.text,
        confirmPassword: _confirmPassCtrl.text,
      );
      if (!mounted) return;
      widget.onSuccess();
    } on LoginApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = _fpIsCompactDialog(context);

    return Dialog(
      insetPadding: _fpDialogInset(context),
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: _fpDialogWidth(context, 420),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FpModalHeader(
              icon: Icons.lock_reset_rounded,
              title: 'Set New Password',
              subtitle: 'Identity verified. Enter your new password below.',
            ),
            const Divider(color: AppColors.cardBorder, height: 28),

            _FpModalField(
              label: 'New Password',
              icon: Icons.lock_open_outlined,
              child: _FpPasswordField(
                controller: _newPassCtrl,
                obscure: _obscureNew,
                hint: 'Min. 8 chars, 1 uppercase, 1 number, 1 special',
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            const SizedBox(height: 16),

            _FpModalField(
              label: 'Confirm New Password',
              icon: Icons.check_circle_outline_rounded,
              child: _FpPasswordField(
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
              style: TextStyle(color: AppColors.textSubtle, fontSize: 10.5),
            ),

            if (_errorMsg != null) ...[
              const SizedBox(height: 14),
              _FpErrorBanner(message: _errorMsg!),
            ],

            const SizedBox(height: 22),

            if (!isCompact)
              Row(
                children: [
                  Expanded(
                    child: _FpGradientButton(
                      icon: Icons.lock_reset_rounded,
                      label: 'Reset Password',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
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
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FpGradientButton(
                    icon: Icons.lock_reset_rounded,
                    label: 'Reset Password',
                    loading: _loading,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
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
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared modal sub-widgets  (_Fp prefix = "Forgot Password" scope)
// ─────────────────────────────────────────────────────────────────────────────

class _FpModalHeader extends StatelessWidget {
  const _FpModalHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
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
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FpModalField extends StatelessWidget {
  const _FpModalField({
    required this.label,
    required this.icon,
    required this.child,
  });
  final String label;
  final IconData icon;
  final Widget child;

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

class _FpPasswordField extends StatelessWidget {
  const _FpPasswordField({
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
      decoration: _fpInputDecoration().copyWith(
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

class _FpErrorBanner extends StatelessWidget {
  const _FpErrorBanner({required this.message});
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

class _FpGradientButton extends StatelessWidget {
  const _FpGradientButton({
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

InputDecoration _fpInputDecoration() => InputDecoration(
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
);

bool _fpIsCompactDialog(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 480;

EdgeInsets _fpDialogInset(BuildContext context) => EdgeInsets.symmetric(
  horizontal: _fpIsCompactDialog(context) ? 12 : 24,
  vertical: 24,
);

double _fpDialogWidth(BuildContext context, double maxWidth) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final horizontalInset = _fpIsCompactDialog(context) ? 12.0 : 24.0;
  final availableWidth = screenWidth - (horizontalInset * 2);
  return availableWidth.clamp(280.0, maxWidth).toDouble();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Existing login-card private widgets (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textWhite, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textSubtle),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppColors.textSubtle, size: 20)
            : null,
        filled: true,
        fillColor: AppColors.inputBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryCyan,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textWhite, fontSize: 14.5),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.inputBackground,
        hintText: 'Enter password',
        hintStyle: const TextStyle(color: AppColors.textSubtle),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: AppColors.textSubtle,
          size: 20,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryCyan,
            width: 1.5,
          ),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.textSubtle,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.login_rounded, size: 18, color: Colors.white),
          label: const Text(
            'Sign In',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingButton extends StatelessWidget {
  const _LoadingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      ),
    );
  }
}
