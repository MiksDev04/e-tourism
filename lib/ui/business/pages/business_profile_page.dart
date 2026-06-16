// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../shared/layouts/business_layout.dart';
import '../widgets/offline_state.dart';
import '../../../api/business_profile_api.dart';
import '../../../api/login_api.dart';

// ─── Fixed San Pablo location values ──────────────────────────────────────────

const _fixedCityMunicipality = 'San Pablo City';
const _fixedProvince = 'Laguna';
const _fixedRegion = 'Region IV-A';

const _sanPabloBarangays = <String>[
  'Atisan',
  'Bagong Bayan II-A',
  'Bagong Pook VI-C',
  'Barangay I-A',
  'Barangay I-B',
  'Barangay II-A',
  'Barangay II-B',
  'Barangay II-C',
  'Barangay II-D',
  'Barangay II-E',
  'Barangay II-F',
  'Barangay III-A',
  'Barangay III-B',
  'Barangay III-C',
  'Barangay III-D',
  'Barangay III-E',
  'Barangay III-F',
  'Barangay IV-A',
  'Barangay IV-B',
  'Barangay IV-C',
  'Barangay V-A',
  'Barangay V-B',
  'Barangay V-C',
  'Barangay V-D',
  'Barangay VI-A',
  'Barangay VI-B',
  'Barangay VI-D',
  'Barangay VI-E',
  'Barangay VII-A',
  'Barangay VII-B',
  'Barangay VII-C',
  'Barangay VII-D',
  'Barangay VII-E',
  'Bautista',
  'Concepcion',
  'Del Remedio',
  'Dolores',
  'San Antonio 1',
  'San Antonio 2',
  'San Bartolome',
  'San Buenaventura',
  'San Crispin',
  'San Cristobal',
  'San Diego',
  'San Francisco',
  'San Gabriel',
  'San Gregorio',
  'San Ignacio',
  'San Isidro',
  'San Joaquin',
  'San Jose',
  'San Juan',
  'San Lorenzo',
  'San Lucas 1',
  'San Lucas 2',
  'San Marcos',
  'San Mateo',
  'San Miguel',
  'San Nicolas',
  'San Pedro',
  'San Rafael',
  'San Roque',
  'San Vicente',
  'Santa Ana',
  'Santa Catalina',
  'Santa Cruz',
  'Santa Elena',
  'Santa Felomina',
  'Santa Isabel',
  'Santa Maria',
  'Santa Maria Magdalena',
  'Santa Monica',
  'Santa Veronica',
  'Santiago I',
  'Santiago II',
  'Santisimo Rosario',
  'Santo Angel',
  'Santo Cristo',
  'Santo Niño',
  'Soledad',
];

// ─── Business Profile Page ────────────────────────────────────────────────────

class BusinessProfilePage extends StatefulWidget {
  const BusinessProfilePage({super.key});

  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final _api = BusinessProfileApi();

  // ── Connectivity ──────────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // ── Load state ────────────────────────────────────────────────────────────
  bool _isLoading = true;
  ProfileModel? _profile;
  BusinessModel? _business;

  // ── Save state ────────────────────────────────────────────────────────────
  bool _isSavingAccount  = false;
  bool _isSavingBusiness = false;

  // ── Account controllers ───────────────────────────────────────────────────
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();

  // ── Business controllers ──────────────────────────────────────────────────
  final _businessNameCtrl    = TextEditingController();
  final _tradenameCtrl       = TextEditingController();
  final _ownerFirstCtrl      = TextEditingController();
  final _ownerMiddleCtrl     = TextEditingController();
  final _ownerLastCtrl       = TextEditingController();
  final _totalRoomsCtrl      = TextEditingController(text: '0');
  final _streetCtrl          = TextEditingController();
  final _barangayCtrl        = TextEditingController();
  final _cityCtrl            = TextEditingController();
  final _provinceCtrl        = TextEditingController();
  final _regionCtrl          = TextEditingController();
  final _permitNumberCtrl    = TextEditingController();
  final _registrationCtrl    = TextEditingController();

