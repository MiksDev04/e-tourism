import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app/api/register_api.dart';
import 'package:app/core/enums/business_enums.dart';
import 'package:app/router/app_routes.dart';
import 'package:app/core/constants/app_colors.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: RegisterScreen());
  }
}

// ─── Colors ───────────────────────────────────────────────────────────────────

class RegisterColors {
  RegisterColors._();
  static const textRed = Color(0xFFFF4D6A);
}

// ─── Validators ───────────────────────────────────────────────────────────────

class _V {
  _V._();

  static final _usernameRe = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
  static final _emailRe = RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
  static final _phoneRe = RegExp(r'^09\d{9}$');

  static String? fullName(String v) =>
      v.trim().isEmpty ? 'Full name is required' : null;

  static String? username(String v) {
    final value = v.trim();
    if (value.isEmpty) return 'Username is required';
    if (!_usernameRe.hasMatch(value)) {
      return 'Use 3-20 letters, numbers, or underscores';
    }
    return null;
  }

  static String? email(String v) {
    v = v.trim();
    if (v.isEmpty) return 'Email is required';
    if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String v) {
    final stripped = v.trim().replaceAll(RegExp(r'[-\s]'), '');
    if (stripped.isEmpty) return 'Phone number is required';
    if (!_phoneRe.hasMatch(stripped)) {
      return 'Use format 09XX-XXX-XXXX';
    }
    return null;
  }

  static String? password(String v) {
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters long';
    if (!RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(v)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r"[!@#$%^&*()\-_=+\[\]{};:',.<>?/\\|`~@]").hasMatch(v)) {
      return 'Password must contain at least one special character (e.g. @, #, !)';
    }
    return null;
  }

  static String? confirmPassword(String v, String password) {
    if (v.isEmpty) return 'Please confirm your password';
    if (v != password) return 'Passwords do not match';
    return null;
  }

  static String? businessName(String v) =>
      v.trim().isEmpty ? 'Business name is required' : null;

  static String? businessLine(List<String> values) {
    if (values.isEmpty) return 'Select at least one business line';
    final allowed = <String>{
      'hotel',
      'resort',
      'motel',
      'pension_inn',
      'youth_hostel',
      'apartment',
      'others',
    };
    if (values.any((value) => !allowed.contains(value))) {
      return 'Invalid business line selected';
    }
    return null;
  }

  static String? ownerFirstName(String v) =>
      v.trim().isEmpty ? 'First name is required' : null;

  static String? ownerLastName(String v) =>
      v.trim().isEmpty ? 'Last name is required' : null;

  static String? totalRooms(String v) {
    final n = int.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n <= 0) return 'Must be at least 1';
    return null;
  }

  static String? permitNumber(String v) =>
      v.trim().isEmpty ? 'Permit number is required' : null;

  static String? registrationNumber(String v) =>
      v.trim().isEmpty ? 'Registration number is required' : null;

  static String? street(String v) =>
      v.trim().isEmpty ? 'Street is required' : null;

  static String? barangay(String v) =>
      v.trim().isEmpty ? 'Barangay is required' : null;

  static String? cityMunicipality(String v) =>
      v.trim().isEmpty ? 'City / Municipality is required' : null;

  static String? province(String v) =>
      v.trim().isEmpty ? 'Province is required' : null;

  static String? region(String v) =>
      v.trim().isEmpty ? 'Region is required' : null;

  static String? file(PlatformFile? f) =>
      f == null ? 'Please upload the required file' : null;
}

// ─── Business Line display helpers ───────────────────────────────────────────

const _businessLineItems = [
  'hotel',
  'resort',
  'motel',
  'pension_inn',
  'youth_hostel',
  'apartment',
  'others',
];

const _businessLineLabels = {
  'hotel': 'Hotel',
  'resort': 'Resort',
  'motel': 'Motel',
  'pension_inn': 'Pension Inn',
  'youth_hostel': 'Youth Hostel',
  'apartment': 'Apartment',
  'others': 'Others',
};

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

