// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../business/widgets/business_document_preview_modal.dart';
import '../models/accommodation_models.dart';

// ─── Business Details Data Model ─────────────────────────────────────────────

class BusinessDetails {
  const BusinessDetails({
    required this.name,
    required this.tradeName,
    required this.type,
    required this.businessLine,
    required this.rooms,
    required this.status,
    required this.owner,
    required this.permitNumber,
    required this.registrationNumber,
    required this.registeredDate,
    required this.address,
    required this.street,
    required this.barangay,
    required this.cityMunicipality,
    required this.province,
    required this.region,
    required this.phone,
    required this.email,
    required this.permitFileUrl,
    required this.validIdUrl,
  });

  final String name;
  final String tradeName;
  final String type;
  final String businessLine;
  final int rooms;
  final AccommodationStatus status;
  final String owner;
  final String permitNumber;
  final String registrationNumber;
  final String registeredDate;
  final String address;
  final String street;
  final String barangay;
  final String cityMunicipality;
  final String province;
  final String region;
  final String phone;
  final String email;
  final String permitFileUrl;
  final String validIdUrl;
}

// ─── Show Helper ──────────────────────────────────────────────────────────────

Future<void> showBusinessDetailsModal(
  BuildContext context,
  BusinessDetails details,
) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    barrierDismissible: true,
    builder: (_) => BusinessDetailsModal(details: details),
  );
}

// ─── Modal Widget ─────────────────────────────────────────────────────────────

class BusinessDetailsModal extends StatefulWidget {
  const BusinessDetailsModal({super.key, required this.details});
  final BusinessDetails details;

  @override
  State<BusinessDetailsModal> createState() => _BusinessDetailsModalState();
}

class _BusinessDetailsModalState extends State<BusinessDetailsModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  static const _modalMaxWidth = 480.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: GestureDetector(
            onTap: () {},
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _modalMaxWidth),
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModalHeader(
                            onClose: () => Navigator.of(context).pop(),
                          ),
                          const Divider(color: AppColors.cardBorder, height: 1),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _BusinessIdentity(details: widget.details),
                                  const SizedBox(height: 20),
                                  const Divider(
                                    color: AppColors.cardBorder,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 20),
                                  _DetailsGrid(details: widget.details),
                                  const SizedBox(height: 20),
                                  const Divider(
                                    color: AppColors.cardBorder,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 20),
                                  _ContactInfo(details: widget.details),
                                  const SizedBox(height: 20),
                                  const Divider(
                                    color: AppColors.cardBorder,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 20),
                                  _DocumentsSection(
                                    permitFileUrl: widget.details.permitFileUrl,
                                    validIdUrl: widget.details.validIdUrl,
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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

// ─── Modal Header ─────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Text(
            'Business Details',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          _HoverIconButton(icon: Icons.close_rounded, onTap: onClose),
        ],
      ),
    );
  }
}

// ─── Business Identity ────────────────────────────────────────────────────────

class _BusinessIdentity extends StatelessWidget {
  const _BusinessIdentity({required this.details});
  final BusinessDetails details;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryCyan.withOpacity(0.25)),
          ),
          child: const Icon(
            Icons.apartment_rounded,
            color: AppColors.primaryCyan,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.name,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${details.type} • ${details.businessLine} • ${details.rooms} Rooms',
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              _StatusBadge(status: details.status),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Details Grid ─────────────────────────────────────────────────────────────

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.details});
  final BusinessDetails details;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          first: _DetailField(label: 'Trade Name', value: details.tradeName),
          second: _DetailField(label: 'Owner', value: details.owner),
        ),
        const SizedBox(height: 12),
        _DetailRow(
          first: _DetailField(label: 'Business Line', value: details.businessLine),
          second: _DetailField(
            label: 'Registered',
            value: _formatRegisteredDate(details.registeredDate),
          ),
        ),
        const SizedBox(height: 12),
        _DetailRow(
          first: _DetailField(label: 'Permit #', value: details.permitNumber),
          second: _DetailField(
            label: 'Registration #',
            value: details.registrationNumber,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 24),
        Expanded(child: second),
      ],
    );
  }
}

String _formatRegisteredDate(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty || value == '—') {
    return '—';
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  const monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final local = parsed.toLocal();
  return '${monthNames[local.month - 1]} ${local.day}, ${local.year}';
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSubtle,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Contact Info ─────────────────────────────────────────────────────────────

class _ContactInfo extends StatelessWidget {
  const _ContactInfo({required this.details});
  final BusinessDetails details;

  @override
  Widget build(BuildContext context) {
    // Compose structured address if available
    final parts = <String>[];
    if (details.street.isNotEmpty && details.street != '—') parts.add(details.street);
    if (details.barangay.isNotEmpty && details.barangay != '—') parts.add(details.barangay);
    if (details.cityMunicipality.isNotEmpty && details.cityMunicipality != '—') parts.add(details.cityMunicipality);
    if (details.province.isNotEmpty && details.province != '—') parts.add(details.province);
    if (details.region.isNotEmpty && details.region != '—') parts.add(details.region);
    final addressText = parts.isNotEmpty ? parts.join(', ') : details.address;

    return Column(
      children: [
        _ContactRow(icon: Icons.location_on_outlined, text: addressText),
        const SizedBox(height: 10),
        _ContactRow(icon: Icons.phone_outlined, text: details.phone),
        const SizedBox(height: 10),
        _ContactRow(icon: Icons.email_outlined, text: details.email),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textSubtle, size: 15),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ─── Documents Section ────────────────────────────────────────────────────────

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({
    required this.permitFileUrl,
    required this.validIdUrl,
  });

  final String permitFileUrl;
  final String validIdUrl;

  void _previewDocument(BuildContext context, String title, String url) {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document URL not available.')),
      );
      return;
    }
    showDocumentPreviewModal(context, title, url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Documents',
          style: TextStyle(
            color: AppColors.textSubtle,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _DocumentChip(
              label: 'Business Permit',
              onTap: () => _previewDocument(context, 'Business Permit', permitFileUrl),
            ),
            const SizedBox(width: 8),
            _DocumentChip(
              label: 'Valid ID',
              onTap: () => _previewDocument(context, 'Valid ID', validIdUrl),
            ),
          ],
        ),
      ],
    );
  }
}

class _DocumentChip extends StatefulWidget {
  const _DocumentChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_DocumentChip> createState() => _DocumentChipState();
}

class _DocumentChipState extends State<_DocumentChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primaryCyan.withOpacity(0.1)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? AppColors.primaryCyan.withOpacity(0.5)
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                color: _hovered ? AppColors.primaryCyan : AppColors.textGray,
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: _hovered ? AppColors.primaryCyan : AppColors.textGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.visibility_outlined,
                color: _hovered ? AppColors.primaryCyan : AppColors.textSubtle,
                size: 11,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hover Icon Button ────────────────────────────────────────────────────────

class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.cardBorder.withOpacity(0.8)
                : AppColors.cardBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            color: _hovered ? AppColors.textWhite : AppColors.textGray,
            size: 16,
          ),
        ),
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AccommodationStatus status;

  static ({String label, Color color}) _styleFor(AccommodationStatus s) {
    switch (s) {
      case AccommodationStatus.approved:
        return (label: 'Approved', color: const Color(0xFF00C48C));
      case AccommodationStatus.pending:
        return (label: 'Pending', color: const Color(0xFFFFB020));
      case AccommodationStatus.rejected:
        return (label: 'Rejected', color: const Color(0xFFFF4D6A));
      case AccommodationStatus.warning:
        return (label: 'Warning', color: const Color(0xFFFFB020));
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: style.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}