  // ── Business selection ────────────────────────────────────────────────────
  BusinessType _selectedBusinessType = BusinessType.sole_proprietorship;
  List<BusinessLine> _selectedLines  = [BusinessLine.hotel];
  String? _selectedBarangay;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _subscribeConnectivity();
    _loadData(); // handles its own offline pre-check — no separate prime needed
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    for (final c in [
      _fullNameCtrl, _usernameCtrl, _emailCtrl, _phoneCtrl,
      _businessNameCtrl, _tradenameCtrl, _ownerFirstCtrl, _ownerMiddleCtrl,
      _ownerLastCtrl, _totalRoomsCtrl, _streetCtrl, _barangayCtrl,
      _cityCtrl, _provinceCtrl, _regionCtrl, _permitNumberCtrl,
      _registrationCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeConnectivity() {
    _connectivitySub =
        ConnectivityService.instance.onlineStream.listen((isOnline) async {
      if (!mounted) return;

      if (!isOnline) {
        // Just went offline — show the offline banner immediately.
        if (_isOffline) return; // already showing it, no-op
        setState(() {
          _isOffline = true;
          _isLoading = false;
        });
        return;
      }

      // Connection restored — only reload if we were in offline state
      // and not already mid-load (matches messages page guard exactly).
      if (!_isOffline || _isLoading) return;

      setState(() => _isOffline = false);
      _loadData();
    });
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    // Clear offline banner and show spinner immediately on every load attempt.
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    // ── Pre-check connectivity ─────────────────────────────────────────────
    final online = await ConnectivityService.instance.isOnline;
    if (!mounted) return;
    if (!online) {
      setState(() { _isOffline = true; _isLoading = false; });
      return;
    }

    var session = await SessionService.instance.loadAndCache();

    // Check if we need to auto-authenticate (offline to online transition)
    if (session != null && (session.token == null || session.isOfflineSession)) {
      if (session.username != null && session.password != null) {
        final success = await LoginApi().backgroundAuth(
          username: session.username!,
          password: session.password!,
        );
        if (success) {
          session = SessionService.instance.current;
        }
      }
    }

    // ── Fetch ──────────────────────────────────────────────────────────────
    try {
      final results = await Future.wait([
        _api.fetchProfile(),
        _api.fetchBusiness(),
      ]);
      if (!mounted) return;
      _profile  = results[0] as ProfileModel;
      _business = results[1] as BusinessModel?;
      _populate();
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      if (isNetworkError(e)) {
        setState(() { _isOffline = true; });
        return;
      }
      // Non-network API error — loading stops, page shows whatever was loaded.
    } catch (e) {
      if (!mounted) return;
      if (isNetworkError(e)) {
        setState(() { _isOffline = true; });
        return;
      }
    } finally {
      // Always clears the spinner. The offline paths above set
      // _isLoading = false themselves before returning, but this
      // harmlessly sets it again — keeps the finally block simple.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populate() {
    final p = _profile!;
    _fullNameCtrl.text = p.fullName;
    _usernameCtrl.text = p.username;
    _emailCtrl.text    = p.email;
    _phoneCtrl.text    = p.phone;

    final b = _business;
    if (b == null) return;
    _businessNameCtrl.text = b.businessName;
    _tradenameCtrl.text    = b.tradename ?? '';
    _ownerFirstCtrl.text   = b.ownerFirstName ?? '';
    _ownerMiddleCtrl.text  = b.ownerMiddleName ?? '';
    _ownerLastCtrl.text    = b.ownerLastName ?? '';
    _totalRoomsCtrl.text   = b.totalRooms.toString();
    _streetCtrl.text       = b.street ?? '';
    
    // Fixed location values
    _barangayCtrl.text     = b.barangay ?? '';
    _cityCtrl.text         = _fixedCityMunicipality;
    _provinceCtrl.text     = _fixedProvince;
    _regionCtrl.text       = _fixedRegion;

    _permitNumberCtrl.text = b.permitNumber ?? '';
    _registrationCtrl.text = b.registrationNumber ?? '';
    setState(() {
      _selectedBusinessType = b.businessType;
      _selectedLines        = b.businessLine.isNotEmpty
          ? b.businessLine : [BusinessLine.hotel];

      // Handle barangay selection
      if (_sanPabloBarangays.contains(b.barangay)) {
        _selectedBarangay = b.barangay;
      } else if (_sanPabloBarangays.isNotEmpty) {
        _selectedBarangay = _sanPabloBarangays.first;
        _barangayCtrl.text = _selectedBarangay!;
      }
    });
  }

  // ── Save actions ──────────────────────────────────────────────────────────

  Future<void> _saveAccountInfo() async {
    setState(() => _isSavingAccount = true);
    try {
      await _api.updateAccountInfo(
        fullName: _fullNameCtrl.text,
        username: _usernameCtrl.text,
        phone:    _phoneCtrl.text,
      );
      _profile = _profile?.copyWith(
        fullName: _fullNameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        phone:    _phoneCtrl.text.trim(),
      );
      _showSnack('Account information updated.', isError: false);
    } on ProfileApiException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _isSavingAccount = false);
    }
  }

  Future<void> _saveBusinessInfo() async {
    if (_business == null) {
      _showSnack('No business record found.');
      return;
    }
    setState(() => _isSavingBusiness = true);
    try {
      await _api.updateBusinessInfo(
        businessId:         _business!.id,
        businessName:       _businessNameCtrl.text,
        tradename:          _tradenameCtrl.text,
        ownerFirstName:     _ownerFirstCtrl.text,
        ownerMiddleName:    _ownerMiddleCtrl.text,
        ownerLastName:      _ownerLastCtrl.text,
        businessType:       _selectedBusinessType,
        businessLine:       _selectedLines,
        totalRooms:         int.tryParse(_totalRoomsCtrl.text) ?? 0,
        street:             _streetCtrl.text,
        barangay:           _selectedBarangay ?? _barangayCtrl.text,
        cityMunicipality:   _fixedCityMunicipality,
        province:           _fixedProvince,
        region:             _fixedRegion,
        permitNumber:       _permitNumberCtrl.text,
        registrationNumber: _registrationCtrl.text,
      );
      _showSnack('Business information updated.', isError: false);
    } on ProfileApiException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _isSavingBusiness = false);
    }
  }

  // ── Dialog launchers ──────────────────────────────────────────────────────

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordChangeDialog(api: _api),
    );
  }

  void _showChangeEmailDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmailChangeDialog(
        api:          _api,
        currentEmail: _profile?.email ?? '',
        onSuccess: (newEmail) {
          setState(() {
            _emailCtrl.text = newEmail;
            _profile = _profile?.copyWith(email: newEmail);
          });
        },
      ),
    );
  }

  // ── Snackbar helper ───────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BusinessLayout(
      title: 'Profile',
      selectedIndex: 5,
      onNavSelected: (_) {},
      child: _isOffline
          ? OfflineState(onRetry: _loadData)
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(isNarrow ? 16 : 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PageHeader(),
                              const SizedBox(height: 20),
                              _BusinessCard(business: _business),
                              const SizedBox(height: 16),
                              _AccountInfoCard(
                                fullNameCtrl: _fullNameCtrl,
                                usernameCtrl: _usernameCtrl,
                                emailCtrl:    _emailCtrl,
                                phoneCtrl:    _phoneCtrl,
                                isSaving:     _isSavingAccount,
                                onSave:       _saveAccountInfo,
                                isNarrow:     isNarrow,
                              ),
                              const SizedBox(height: 16),
                              _SecurityCard(
                                onChangePassword: _showChangePasswordDialog,
                                onChangeEmail:    _showChangeEmailDialog,
                              ),
                              const SizedBox(height: 16),
                              _BusinessInfoCard(
                                businessNameCtrl:   _businessNameCtrl,
                                tradenameCtrl:      _tradenameCtrl,
                                ownerFirstCtrl:     _ownerFirstCtrl,
                                ownerMiddleCtrl:    _ownerMiddleCtrl,
                                ownerLastCtrl:      _ownerLastCtrl,
                                totalRoomsCtrl:     _totalRoomsCtrl,
                                streetCtrl:         _streetCtrl,
                                barangayCtrl:       _barangayCtrl,
                                cityCtrl:           _cityCtrl,
                                provinceCtrl:       _provinceCtrl,
                                regionCtrl:         _regionCtrl,
                                permitNumberCtrl:   _permitNumberCtrl,
                                registrationCtrl:   _registrationCtrl,
                                selectedBusinessType: _selectedBusinessType,
                                selectedLines:        _selectedLines,
                                onBusinessTypeChanged: (v) => setState(
                                  () => _selectedBusinessType =
                                      v ?? BusinessType.sole_proprietorship),
                                onLinesChanged: (v) =>
                                    setState(() => _selectedLines = v),
                                isSaving:  _isSavingBusiness,
                                onSave:    _saveBusinessInfo,
                                isNarrow:  isNarrow,
                                hasRecord: _business != null,
                                selectedBarangay: _selectedBarangay,
                                onBarangayChanged: (v) => setState(() {
                                  _selectedBarangay = v;
                                  if (v != null) _barangayCtrl.text = v;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile & Settings',
              style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'Manage your account and business information',
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Business Card (identity) ─────────────────────────────────────────────────

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business});
  final BusinessModel? business;

  @override
  Widget build(BuildContext context) {
    final name   = business?.businessName ?? '—';
    final line   = business?.businessLine.firstOrNull?.label ?? '';
    final status = business?.status ?? BusinessStatus.pending;

    return _SectionCard(
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.business_center_outlined,
                  color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(line,
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 12.5)),
              ],
            ),
          ),
          _StatusBadge(status: status),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final BusinessStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, border, dot, text, label) = switch (status) {
      BusinessStatus.approved  => (
        const Color(0xFF0D3B26), const Color(0xFF1A5C3A),
        const Color(0xFF34D399), const Color(0xFF34D399), 'Approved'),
      BusinessStatus.rejected  => (
        const Color(0xFF3B0D0D), const Color(0xFF5C1A1A),
        const Color(0xFFF87171), const Color(0xFFF87171), 'Rejected'),
      BusinessStatus.warning => (
        const Color(0xFF3B2A0D), const Color(0xFF5C3F1A),
        const Color(0xFFFBBF24), const Color(0xFFFBBF24), 'Suspended'),
      BusinessStatus.pending   => (
        const Color(0xFF1A1F3B), const Color(0xFF2A3260),
        const Color(0xFF818CF8), const Color(0xFF818CF8), 'Pending'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: text, fontSize: 12, fontWeight: FontWeight.w600)),
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
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.isSaving,
    required this.onSave,
    required this.isNarrow,
  });

  final TextEditingController fullNameCtrl, usernameCtrl, emailCtrl, phoneCtrl;
  final bool isSaving;
  final VoidCallback onSave;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.person_outline_rounded, label: 'Account Information'),
          const SizedBox(height: 20),
          if (isNarrow) ...[
            _LabeledField(label: 'Full Name',
                child: _InputField(controller: fullNameCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Username',
                child: _InputField(controller: usernameCtrl)),
          ] else
            Row(children: [
              Expanded(child: _LabeledField(label: 'Full Name',
                  child: _InputField(controller: fullNameCtrl))),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(label: 'Username',
                  child: _InputField(controller: usernameCtrl))),
            ]),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Email',
            icon: Icons.mail_outline_rounded,
            child: _ReadonlyField(
              controller: emailCtrl,
              tooltip: 'Use "Change Email" in Security to update',
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Phone',
            icon: Icons.phone_outlined,
            child: _InputField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone),
          ),
          const SizedBox(height: 22),
          _ActionButton(
            icon: Icons.save_outlined,
            label: 'Save Account',
            isSaving: isSaving,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}

