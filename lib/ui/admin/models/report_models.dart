// ─── Report Models ────────────────────────────────────────────────────────────
//
// ignore_for_file: constant_identifier_names

enum ReportStatus { submitted, approved, rejected, draft }

extension ReportStatusX on ReportStatus {
  String get label {
    switch (this) {
      case ReportStatus.submitted:
        return 'Submitted';
      case ReportStatus.approved:
        return 'Approved';
      case ReportStatus.rejected:
        return 'Rejected';
      case ReportStatus.draft:
        return 'Draft';
    }
  }

  static ReportStatus fromString(String? value) {
    switch (value) {
      case 'submitted':
        return ReportStatus.submitted;
      case 'approved':
        return ReportStatus.approved;
      case 'rejected':
        return ReportStatus.rejected;
      default:
        return ReportStatus.draft;
    }
  }
}

// ─── Report ───────────────────────────────────────────────────────────────────

class Report {
  final String id;
  final String businessId;
  final String business;

  /// Human-readable period e.g. "April 2024"
  final String period;
  final int periodMonth;
  final int periodYear;

  final int totalGuests;
  final int checkIns;

  /// ISO-8601 date string from generated_at e.g. "2024-05-02"
  final String? submitted;

  final ReportStatus status;
  final String? fileUrl;
  final String? remarks;
  final String reportScope;

  const Report({
    required this.id,
    required this.businessId,
    required this.business,
    required this.period,
    required this.periodMonth,
    required this.periodYear,
    required this.totalGuests,
    required this.checkIns,
    this.submitted,
    required this.status,
    this.fileUrl,
    this.remarks,
    this.reportScope = 'monthly',
  });

  // ── Deserialisation ──────────────────────────────────────────────────────

  factory Report.fromJson(Map<String, dynamic> json) {
    const monthNames = [
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

    final month = (json['period_month'] as num).toInt();
    final year = (json['period_year'] as num).toInt();

    final businessMap = json['businesses'] as Map<String, dynamic>?;

    return Report(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      business: businessMap?['business_name'] as String? ?? 'Unknown Business',
      period: '${monthNames[month - 1]} $year',
      periodMonth: month,
      periodYear: year,
      totalGuests: (json['total_guests'] as num?)?.toInt() ?? 0,
      checkIns: (json['check_ins'] as num?)?.toInt() ?? 0,
      submitted: json['generated_at'] != null
          ? (json['generated_at'] as String).substring(0, 10)
          : null,
      status: ReportStatusX.fromString(json['status'] as String?),
      fileUrl: json['file_url'] as String?,
      remarks: json['remarks'] as String?,
      reportScope: json['report_scope'] as String? ?? 'monthly',
    );
  }

  // ── Mutation helpers ─────────────────────────────────────────────────────

  Report copyWith({ReportStatus? status, String? fileUrl, String? remarks}) {
    return Report(
      id: id,
      businessId: businessId,
      business: business,
      period: period,
      periodMonth: periodMonth,
      periodYear: periodYear,
      totalGuests: totalGuests,
      checkIns: checkIns,
      submitted: submitted,
      status: status ?? this.status,
      fileUrl: fileUrl ?? this.fileUrl,
      remarks: remarks ?? this.remarks,
      reportScope: reportScope,
    );
  }

  @override
  String toString() =>
      'Report($reportScope · $business · $period · ${status.label})';
}

// ─── Business Option (for dropdowns) ─────────────────────────────────────────

class BusinessOption {
  final String id;
  final String name;

  const BusinessOption({required this.id, required this.name});

  factory BusinessOption.fromJson(Map<String, dynamic> json) {
    return BusinessOption(
      id: json['id'] as String,
      name: json['business_name'] as String,
    );
  }

  @override
  String toString() => name;
}

// ─── Review Report Data (passed to the review modal widget) ──────────────────
// NOTE: Update your review_report_modal.dart to accept the new fields
//       reportId, fileUrl, and remarks.

class ReviewReportData {
  final String reportId;
  final String business;
  final String period;
  final int totalGuests;
  final int checkIns;
  final String? submitted;
  final ReportStatus status;
  final String? fileUrl;
  final String? remarks;

  const ReviewReportData({
    required this.reportId,
    required this.business,
    required this.period,
    required this.totalGuests,
    required this.checkIns,
    this.submitted,
    required this.status,
    this.fileUrl,
    this.remarks,
  });

  factory ReviewReportData.fromReport(Report r) {
    return ReviewReportData(
      reportId: r.id,
      business: r.business,
      period: r.period,
      totalGuests: r.totalGuests,
      checkIns: r.checkIns,
      submitted: r.submitted,
      status: r.status,
      fileUrl: r.fileUrl,
      remarks: r.remarks,
    );
  }
}
