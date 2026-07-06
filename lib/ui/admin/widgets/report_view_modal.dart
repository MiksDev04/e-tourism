import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../api/admin_report_api.dart';

// ─── Report Viewer Modal ──────────────────────────────────────────────────────

class ReportViewerModal extends StatefulWidget {
  const ReportViewerModal({
    super.key,
    required this.report,
    required this.onDownloadExcel,
  });

  final GeneratedReport report;
  final VoidCallback onDownloadExcel;

  @override
  State<ReportViewerModal> createState() => _ReportViewerModalState();
}

class _ReportViewerModalState extends State<ReportViewerModal> {
  bool _loading = true;
  String? _error;
  Uint8List? _pdfBytes;

  bool _exportingExcel = false;
  bool _exportingPdf = false;
  bool _printing = false;
  double _zoomScale = 1.0;

  final _reportService = ReportService();

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  void _setZoom(double scale) {
    setState(() {
      _zoomScale = scale.clamp(1.0, 2.0);
    });
  }

  void _handleZoom(bool increase) {
    if (increase) {
      _setZoom(_zoomScale + 0.1);
    } else {
      _setZoom(_zoomScale - 0.1);
    }
  }

  void _resetZoom() {
    setState(() => _zoomScale = 1.0);
  }

  Future<void> _loadPdf() async {
    try {
      final pdfUrl = widget.report.pdfUrl ??
          widget.report.fileUrl!.replaceAll('.xlsx', '.pdf');
      final bytes = await _reportService.downloadReportFile(pdfUrl);
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = isNetworkError(e)
            ? 'No internet connection. Please check your network and try again.'
            : 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exportingExcel = true);
    try {
      widget.onDownloadExcel();
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_pdfBytes == null) return;
    setState(() => _exportingPdf = true);
    try {
      final fileName =
          'Report_${widget.report.shortId}_'
          '${widget.report.periodLabel.replaceAll(' ', '_')}.pdf';

      if (kIsWeb) {
        await saveFileToDownloads(fileName, _pdfBytes!);
        _showModalSnack('PDF downloaded: $fileName');
      } else {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          _showModalSnack('Could not access Downloads folder.', isError: true);
          return;
        }
        final file = File('${downloadsDir.path}/$fileName');
        await file.writeAsBytes(_pdfBytes!);
        _showModalSnack('PDF saved: $fileName');

        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _showModalSnack('Error exporting PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _printPdf() async {
    if (_pdfBytes == null || _printing) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        // `format` is the page size/printable area of whatever printer and
        // paper the user picks in the OS print dialog. The report PDF is
        // pre-rendered at a fixed size (A4 from the backend), so instead of
        // returning it as-is (which prints cropped/offset on any printer
        // using a different paper size or driver margins), we rebuild it
        // scaled to fit that printable area — Windows' native print dialog
        // has no "Fit to page" option of its own, so this has to happen
        // here in the app.
        onLayout: (format) => _fitToPage(_pdfBytes!, format),
        name: 'Report_${widget.report.shortId}',
      );
    } catch (e) {
      _showModalSnack('Error printing PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Rasters each page of [source] and re-lays it out onto a fresh PDF whose
  /// pages match [format] (the printer/paper actually selected by the user),
  /// scaling each page's content to fit entirely within the printable area
  /// while preserving its aspect ratio — equivalent to "Fit to printable
  /// area" in browsers/Adobe Reader, which the raw Windows print dialog
  /// doesn't provide.
  Future<Uint8List> _fitToPage(Uint8List source, PdfPageFormat format) async {
    final fitted = pw.Document();

    // 200 dpi is a good balance between print sharpness (tables/small text
    // in DAE-1B/DAE-2 style reports stay legible) and raster/print time.
    // Bump this if a printer's output looks soft; drop it if printing feels
    // slow on large multi-page reports.
    const rasterDpi = 200.0;

    await for (final page in Printing.raster(source, dpi: rasterDpi)) {
      final png = await page.toPng();
      final image = pw.MemoryImage(png);

      fitted.addPage(
        pw.Page(
          pageFormat: format,
          // No explicit margin override: `format` already carries the
          // printer/driver's own margins, so the default page margin is the
          // true printable area. FittedBox then scales the rastered page to
          // sit fully inside it without clipping or distorting proportions.
          build: (context) => pw.Align(
            alignment: pw.Alignment.topCenter,
            child: pw.FittedBox(
              fit: pw.BoxFit.contain,
              alignment: pw.Alignment.topCenter,
              child: pw.SizedBox(
                width: page.width.toDouble(),
                height: page.height.toDouble(),
                child: pw.Image(image),
              ),
            ),
          ),
        ),
      );
    }

    return fitted.save();
  }

  void _showModalSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError
            ? const Color(0xFFFF4D6A)
            : const Color(0xFF00C48C),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final isMobile = size.width < 900;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile
          ? EdgeInsets.only(top: topPadding)
          : const EdgeInsets.all(20),
      child: Container(
        width: isMobile ? size.width : size.width * 0.95,
        height: isMobile ? size.height - topPadding : size.height * 0.92,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
          border: isMobile ? null : Border.all(color: AppColors.cardBorder),
          boxShadow: isMobile
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
        ),
        child: Column(
          children: [
            _ModalHeader(
              report: widget.report,
              onClose: () => Navigator.pop(context),
              onExportExcel: _exportingExcel ? null : _exportExcel,
              exportingExcel: _exportingExcel,
              onExportPdf: (_exportingPdf || _pdfBytes == null)
                  ? null
                  : _exportPdf,
              exportingPdf: _exportingPdf,
              onPrint: (_pdfBytes == null || _printing) ? null : _printPdf,
              printing: _printing,
              zoomScale: _zoomScale,
              onZoomIn: () => _handleZoom(true),
              onZoomOut: () => _handleZoom(false),
              onResetZoom: _resetZoom,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),
            Expanded(
              child: _loading
                  ? const _LoadingView()
                  : _error != null
                  ? _ErrorView(
                      error: _error!,
                      onRetry: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _loadPdf();
                      },
                    )
                  : _PdfView(
                      pdfBytes: _pdfBytes!,
                      zoomScale: _zoomScale,
                      onZoomChanged: _setZoom,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfView extends StatefulWidget {
  const _PdfView({
    super.key,
    required this.pdfBytes,
    required this.zoomScale,
    this.onZoomChanged,
  });

  final Uint8List pdfBytes;
  final double zoomScale;
  final void Function(double)? onZoomChanged;

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  final ScrollController _horizontalController = ScrollController();
  double? _initialZoomScale;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      final delta = event.scrollDelta.dy;
      if (delta < 0) {
        widget.onZoomChanged?.call(widget.zoomScale + 0.1);
      } else if (delta > 0) {
        widget.onZoomChanged?.call(widget.zoomScale - 0.1);
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _initialZoomScale = widget.zoomScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2 && _initialZoomScale != null) {
      final newScale = (_initialZoomScale! * details.scale).clamp(0.5, 2.0);
      widget.onZoomChanged?.call(newScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 900;

    // Estimate available width based on modal size and paddings
    final modalWidth = isMobile ? size.width : size.width * 0.95;
    final availableWidth = modalWidth - (isMobile ? 32 : 88);
    final targetWidth = availableWidth * widget.zoomScale;

    return Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)) {
              return AppColors.primaryCyan;
            }
            return AppColors.primaryCyan.withOpacity(0.5);
          }),
          trackColor: WidgetStateProperty.all(
            AppColors.primaryCyan.withOpacity(0.05),
          ),
          trackVisibility: WidgetStateProperty.all(true),
          thumbVisibility: WidgetStateProperty.all(true),
          thickness: WidgetStateProperty.all(10),
          radius: const Radius.circular(4),
          interactive: true,
        ),
      ),
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: Container(
          color: AppColors.backgroundDark,
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: Container(
                width: targetWidth + 48,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: PdfPreview(
                    build: (format) => widget.pdfBytes,
                    useActions: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    maxPageWidth: targetWidth,
                    loadingWidget: const _LoadingView(),
                    onError: (context, error) =>
                        const _ErrorView(error: 'Could not render PDF.'),
                    scrollViewDecoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    pdfPreviewPageDecoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.black.withOpacity(0.05),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    previewPageMargin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
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

// ── Modal Header ──────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({
    required this.report,
    required this.onClose,
    required this.onExportExcel,
    required this.exportingExcel,
    required this.onExportPdf,
    required this.exportingPdf,
    required this.onPrint,
    required this.printing,
    required this.zoomScale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
  });

  final GeneratedReport report;
  final VoidCallback onClose;
  final VoidCallback? onExportExcel;
  final bool exportingExcel;
  final VoidCallback? onExportPdf;
  final bool exportingPdf;
  final VoidCallback? onPrint;
  final bool printing;
  final double zoomScale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;

  Widget _buildIcon() => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppColors.primaryCyan.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(
      Icons.picture_as_pdf_rounded,
      color: AppColors.primaryCyan,
      size: 18,
    ),
  );

  Widget _buildInfo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            report.reportScope,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryCyan.withOpacity(0.10),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: AppColors.primaryCyan.withOpacity(0.25),
              ),
            ),
            child: Text(
              report.periodLabel,
              style: const TextStyle(
                color: AppColors.primaryCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        'Report ID: ${report.shortId}',
        style: const TextStyle(
          color: AppColors.textGray,
          fontSize: 11.5,
          fontFamily: 'monospace',
        ),
      ),
    ],
  );