// ─── Security Card ────────────────────────────────────────────────────────────

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.onChangePassword,
    required this.onChangeEmail,
  });

  final VoidCallback onChangePassword;
  final VoidCallback onChangeEmail;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(icon: Icons.lock_outline_rounded, label: 'Security'),
          const SizedBox(height: 20),
          _SecurityRow(
            icon: Icons.password_outlined,
            title: 'Password',
            subtitle: 'Change your account password',
            buttonLabel: 'Change Password',
            onTap: onChangePassword,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 12),
          _SecurityRow(
            icon: Icons.alternate_email_outlined,
            title: 'Email Address',
            subtitle: 'Update your login email',
            buttonLabel: 'Change Email',
            onTap: onChangeEmail,
          ),
        ],
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle, buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.inputBackground,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Icon(icon, color: AppColors.primaryCyan, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 12)),
            ],
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primaryCyan.withOpacity(0.4)),
            ),
            child: Text(buttonLabel,
                style: const TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

// ─── Business Info Card ───────────────────────────────────────────────────────

class _BusinessInfoCard extends StatelessWidget {
  const _BusinessInfoCard({
    required this.businessNameCtrl,
    required this.tradenameCtrl,
    required this.ownerFirstCtrl,
    required this.ownerMiddleCtrl,
    required this.ownerLastCtrl,
    required this.totalRoomsCtrl,
    required this.streetCtrl,
    required this.barangayCtrl,
    required this.cityCtrl,
    required this.provinceCtrl,
    required this.regionCtrl,
    required this.permitNumberCtrl,
    required this.registrationCtrl,
    required this.selectedBusinessType,
    required this.selectedLines,
    required this.onBusinessTypeChanged,
    required this.onLinesChanged,
    required this.isSaving,
    required this.onSave,
    required this.isNarrow,
    required this.hasRecord,
    required this.selectedBarangay,
    required this.onBarangayChanged,
  });

  final TextEditingController businessNameCtrl, tradenameCtrl;
  final TextEditingController ownerFirstCtrl, ownerMiddleCtrl, ownerLastCtrl;
  final TextEditingController totalRoomsCtrl;
  final TextEditingController streetCtrl, barangayCtrl, cityCtrl;
  final TextEditingController provinceCtrl, regionCtrl;
  final TextEditingController permitNumberCtrl, registrationCtrl;
  final BusinessType selectedBusinessType;
  final List<BusinessLine> selectedLines;
  final ValueChanged<BusinessType?> onBusinessTypeChanged;
  final ValueChanged<List<BusinessLine>> onLinesChanged;
  final bool isSaving;
  final VoidCallback onSave;
  final bool isNarrow;
  final bool hasRecord;
  final String? selectedBarangay;
  final ValueChanged<String?> onBarangayChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(icon: Icons.store_outlined, label: 'Business Information'),
          const SizedBox(height: 20),

          // ── Business Identity ─────────────────────────────────────────────
          const _SubLabel(label: 'Identity'),
          const SizedBox(height: 12),
          if (isNarrow) ...[
            _LabeledField(label: 'Business Name',
                child: _InputField(controller: businessNameCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Trade Name / DBA (optional)',
                child: _InputField(controller: tradenameCtrl)),
          ] else
            Row(children: [
              Expanded(child: _LabeledField(label: 'Business Name',
                  child: _InputField(controller: businessNameCtrl))),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(
                  label: 'Trade Name / DBA (optional)',
                  child: _InputField(controller: tradenameCtrl))),
            ]),
          const SizedBox(height: 14),

          if (isNarrow) ...[
            _LabeledField(
              label: 'Business Type',
              child: _EnumDropdown<BusinessType>(
                value: selectedBusinessType,
                items: BusinessType.values,
                labelOf: (e) => e.label,
                onChanged: onBusinessTypeChanged,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Total Rooms / Units',
              icon: Icons.bed_outlined,
              child: _InputField(
                  controller: totalRoomsCtrl,
                  keyboardType: TextInputType.number),
            ),
          ] else
            Row(children: [
              Expanded(child: _LabeledField(
                label: 'Business Type',
                child: _EnumDropdown<BusinessType>(
                  value: selectedBusinessType,
                  items: BusinessType.values,
                  labelOf: (e) => e.label,
                  onChanged: onBusinessTypeChanged,
                ),
              )),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(
                label: 'Total Rooms / Units',
                icon: Icons.bed_outlined,
                child: _InputField(
                    controller: totalRoomsCtrl,
                    keyboardType: TextInputType.number),
              )),
            ]),
          const SizedBox(height: 14),

          _LabeledField(
            label: 'Business Line',
            child: _BusinessLineChips(
              selected: selectedLines,
              onChanged: onLinesChanged,
            ),
          ),
          const SizedBox(height: 20),

          // ── Owner ─────────────────────────────────────────────────────────
          const _SubLabel(label: 'Owner'),
          const SizedBox(height: 12),
          if (isNarrow) ...[
            _LabeledField(label: 'First Name',
                child: _InputField(controller: ownerFirstCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Middle Name (optional)',
                child: _InputField(controller: ownerMiddleCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Last Name',
                child: _InputField(controller: ownerLastCtrl)),
          ] else ...[
            Row(children: [
              Expanded(child: _LabeledField(label: 'First Name',
                  child: _InputField(controller: ownerFirstCtrl))),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(label: 'Middle Name (optional)',
                  child: _InputField(controller: ownerMiddleCtrl))),
            ]),
            const SizedBox(height: 14),
            _LabeledField(label: 'Last Name',
                child: _InputField(controller: ownerLastCtrl)),
          ],
          const SizedBox(height: 20),

          // ── Address ───────────────────────────────────────────────────────
          const _SubLabel(label: 'Address'),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'Street',
            icon: Icons.location_on_outlined,
            child: _InputField(controller: streetCtrl),
          ),
          const SizedBox(height: 14),
          if (isNarrow) ...[
            _LabeledField(
              label: 'Barangay',
              child: _EnumDropdown<String?>(
                value: selectedBarangay,
                items: _sanPabloBarangays,
                labelOf: (e) => e ?? '',
                onChanged: onBarangayChanged,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(label: 'City / Municipality',
                child: _ReadonlyField(controller: cityCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Province',
                child: _ReadonlyField(controller: provinceCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Region',
                child: _ReadonlyField(controller: regionCtrl)),
          ] else ...[
            Row(children: [
              Expanded(child: _LabeledField(
                label: 'Barangay',
                child: _EnumDropdown<String?>(
                  value: selectedBarangay,
                  items: _sanPabloBarangays,
                  labelOf: (e) => e ?? '',
                  onChanged: onBarangayChanged,
                ),
              )),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(label: 'City / Municipality',
                  child: _ReadonlyField(controller: cityCtrl))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _LabeledField(label: 'Province',
                  child: _ReadonlyField(controller: provinceCtrl))),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(label: 'Region',
                  child: _ReadonlyField(controller: regionCtrl))),
            ]),
          ],
          const SizedBox(height: 20),

          // ── Registration ──────────────────────────────────────────────────
          const _SubLabel(label: 'Registration'),
          const SizedBox(height: 12),
          if (isNarrow) ...[
            _LabeledField(label: 'Permit Number',
                child: _InputField(controller: permitNumberCtrl)),
            const SizedBox(height: 14),
            _LabeledField(label: 'Registration Number',
                child: _InputField(controller: registrationCtrl)),
          ] else
            Row(children: [
              Expanded(child: _LabeledField(label: 'Permit Number',
                  child: _InputField(controller: permitNumberCtrl))),
              const SizedBox(width: 14),
              Expanded(child: _LabeledField(label: 'Registration Number',
                  child: _InputField(controller: registrationCtrl))),
            ]),
          const SizedBox(height: 22),

          if (!hasRecord)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No business record found. Please contact the admin.',
                style: TextStyle(color: Colors.amber.shade400, fontSize: 12.5),
              ),
            ),

          _ActionButton(
            icon: Icons.save_outlined,
            label: 'Save Business Info',
            isSaving: isSaving,
            onPressed: hasRecord ? onSave : () {},
          ),
        ],
      ),
    );
  }
}