// ─── Register Screen ──────────────────────────────────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ── Connectivity ───────────────────────────────────────────────────────────
  bool _isOnline = true;
  bool _checkingConnection = true;
  Timer? _connectivityTimer;

  // ── Form state ─────────────────────────────────────────────────────────────
  int _step = 1;
  bool _isLoading = false;
  String? _errorMessage;

  // Step 1
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // Step 2
  final _businessNameCtrl = TextEditingController();
  final _tradeNameCtrl = TextEditingController();
  final _ownerFirstNameCtrl = TextEditingController();
  final _ownerMiddleNameCtrl = TextEditingController();
  final _ownerLastNameCtrl = TextEditingController();
  final _totalRoomsCtrl = TextEditingController();
  final _permitNumberCtrl = TextEditingController();
  final _registrationCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: _fixedCityMunicipality);
  final _provinceCtrl = TextEditingController(text: _fixedProvince);
  final _regionCtrl = TextEditingController(text: _fixedRegion);

  // Business type: sole_proprietorship | corporation | partnership
  String _businessType = 'Sole Proprietorship';

  // Business line: DB stores as array, users can choose one or more
  List<String> _businessLine = ['hotel'];

  PlatformFile? _permitFile;
  PlatformFile? _validIdFile;
  bool _showErrors = false;

  final _api = RegisterApi();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkConnectivity(),
    );
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    for (final c in [
      _fullNameCtrl,
      _usernameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _passwordCtrl,
      _confirmPassCtrl,
      _businessNameCtrl,
      _tradeNameCtrl,
      _ownerFirstNameCtrl,
      _ownerMiddleNameCtrl,
      _ownerLastNameCtrl,
      _totalRoomsCtrl,
      _permitNumberCtrl,
      _registrationCtrl,
      _streetCtrl,
      _barangayCtrl,
      _cityCtrl,
      _provinceCtrl,
      _regionCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      if (kIsWeb) {
        if (mounted) {
          setState(() {
            _isOnline = true;
            _checkingConnection = false;
          });
        }
        return;
      }

      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      if (mounted) {
        setState(() {
          _isOnline = online;
          _checkingConnection = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isOnline = false;
          _checkingConnection = false;
        });
      }
    }
  }

  // ── Step 1 ─────────────────────────────────────────────────────────────────

  bool get _step1Valid =>
      _V.fullName(_fullNameCtrl.text) == null &&
      _V.username(_usernameCtrl.text) == null &&
      _V.email(_emailCtrl.text) == null &&
      _V.phone(_phoneCtrl.text) == null &&
      _V.password(_passwordCtrl.text) == null &&
      _V.confirmPassword(_confirmPassCtrl.text, _passwordCtrl.text) == null;

  void _goNext() {
    setState(() => _showErrors = true);
    if (!_step1Valid) return;
    setState(() {
      _step = 2;
      _showErrors = false;
      _errorMessage = null;
    });
  }

  void _goBack() => setState(() {
    _step = 1;
    _showErrors = false;
    _errorMessage = null;
  });

  // ── Step 2 ─────────────────────────────────────────────────────────────────

  bool get _step2Valid =>
      _V.businessName(_businessNameCtrl.text) == null &&
      _V.ownerFirstName(_ownerFirstNameCtrl.text) == null &&
      _V.ownerLastName(_ownerLastNameCtrl.text) == null &&
      _V.businessLine(_businessLine) == null &&
      _V.totalRooms(_totalRoomsCtrl.text) == null &&
      _V.permitNumber(_permitNumberCtrl.text) == null &&
      _V.registrationNumber(_registrationCtrl.text) == null &&
      _V.street(_streetCtrl.text) == null &&
      _V.barangay(_barangayCtrl.text) == null &&
      _V.cityMunicipality(_cityCtrl.text) == null &&
      _V.province(_provinceCtrl.text) == null &&
      _V.region(_regionCtrl.text) == null &&
      _V.file(_permitFile) == null &&
      _V.file(_validIdFile) == null;

  Future<void> _pickPermitFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
    );
    if (result != null) {
      setState(() => _permitFile = result.files.single);
    }
  }

  Future<void> _pickValidId() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
    );
    if (result != null) {
      setState(() => _validIdFile = result.files.single);
    }
  }

  void _applyFixedLocationValues() {
    _cityCtrl.text = _fixedCityMunicipality;
    _provinceCtrl.text = _fixedProvince;
    _regionCtrl.text = _fixedRegion;
  }

  Future<void> _submit() async {
    _applyFixedLocationValues();
    setState(() {
      _showErrors = true;
      _errorMessage = null;
    });
    if (!_step2Valid) return;

    setState(() => _isLoading = true);

    final result = await _api.register(
      fullName: _fullNameCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      phoneNumber: _phoneCtrl.text.trim(),
      businessName: _businessNameCtrl.text.trim(),
      tradeName: _tradeNameCtrl.text.trim(),
      businessType: _mapBusinessType(_businessType),
      businessLine: _businessLine,
      ownerFirstName: _ownerFirstNameCtrl.text.trim(),
      ownerMiddleName: _ownerMiddleNameCtrl.text.trim(),
      ownerLastName: _ownerLastNameCtrl.text.trim(),
      totalRooms: int.parse(_totalRoomsCtrl.text.trim()),
      permitNumber: _permitNumberCtrl.text.trim(),
      registrationNumber: _registrationCtrl.text.trim(),
      street: _streetCtrl.text.trim(),
      barangay: _barangayCtrl.text.trim(),
      cityMunicipality: _fixedCityMunicipality,
      province: _fixedProvince,
      region: _fixedRegion,
      permitFile: _permitFile!,
      validIdFile: _validIdFile!,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration submitted! Awaiting admin approval.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  BusinessType _mapBusinessType(String type) {
    switch (type) {
      case 'Corporation':
        return BusinessType.corporation;
      case 'Partnership':
        return BusinessType.partnership;
      case 'Sole Proprietorship':
      default:
        return BusinessType.soleProprietorship;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_checkingConnection) {
      return Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.3),
            radius: 1.2,
            colors: [AppColors.activeNavBg, AppColors.backgroundDark],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryCyan),
        ),
      );
    }

    return Stack(
      children: [_buildPage(), if (!_isOnline) _buildOfflineOverlay()],
    );
  }

  Widget _buildPage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.3),
          radius: 1.2,
          colors: [AppColors.activeNavBg, AppColors.backgroundDark],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      const _AppHeader(),
                      const SizedBox(height: 28),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: _FormCard(
                          step: _step,
                          showErrors: _showErrors,
                          isLoading: _isLoading,
                          errorMessage: _errorMessage,
                          // Step 1
                          fullNameCtrl: _fullNameCtrl,
                          usernameCtrl: _usernameCtrl,
                          emailCtrl: _emailCtrl,
                          phoneCtrl: _phoneCtrl,
                          passwordCtrl: _passwordCtrl,
                          confirmPassCtrl: _confirmPassCtrl,
                          onNext: _goNext,
                          // Step 2
                          businessNameCtrl: _businessNameCtrl,
                          tradeNameCtrl: _tradeNameCtrl,
                          businessType: _businessType,
                          onBusinessTypeChanged: (v) =>
                              setState(() => _businessType = v!),
                          businessLine: _businessLine,
                          onBusinessLineChanged: (v) =>
                              setState(() => _businessLine = v),
                          ownerFirstNameCtrl: _ownerFirstNameCtrl,
                          ownerMiddleNameCtrl: _ownerMiddleNameCtrl,
                          ownerLastNameCtrl: _ownerLastNameCtrl,
                          totalRoomsCtrl: _totalRoomsCtrl,
                          permitNumberCtrl: _permitNumberCtrl,
                          registrationCtrl: _registrationCtrl,
                          streetCtrl: _streetCtrl,
                          barangayCtrl: _barangayCtrl,
                          cityCtrl: _cityCtrl,
                          provinceCtrl: _provinceCtrl,
                          regionCtrl: _regionCtrl,
                          permitFile: _permitFile,
                          validIdFile: _validIdFile,
                          onPickPermitFile: _pickPermitFile,
                          onPickValidId: _pickValidId,
                          onBack: _goBack,
                          onSubmit: _submit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOfflineOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: RegisterColors.textRed.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 28,
                    color: RegisterColors.textRed,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Internet Connection',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'An internet connection is required to register your accommodation establishment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                _HoverButton(
                  label: 'Try Again',
                  icon: Icons.refresh_rounded,
                  onPressed: _checkConnectivity,
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.login),
                  child: const Text(
                    'Back to Sign In',
                    style: TextStyle(
                      color: AppColors.primaryCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── App Header ───────────────────────────────────────────────────────────────

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AppLogo(),
        const SizedBox(height: 14),
        const Text(
          'Register Accommodation',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tourism Record Management System',
          style: TextStyle(color: AppColors.primaryCyan, fontSize: 13.5),
        ),
      ],
    );
  }
}

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