  Widget _buildZoomControls() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.backgroundDark,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ZoomBtn(icon: Icons.remove_rounded, onTap: onZoomOut),
        GestureDetector(
          onTap: onResetZoom,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 48),
            child: Text(
              '${(zoomScale * 100).toInt()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        _ZoomBtn(icon: Icons.add_rounded, onTap: onZoomIn),
      ],
    ),
  );

  Widget _buildCloseBtn() => GestureDetector(
    onTap: onClose,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Icon(
        Icons.close_rounded,
        color: AppColors.textGray,
        size: 16,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _buildIcon(),
                const SizedBox(width: 10),
                Expanded(child: _buildInfo()),
                const SizedBox(width: 8),
                _buildCloseBtn(),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildZoomControls(),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ExportButton(
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'PDF',
                          color: const Color(0xFFD32F2F),
                          borderColor: const Color(0xFFD32F2F),
                          isLoading: exportingPdf,
                          onTap: onExportPdf,
                        ),
                        const SizedBox(width: 8),
                        _ExportButton(
                          icon: Icons.table_rows_rounded,
                          label: 'Excel',
                          color: const Color(0xFF1D6F42),
                          borderColor: const Color(0xFF1D6F42),
                          isLoading: exportingExcel,
                          onTap: onExportExcel,
                        ),
                        const SizedBox(width: 8),
                        _ExportButton(
                          icon: Icons.print_rounded,
                          label: 'Print',
                          color: AppColors.primaryCyan,
                          borderColor: AppColors.primaryCyan,
                          isLoading: printing,
                          onTap: onPrint,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          _buildIcon(),
          const SizedBox(width: 12),
          Expanded(child: _buildInfo()),
          const SizedBox(width: 12),
          // Group zoom and export buttons to handle tight spaces
          Flexible(
            flex: 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildZoomControls(),
                  const SizedBox(width: 12),
                  _ExportButton(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'PDF',
                    color: const Color(0xFFD32F2F),
                    borderColor: const Color(0xFFD32F2F),
                    isLoading: exportingPdf,
                    onTap: onExportPdf,
                  ),
                  const SizedBox(width: 8),
                  _ExportButton(
                    icon: Icons.table_rows_rounded,
                    label: 'Excel',
                    color: const Color(0xFF1D6F42),
                    borderColor: const Color(0xFF1D6F42),
                    isLoading: exportingExcel,
                    onTap: onExportExcel,
                  ),
                  const SizedBox(width: 8),
                  _ExportButton(
                    icon: Icons.print_rounded,
                    label: 'Print',
                    color: AppColors.primaryCyan,
                    borderColor: AppColors.primaryCyan,
                    isLoading: printing,
                    onTap: onPrint,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildCloseBtn(),
        ],
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(icon, color: AppColors.textWhite, size: 14),
      ),
    );
  }
}

// ── Export Button ─────────────────────────────────────────────────────────────

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onTap,
    this.isLoading = false,
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
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

// ── Loading & Error Views ─────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryCyan,
            strokeWidth: 2,
          ),
          SizedBox(height: 14),
          Text(
            'Loading report preview…',
            style: TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, this.onRetry});
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF4D6A),
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load the report preview.',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryCyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}