// ─── Business Line Chips ──────────────────────────────────────────────────────

class _BusinessLineChips extends StatelessWidget {
  const _BusinessLineChips({
    required this.selected,
    required this.onChanged,
  });

  final List<BusinessLine> selected;
  final ValueChanged<List<BusinessLine>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BusinessLine.values.map((line) {
        final isOn = selected.contains(line);
        return GestureDetector(
          onTap: () {
            final next = List<BusinessLine>.from(selected);
            if (isOn) {
              if (next.length > 1) next.remove(line);
            } else {
              next.add(line);
            }
            onChanged(next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isOn
                  ? AppColors.primaryCyan.withOpacity(0.15)
                  : AppColors.inputBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOn ? AppColors.primaryCyan : AppColors.inputBorder,
                width: isOn ? 1.5 : 1,
              ),
            ),
            child: Text(
              line.label,
              style: TextStyle(
                color: isOn ? AppColors.primaryCyan : AppColors.textGray,
                fontSize: 12.5,
                fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Password Change Dialog ───────────────────────────────────────────────────

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog({required this.api});
  final BusinessProfileApi api;

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  int _step = 1;
  bool _loading  = false;
  String? _error;
  String? _verifiedOtp;

  final List<TextEditingController> _pinCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocus =
      List.generate(6, (_) => FocusNode());

  final _newPassCtrl  = TextEditingController();
  final _confPassCtrl = TextEditingController();
  bool _obscureNew  = true;
  bool _obscureConf = true;

  @override
  void dispose() {
    for (final c in _pinCtrl)  c.dispose();
    for (final f in _pinFocus) f.dispose();
    _newPassCtrl.dispose();
    _confPassCtrl.dispose();
    super.dispose();
  }

  void _clearPins() { for (final c in _pinCtrl) c.clear(); }

  Future<void> _sendOtp() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.sendPasswordChangeOtp();
      if (!mounted) return;
      setState(() { _loading = false; _step = 2; });
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _pinFocus[0].requestFocus());
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.verifyPasswordChangeOtp(otp: otp);
      if (!mounted) return;
      setState(() { 
        _loading = false; 
        _step = 3; 
        _verifiedOtp = otp;
      });
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      // Map ambiguous backend messages (e.g. "expired") to a clearer
      // user-facing message indicating the code is incorrect.
      final em = e.message.toLowerCase();
      final display = (em.contains('expired') || em.contains('expire'))
          ? 'Incorrect OTP. Please check and try again.'
          : e.message;
      setState(() { _loading = false; _error = display; });
    }
  }

  Future<void> _submitPassword() async {
    if (_verifiedOtp == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.updatePassword(
        otp:             _verifiedOtp,
        newPassword:     _newPassCtrl.text,
        confirmPassword: _confPassCtrl.text,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully.'),
            backgroundColor: Color(0xFF065F46),
          ),
        );
      }
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: 'Change Password',
      stepLabel: 'Step $_step of 3',
      onClose: () => Navigator.pop(context),
      child: switch (_step) {
        1 => _StepSendOtp(
          description:
              'We\'ll send a 6-digit verification code to your registered email address.',
          loading:  _loading,
          error:    _error,
          onSend:   _sendOtp,
          onCancel: () => Navigator.pop(context),
        ),
        2 => _StepVerifyOtp(
          pinCtrl:  _pinCtrl,
          pinFocus: _pinFocus,
          loading:  _loading,
          error:    _error,
          onVerify: _verifyOtp,
          onResend: () {
            _clearPins();
            setState(() { _step = 1; _error = null; });
          },
        ),
        _ => _StepNewPassword(
          newPassCtrl:  _newPassCtrl,
          confPassCtrl: _confPassCtrl,
          obscureNew:   _obscureNew,
          obscureConf:  _obscureConf,
          onToggleNew:  () => setState(() => _obscureNew  = !_obscureNew),
          onToggleConf: () => setState(() => _obscureConf = !_obscureConf),
          loading:  _loading,
          error:    _error,
          onSubmit: _submitPassword,
        ),
      },
    );
  }
}