// ─── Form Card ────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.step,
    required this.showErrors,
    required this.isLoading,
    this.errorMessage,
    // Step 1
    required this.fullNameCtrl,
    required this.usernameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.passwordCtrl,
    required this.confirmPassCtrl,
    required this.onNext,
    // Step 2
    required this.businessNameCtrl,
    required this.tradeNameCtrl,
    required this.businessType,
    required this.onBusinessTypeChanged,
    required this.businessLine,
    required this.onBusinessLineChanged,
    required this.ownerFirstNameCtrl,
    required this.ownerMiddleNameCtrl,
    required this.ownerLastNameCtrl,
    required this.totalRoomsCtrl,
    required this.permitNumberCtrl,
    required this.registrationCtrl,
    required this.streetCtrl,
    required this.barangayCtrl,
    required this.cityCtrl,
    required this.provinceCtrl,
    required this.regionCtrl,
    required this.permitFile,
    required this.validIdFile,
    required this.onPickPermitFile,
    required this.onPickValidId,
    required this.onBack,
    required this.onSubmit,
  });

  final int step;
  final bool showErrors;
  final bool isLoading;
  final String? errorMessage;

  // Step 1
  final TextEditingController fullNameCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmPassCtrl;
  final VoidCallback onNext;

  // Step 2
  final TextEditingController businessNameCtrl;
  final TextEditingController tradeNameCtrl;
  final String businessType;
  final ValueChanged<String?> onBusinessTypeChanged;
  final List<String> businessLine;
  final ValueChanged<List<String>> onBusinessLineChanged;
  final TextEditingController ownerFirstNameCtrl;
  final TextEditingController ownerMiddleNameCtrl;
  final TextEditingController ownerLastNameCtrl;
  final TextEditingController totalRoomsCtrl;
  final TextEditingController permitNumberCtrl;
  final TextEditingController registrationCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController barangayCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController provinceCtrl;
  final TextEditingController regionCtrl;
  final PlatformFile? permitFile;
  final PlatformFile? validIdFile;
  final VoidCallback onPickPermitFile;
  final VoidCallback onPickValidId;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
          _StepIndicator(currentStep: step),
          const SizedBox(height: 24),
          if (step == 1)
            _Step1Form(
              fullNameCtrl: fullNameCtrl,
              usernameCtrl: usernameCtrl,
              emailCtrl: emailCtrl,
              phoneCtrl: phoneCtrl,
              passwordCtrl: passwordCtrl,
              confirmPassCtrl: confirmPassCtrl,
              showErrors: showErrors,
              onNext: onNext,
            )
          else
            _Step2Form(
              showErrors: showErrors,
              isLoading: isLoading,
              errorMessage: errorMessage,
              businessNameCtrl: businessNameCtrl,
              tradeNameCtrl: tradeNameCtrl,
              businessType: businessType,
              onBusinessTypeChanged: onBusinessTypeChanged,
              businessLine: businessLine,
              onBusinessLineChanged: onBusinessLineChanged,
              ownerFirstNameCtrl: ownerFirstNameCtrl,
              ownerMiddleNameCtrl: ownerMiddleNameCtrl,
              ownerLastNameCtrl: ownerLastNameCtrl,
              totalRoomsCtrl: totalRoomsCtrl,
              permitNumberCtrl: permitNumberCtrl,
              registrationCtrl: registrationCtrl,
              streetCtrl: streetCtrl,
              barangayCtrl: barangayCtrl,
              cityCtrl: cityCtrl,
              provinceCtrl: provinceCtrl,
              regionCtrl: regionCtrl,
              permitFile: permitFile,
              validIdFile: validIdFile,
              onPickPermitFile: onPickPermitFile,
              onPickValidId: onPickValidId,
              onBack: onBack,
              onSubmit: onSubmit,
            ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () =>
                  Navigator.pushReplacementNamed(context, AppRoutes.login),
              child: RichText(
                text: const TextSpan(
                  text: 'Already registered? ',
                  style: TextStyle(color: AppColors.textSubtle, fontSize: 13),
                  children: [
                    TextSpan(
                      text: 'Sign in',
                      style: TextStyle(
                        color: AppColors.primaryCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepBadge(
          number: 1,
          label: 'Account Info',
          isActive: currentStep == 1,
          isComplete: currentStep > 1,
        ),
        Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: currentStep > 1
                ? AppColors.primaryCyan
                : AppColors.cardBorder,
          ),
        ),
        _StepBadge(
          number: 2,
          label: 'Business Details',
          isActive: currentStep == 2,
          isComplete: false,
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.number,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  final int number;
  final String label;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final borderColor = (isActive || isComplete)
        ? AppColors.primaryCyan
        : AppColors.cardBorder;
    final textColor = (isActive || isComplete)
        ? AppColors.textWhite
        : AppColors.textSubtle;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Center(
            child: isComplete
                ? const Icon(
                    Icons.check,
                    color: AppColors.primaryCyan,
                    size: 16,
                  )
                : Text(
                    '$number',
                    style: TextStyle(
                      color: borderColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─── Step 1 Form ──────────────────────────────────────────────────────────────

class _Step1Form extends StatefulWidget {
  const _Step1Form({
    required this.fullNameCtrl,
    required this.usernameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.passwordCtrl,
    required this.confirmPassCtrl,
    required this.showErrors,
    required this.onNext,
  });

  final TextEditingController fullNameCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmPassCtrl;
  final bool showErrors;
  final VoidCallback onNext;

  @override
  State<_Step1Form> createState() => _Step1FormState();
}

class _Step1FormState extends State<_Step1Form> {
  final _touched = <String>{};
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  void _touch(String field) => setState(() => _touched.add(field));
  bool _show(String f) => _touched.contains(f) || widget.showErrors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabeledField(
          label: 'Full Name',
          error: _show('fullName')
              ? _V.fullName(widget.fullNameCtrl.text)
              : null,
          child: _Input(
            controller: widget.fullNameCtrl,
            hint: 'Maria Santos',
            hasError:
                _show('fullName') &&
                _V.fullName(widget.fullNameCtrl.text) != null,
            onChanged: (_) => _touch('fullName'),
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Username',
          error: _show('username')
              ? _V.username(widget.usernameCtrl.text)
              : null,
          child: _Input(
            controller: widget.usernameCtrl,
            hint: 'yourname or your_name',
            hasError:
                _show('username') &&
                _V.username(widget.usernameCtrl.text) != null,
            onChanged: (_) => _touch('username'),
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Email Address',
          error: _show('email') ? _V.email(widget.emailCtrl.text) : null,
          child: _Input(
            controller: widget.emailCtrl,
            hint: 'email@example.com',
            keyboardType: TextInputType.emailAddress,
            hasError: _show('email') && _V.email(widget.emailCtrl.text) != null,
            onChanged: (_) => _touch('email'),
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Phone Number',
          error: _show('phone') ? _V.phone(widget.phoneCtrl.text) : null,
          child: _Input(
            controller: widget.phoneCtrl,
            hint: '09XX-XXX-XXXX',
            keyboardType: TextInputType.phone,
            hasError: _show('phone') && _V.phone(widget.phoneCtrl.text) != null,
            onChanged: (_) => _touch('phone'),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, _PhoneFormatter()],
          ),
        ),
        const SizedBox(height: 16),
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Password',
            error: _show('password')
                ? _V.password(widget.passwordCtrl.text)
                : null,
            child: _Input(
              controller: widget.passwordCtrl,
              hint: 'Min 8 characters',
              obscure: _hidePassword,
              hasError:
                  _show('password') &&
                  _V.password(widget.passwordCtrl.text) != null,
              onChanged: (_) => _touch('password'),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.textSubtle,
                  size: 18,
                ),
                tooltip: _hidePassword ? 'Show password' : 'Hide password',
              ),
            ),
          ),
          second: _LabeledField(
            label: 'Confirm Password',
            error: _show('confirmPass')
                ? _V.confirmPassword(
                    widget.confirmPassCtrl.text,
                    widget.passwordCtrl.text,
                  )
                : null,
            child: _Input(
              controller: widget.confirmPassCtrl,
              hint: 'Repeat password',
              obscure: _hideConfirmPassword,
              hasError:
                  _show('confirmPass') &&
                  _V.confirmPassword(
                        widget.confirmPassCtrl.text,
                        widget.passwordCtrl.text,
                      ) !=
                      null,
              onChanged: (_) => _touch('confirmPass'),
              suffixIcon: IconButton(
                onPressed: () => setState(
                  () => _hideConfirmPassword = !_hideConfirmPassword,
                ),
                icon: Icon(
                  _hideConfirmPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.textSubtle,
                  size: 18,
                ),
                tooltip: _hideConfirmPassword
                    ? 'Show password'
                    : 'Hide password',
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _GradientButton(
          label: 'Next: Business Details →',
          onPressed: widget.onNext,
        ),
      ],
    );
  }
}

// ─── Step 2 Form ──────────────────────────────────────────────────────────────

class _Step2Form extends StatefulWidget {
  const _Step2Form({
    required this.showErrors,
    required this.isLoading,
    this.errorMessage,
    required this.businessNameCtrl,
    required this.tradeNameCtrl,
    required this.businessType,
    required this.onBusinessTypeChanged,
    required this.businessLine,
    required this.onBusinessLineChanged,
    required this.ownerFirstNameCtrl,
    required this.ownerMiddleNameCtrl,
    required this.ownerLastNameCtrl,
    required this.totalRoomsCtrl,
    required this.permitNumberCtrl,
    required this.registrationCtrl,
    required this.streetCtrl,
    required this.barangayCtrl,
    required this.cityCtrl,
    required this.provinceCtrl,
    required this.regionCtrl,
    required this.permitFile,
    required this.validIdFile,
    required this.onPickPermitFile,
    required this.onPickValidId,
    required this.onBack,
    required this.onSubmit,
  });

  final bool showErrors;
  final bool isLoading;
  final String? errorMessage;
  final TextEditingController businessNameCtrl;
  final TextEditingController tradeNameCtrl;
  final String businessType;
  final ValueChanged<String?> onBusinessTypeChanged;
  final List<String> businessLine;
  final ValueChanged<List<String>> onBusinessLineChanged;
  final TextEditingController ownerFirstNameCtrl;
  final TextEditingController ownerMiddleNameCtrl;
  final TextEditingController ownerLastNameCtrl;
  final TextEditingController totalRoomsCtrl;
  final TextEditingController permitNumberCtrl;
  final TextEditingController registrationCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController barangayCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController provinceCtrl;
  final TextEditingController regionCtrl;
  final PlatformFile? permitFile;
  final PlatformFile? validIdFile;
  final VoidCallback onPickPermitFile;
  final VoidCallback onPickValidId;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  State<_Step2Form> createState() => _Step2FormState();
}

class _Step2FormState extends State<_Step2Form> {
  final _touched = <String>{};

  void _touch(String field) => setState(() => _touched.add(field));
  bool _show(String f) => _touched.contains(f) || widget.showErrors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Business Name + Business Type ─────────────────────────────────
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Business Name',
            error: _show('businessName')
                ? _V.businessName(widget.businessNameCtrl.text)
                : null,
            child: _Input(
              controller: widget.businessNameCtrl,
              hint: 'Hotel / Resort Name',
              hasError:
                  _show('businessName') &&
                  _V.businessName(widget.businessNameCtrl.text) != null,
              onChanged: (_) => _touch('businessName'),
            ),
          ),
          second: _LabeledField(
            label: 'Business Type',
            child: _DropdownField(
              value: widget.businessType,
              items: const [
                'Sole Proprietorship',
                'Corporation',
                'Partnership',
              ],
              onChanged: widget.onBusinessTypeChanged,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Business Line ─────────────────────────────────────────────────
        _LabeledField(
          label: 'Business Line',
          error: _show('businessLine')
              ? _V.businessLine(widget.businessLine)
              : null,
          child: _BusinessLineSelector(
            selected: widget.businessLine,
            items: _businessLineItems,
            displayLabels: _businessLineLabels,
            showError:
                _show('businessLine') &&
                _V.businessLine(widget.businessLine) != null,
            onChanged: (values) {
              widget.onBusinessLineChanged(values);
              _touch('businessLine');
            },
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Trade Name (Optional)',
          child: _Input(
            controller: widget.tradeNameCtrl,
            hint: 'e.g. The Grand Hotel',
            onChanged: (_) {},
          ),
        ),
        // ── Owner First Name + Last Name ───────────────────────────────────
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Owner First Name',
            error: _show('ownerFirstName')
                ? _V.ownerFirstName(widget.ownerFirstNameCtrl.text)
                : null,
            child: _Input(
              controller: widget.ownerFirstNameCtrl,
              hint: 'First name',
              hasError:
                  _show('ownerFirstName') &&
                  _V.ownerFirstName(widget.ownerFirstNameCtrl.text) != null,
              onChanged: (_) => _touch('ownerFirstName'),
            ),
          ),
          second: _LabeledField(
            label: 'Owner Last Name',
            error: _show('ownerLastName')
                ? _V.ownerLastName(widget.ownerLastNameCtrl.text)
                : null,
            child: _Input(
              controller: widget.ownerLastNameCtrl,
              hint: 'Last name',
              hasError:
                  _show('ownerLastName') &&
                  _V.ownerLastName(widget.ownerLastNameCtrl.text) != null,
              onChanged: (_) => _touch('ownerLastName'),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Owner Middle Name + Total Rooms ────────────────────────────────
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Middle Name (Optional)',
            child: _Input(
              controller: widget.ownerMiddleNameCtrl,
              hint: 'Middle name',
              onChanged: (_) {},
            ),
          ),
          second: _LabeledField(
            label: 'Total Rooms / Units',
            error: _show('totalRooms')
                ? _V.totalRooms(widget.totalRoomsCtrl.text)
                : null,
            child: _Input(
              controller: widget.totalRoomsCtrl,
              hint: 'e.g. 30',
              keyboardType: TextInputType.number,
              hasError:
                  _show('totalRooms') &&
                  _V.totalRooms(widget.totalRoomsCtrl.text) != null,
              onChanged: (_) => _touch('totalRooms'),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Permit Number + Registration Number ───────────────────────────
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Permit Number',
            error: _show('permitNumber')
                ? _V.permitNumber(widget.permitNumberCtrl.text)
                : null,
            child: _Input(
              controller: widget.permitNumberCtrl,
              hint: 'SP-HTL-2024-XXX',
              hasError:
                  _show('permitNumber') &&
                  _V.permitNumber(widget.permitNumberCtrl.text) != null,
              onChanged: (_) => _touch('permitNumber'),
            ),
          ),
          second: _LabeledField(
            label: 'Registration Number',
            error: _show('registration')
                ? _V.registrationNumber(widget.registrationCtrl.text)
                : null,
            child: _Input(
              controller: widget.registrationCtrl,
              hint: 'BIR-2024-XXXXX',
              hasError:
                  _show('registration') &&
                  _V.registrationNumber(widget.registrationCtrl.text) != null,
              onChanged: (_) => _touch('registration'),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Street ────────────────────────────────────────────────────────
        _LabeledField(
          label: 'Street',
          error: _show('street') ? _V.street(widget.streetCtrl.text) : null,
          child: _Input(
            controller: widget.streetCtrl,
            hint: 'House number, street',
            hasError:
                _show('street') && _V.street(widget.streetCtrl.text) != null,
            onChanged: (_) => _touch('street'),
          ),
        ),
        const SizedBox(height: 12),

        // ── Barangay + City ───────────────────────────────────────────────
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Barangay',
            error: _show('barangay')
                ? _V.barangay(widget.barangayCtrl.text)
                : null,
            child: _BarangayAutocomplete(
              controller: widget.barangayCtrl,
              hasError:
                  _show('barangay') &&
                  _V.barangay(widget.barangayCtrl.text) != null,
              onChanged: (_) => _touch('barangay'),
              onSelected: (_) => _touch('barangay'),
            ),
          ),
          second: _LabeledField(
            label: 'City / Municipality',
            error: _show('city')
                ? _V.cityMunicipality(widget.cityCtrl.text)
                : null,
            child: _Input(
              controller: widget.cityCtrl,
              hint: 'City / Municipality',
              enabled: false,
              hasError:
                  _show('city') &&
                  _V.cityMunicipality(widget.cityCtrl.text) != null,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Province + Region ─────────────────────────────────────────────
        _ResponsiveFieldPair(
          first: _LabeledField(
            label: 'Province',
            error: _show('province')
                ? _V.province(widget.provinceCtrl.text)
                : null,
            child: _Input(
              controller: widget.provinceCtrl,
              hint: 'Province',
              enabled: false,
              hasError:
                  _show('province') &&
                  _V.province(widget.provinceCtrl.text) != null,
            ),
          ),
          second: _LabeledField(
            label: 'Region',
            error: _show('region') ? _V.region(widget.regionCtrl.text) : null,
            child: _Input(
              controller: widget.regionCtrl,
              hint: 'Region',
              enabled: false,
              hasError:
                  _show('region') && _V.region(widget.regionCtrl.text) != null,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── File Uploads ──────────────────────────────────────────────────
        _LabeledField(
          label: 'Business Permit',
          error: widget.showErrors ? _V.file(widget.permitFile) : null,
          child: _FilePicker(
            label: 'Upload Permit (PDF / Image)',
            file: widget.permitFile,
            hasError: widget.showErrors && _V.file(widget.permitFile) != null,
            onPick: widget.onPickPermitFile,
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: "Owner's Valid ID",
          error: widget.showErrors ? _V.file(widget.validIdFile) : null,
          child: _FilePicker(
            label: "Upload Owner's Valid ID (PDF / Image)",
            file: widget.validIdFile,
            hasError: widget.showErrors && _V.file(widget.validIdFile) != null,
            onPick: widget.onPickValidId,
          ),
        ),
        const SizedBox(height: 16),

        // ── Error Banner ──────────────────────────────────────────────────
        if (widget.errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RegisterColors.textRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: RegisterColors.textRed.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: RegisterColors.textRed,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.errorMessage!,
                    style: const TextStyle(
                      color: RegisterColors.textRed,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Back + Submit ─────────────────────────────────────────────────
        Row(
          children: [
            _BackButton(onPressed: widget.isLoading ? () {} : widget.onBack),
            const SizedBox(width: 12),
            Expanded(
              child: widget.isLoading
                  ? const _LoadingButton()
                  : _GradientButton(
                      label: 'Submit Registration',
                      onPressed: widget.onSubmit,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _FilePicker extends StatelessWidget {
  const _FilePicker({
    required this.label,
    required this.file,
    required this.hasError,
    required this.onPick,
  });

  final String label;
  final PlatformFile? file;
  final bool hasError;
  final VoidCallback onPick;

  String get _fileName => file!.name;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? RegisterColors.textRed
        : AppColors.inputBorder;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(
              file != null ? Icons.check_circle : Icons.upload_file_rounded,
              color: file != null ? AppColors.primaryCyan : AppColors.textGray,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                file != null ? _fileName : label,
                style: TextStyle(
                  color: file != null
                      ? AppColors.textWhite
                      : AppColors.textSubtle,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              file != null ? 'Change' : 'Browse',
              style: const TextStyle(
                color: AppColors.primaryCyan,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
      height: 48,
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: const TextStyle(
              color: RegisterColors.textRed,
              fontSize: 11.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _BarangayAutocomplete extends StatefulWidget {
  const _BarangayAutocomplete({
    required this.controller,
    this.hasError = false,
    this.onChanged,
    this.onSelected,
  });

  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSelected;

  @override
  State<_BarangayAutocomplete> createState() => _BarangayAutocompleteState();
}

class _BarangayAutocompleteState extends State<_BarangayAutocomplete> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError
        ? RegisterColors.textRed
        : AppColors.inputBorder;

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return _sanPabloBarangays;
        return _sanPabloBarangays.where(
          (barangay) => barangay.toLowerCase().contains(query),
        );
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          onChanged: widget.onChanged,
          style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Select or enter barangay',
            hintStyle: const TextStyle(
              color: AppColors.textSubtle,
              fontSize: 13.5,
            ),
            filled: true,
            fillColor: AppColors.inputBackground,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primaryCyan,
                width: 1.5,
              ),
            ),
            suffixIcon: const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppColors.textGray,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            elevation: 8,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelectedOption(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Text(
                        option,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return oldValue;
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 4 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.hasError = false,
    this.enabled = true,
    this.onChanged,
    this.suffixIcon,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final bool obscure;
  final bool hasError;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? RegisterColors.textRed
        : AppColors.inputBorder;
    final textColor = enabled ? AppColors.textWhite : AppColors.textGray;
    final fillColor = enabled
        ? AppColors.inputBackground
        : AppColors.inputBackground.withOpacity(0.45);
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      enabled: enabled,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      style: TextStyle(color: textColor, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSubtle, fontSize: 13.5),
        filled: true,
        fillColor: fillColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.inputBorder.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.primaryCyan,
            width: 1.5,
          ),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.cardBackground,
          iconEnabledColor: AppColors.textGray,
          style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ResponsiveFieldPair extends StatelessWidget {
  const _ResponsiveFieldPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

class _BusinessLineSelector extends StatelessWidget {
  const _BusinessLineSelector({
    required this.selected,
    required this.items,
    required this.displayLabels,
    required this.onChanged,
    required this.showError,
  });

  final List<String> selected;
  final List<String> items;
  final Map<String, String> displayLabels;
  final ValueChanged<List<String>> onChanged;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final borderColor = showError
        ? RegisterColors.textRed
        : AppColors.inputBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          final isSelected = selected.contains(item);
          return FilterChip(
            selected: isSelected,
            onSelected: (_) {
              final next = List<String>.from(selected);
              if (isSelected) {
                next.remove(item);
              } else {
                next.add(item);
              }
              onChanged(next);
            },
            label: Text(displayLabels[item] ?? item),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.textWhite,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            selectedColor: AppColors.primaryBlue,
            checkmarkColor: Colors.white,
            backgroundColor: AppColors.cardBackground,
            side: BorderSide(
              color: isSelected ? AppColors.primaryBlue : AppColors.cardBorder,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  const _GradientButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedOpacity(
            opacity: _hovered && !_pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withOpacity(
                        _hovered ? 0.5 : 0.3,
                      ),
                      blurRadius: _hovered ? 20 : 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.cardBorder.withOpacity(0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered ? AppColors.textGray : AppColors.cardBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 16,
                  color: _hovered ? AppColors.textWhite : AppColors.textGray,
                ),
                const SizedBox(width: 8),
                Text(
                  'Back',
                  style: TextStyle(
                    color: _hovered ? AppColors.textWhite : AppColors.textGray,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverButton extends StatefulWidget {
  const _HoverButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedOpacity(
            opacity: _hovered && !_pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(
                      _hovered ? 0.55 : 0.3,
                    ),
                    blurRadius: _hovered ? 22 : 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