// ─── Email Change Dialog ──────────────────────────────────────────────────────

class _EmailChangeDialog extends StatefulWidget {
  const _EmailChangeDialog({
    required this.api,
    required this.currentEmail,
    required this.onSuccess,
  });

  final BusinessProfileApi api;
  final String currentEmail;
  final ValueChanged<String> onSuccess;

  @override
  State<_EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends State<_EmailChangeDialog> {
  int _step = 1;
  bool _loading = false;
  String? _error;
  String? _verifiedOtp;

  final List<TextEditingController> _pinCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocus =
      List.generate(6, (_) => FocusNode());

  final _newEmailCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in _pinCtrl)  c.dispose();
    for (final f in _pinFocus) f.dispose();
    _newEmailCtrl.dispose();
    super.dispose();
  }

  void _clearPins() { for (final c in _pinCtrl) c.clear(); }

  Future<void> _sendOtp() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.sendEmailChangeOtp();
      if (!mounted) return;
      setState(() { _loading = false; _step = 2; });
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _pinFocus[0].requestFocus());
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.verifyEmailChangeOtp(otp: otp);
      if (!mounted) return;
      setState(() { 
        _loading = false; 
        _step = 3; 
        _verifiedOtp = otp;
      });
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      // Map ambiguous backend messages (e.g. "expired") to a clearer
      // user-facing message indicating the code is incorrect.
      final em = e.message.toLowerCase();
      final display = (em.contains('expired') || em.contains('expire'))
          ? 'Incorrect OTP. Please check and try again.'
          : e.message;
      setState(() { _loading = false; _error = display; });
    }
  }

  Future<void> _submitEmail() async {
    if (_verifiedOtp == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.updateEmail(
        newEmail: _newEmailCtrl.text,
        otp:      _verifiedOtp!,
      );
      final newEmail = _newEmailCtrl.text.trim().toLowerCase();
      widget.onSuccess(newEmail);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email updated successfully.'),
            backgroundColor: Color(0xFF065F46),
          ),
        );
      }
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: 'Change Email',
      stepLabel: 'Step $_step of 3',
      onClose: () => Navigator.pop(context),
      child: switch (_step) {
        1 => _StepSendOtp(
          description:
              'We\'ll send a 6-digit verification code to ${widget.currentEmail} to confirm your identity.',
          loading:  _loading,
          error:    _error,
          onSend:   _sendOtp,
          onCancel: () => Navigator.pop(context),
        ),
        2 => _StepVerifyOtp(
          pinCtrl:  _pinCtrl,
          pinFocus: _pinFocus,
          loading:  _loading,
          error:    _error,
          onVerify: _verifyOtp,
          onResend: () {
            _clearPins();
            setState(() { _step = 1; _error = null; });
          },
        ),
        _ => _StepNewEmail(
          ctrl:     _newEmailCtrl,
          loading:  _loading,
          error:    _error,
          onSubmit: _submitEmail,
        ),
      },
    );
  }
}

// ─── Dialog Shell ─────────────────────────────────────────────────────────────

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.title,
    required this.stepLabel,
    required this.onClose,
    required this.child,
  });

  final String title, stepLabel;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isNarrow = screenSize.width < 600;
    final horizontalInset = isNarrow ? 16.0 : 24.0;

    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: screenSize.height * 0.85,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.all(isNarrow ? 16 : 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: AppColors.textWhite,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(stepLabel,
                                style: const TextStyle(
                                    color: AppColors.textGray, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.textGray, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(height: 1, color: AppColors.cardBorder),
                  const SizedBox(height: 20),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Dialog Step Widgets ──────────────────────────────────────────────────────

class _StepSendOtp extends StatelessWidget {
  const _StepSendOtp({
    required this.description,
    required this.loading,
    this.error,
    required this.onSend,
    required this.onCancel,
  });

  final String description;
  final bool loading;
  final String? error;
  final VoidCallback onSend, onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.mail_outline_rounded,
                color: AppColors.primaryCyan, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(description,
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 13, height: 1.5)),
          ),
        ]),
        if (error != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(error!),
        ],
        const SizedBox(height: 22),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: loading ? null : onCancel,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.cardBorder),
                foregroundColor: AppColors.textGray,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _ActionButton(
            icon: Icons.send_outlined,
            label: 'Send Code',
            isSaving: loading,
            onPressed: onSend,
          )),
        ]),
      ],
    );
  }
}

class _StepVerifyOtp extends StatefulWidget {
  const _StepVerifyOtp({
    required this.pinCtrl,
    required this.pinFocus,
    required this.loading,
    this.error,
    required this.onVerify,
    required this.onResend,
  });

  final List<TextEditingController> pinCtrl;
  final List<FocusNode> pinFocus;
  final bool loading;
  final String? error;
  final ValueChanged<String> onVerify;
  final VoidCallback onResend;

  @override
  State<_StepVerifyOtp> createState() => _StepVerifyOtpState();
}

class _StepVerifyOtpState extends State<_StepVerifyOtp> {
  String get _otpValue => widget.pinCtrl.map((c) => c.text).join();

  void _onPinChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      widget.pinFocus[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      widget.pinFocus[index - 1].requestFocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        const SizedBox(height: 14),
        const Text(
          'Enter the 6-digit code sent to your email.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final boxWidth = ((constraints.maxWidth - 48) / 6)
                .clamp(36.0, 46.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) => Container(
                width: boxWidth,
                height: 54,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: widget.pinCtrl[i],
                  focusNode:  widget.pinFocus[i],
                  maxLength:  1,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.primaryCyan, width: 2),
                    ),
                  ),
                  onChanged: (v) => _onPinChanged(v, i),
                ),
              )),
            );
          },
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(widget.error!),
        ],
        const SizedBox(height: 22),
        _ActionButton(
          icon:     Icons.verified_outlined,
          label:    'Verify Code',
          isSaving: widget.loading,
          onPressed: _otpValue.length == 6 && !widget.loading
              ? () => widget.onVerify(_otpValue)
              : () {},
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: widget.loading ? null : widget.onResend,
              child: const Text(
                'Resend Code',
                style: TextStyle(color: AppColors.primaryCyan, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepNewPassword extends StatelessWidget {
  const _StepNewPassword({
    required this.newPassCtrl,
    required this.confPassCtrl,
    required this.obscureNew,
    required this.obscureConf,
    required this.onToggleNew,
    required this.onToggleConf,
    required this.loading,
    this.error,
    required this.onSubmit,
  });

  final TextEditingController newPassCtrl, confPassCtrl;
  final bool obscureNew, obscureConf, loading;
  final VoidCallback onToggleNew, onToggleConf, onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabeledField(
          label: 'New Password',
          child: _PasswordField(
              controller: newPassCtrl,
              obscure: obscureNew,
              onToggle: onToggleNew),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Confirm New Password',
          child: _PasswordField(
              controller: confPassCtrl,
              obscure: obscureConf,
              onToggle: onToggleConf),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(error!),
        ],
        const SizedBox(height: 22),
        _ActionButton(
          icon: Icons.lock_reset_outlined,
          label: 'Update Password',
          isSaving: loading,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _StepNewEmail extends StatelessWidget {
  const _StepNewEmail({
    required this.ctrl,
    required this.loading,
    this.error,
    required this.onSubmit,
  });

  final TextEditingController ctrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabeledField(
          label: 'New Email Address',
          icon: Icons.alternate_email,
          child: _InputField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(error!),
        ],
        const SizedBox(height: 22),
        _ActionButton(
          icon: Icons.check_circle_outline_rounded,
          label: 'Update Email',
          isSaving: loading,
          onPressed: onSubmit,
        ),
      ],
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

// ─── Section Title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryCyan, size: 18),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── Sub Label ────────────────────────────────────────────────────────────────

class _SubLabel extends StatelessWidget {
  const _SubLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryCyan,
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      ],
    );
  }
}

// ─── Labeled Field ────────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  const _LabeledField(
      {required this.label, required this.child, this.icon});

  final String label;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.textGray, size: 14),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500)),
        ]),
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
      decoration: _inputDeco(),
    );
  }
}

// ─── Readonly Field ───────────────────────────────────────────────────────────

class _ReadonlyField extends StatelessWidget {
  const _ReadonlyField({required this.controller, this.tooltip});
  final TextEditingController controller;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      style: const TextStyle(color: AppColors.textGray, fontSize: 13.5),
      decoration: _inputDeco().copyWith(
        suffixIcon: tooltip != null
            ? Tooltip(
                message: tooltip!,
                child: const Icon(Icons.info_outline_rounded,
                    color: AppColors.textGray, size: 16),
              )
            : null,
      ),
    );
  }
}

// ─── Password Field ───────────────────────────────────────────────────────────

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
      style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
      decoration: _inputDeco().copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textGray, size: 18),
          onPressed: onToggle,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

// ─── Enum Dropdown ────────────────────────────────────────────────────────────

class _EnumDropdown<T> extends StatelessWidget {
  const _EnumDropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      onChanged: onChanged,
      dropdownColor: AppColors.cardBackground,
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: AppColors.textGray, size: 20),
      style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
      decoration: _inputDeco(),
      items: items
          .map((t) => DropdownMenuItem(value: t, child: Text(labelOf(t))))
          .toList(),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isSaving,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd]),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 3)),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: isSaving ? null : onPressed,
          icon: isSaving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 16, color: Colors.white),
          label: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ),
    );
  }
}

// ─── Error Banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
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
            child: Text(message,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

// ─── Shared InputDecoration ───────────────────────────────────────────────────

InputDecoration _inputDeco() => InputDecoration(
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