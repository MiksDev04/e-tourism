import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/document_service.dart';
import '../../../core/services/file_saver.dart';
import '../../../core/services/session_service.dart';

// ─── Document Preview Dialog ────────────────────────────────────────────────


Future<void> showDocumentPreviewModal(
  BuildContext context,
  String title,
  String url,
) {
  return showGeneralDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    barrierDismissible: true,
    barrierLabel: 'Close',
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (context, anim, secondaryAnim, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curve),
          child: DocumentPreviewModal(title: title, url: url),
        ),
      );
    },
  );
}

// ─── Document Preview Modal Widget ──────────────────────────────────────────

class DocumentPreviewModal extends StatefulWidget {
  const DocumentPreviewModal({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<DocumentPreviewModal> createState() => _DocumentPreviewModalState();
}

enum _DocType { pdf, png, jpeg, unknown }

_DocType _detectDocType(Uint8List bytes) {
  if (bytes.length >= 4) {
    if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return _DocType.pdf;
    }
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return _DocType.png;
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return _DocType.jpeg;
    }
  }
  return _DocType.unknown;
}

class _DocumentPreviewModalState extends State<DocumentPreviewModal> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;
  bool _saving = false;
  _DocType _docType = _DocType.unknown;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final bytes = await DocumentService.instance.fetchDocument(widget.url);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _docType = _detectDocType(bytes);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final code = await classifyError(e);
        setState(() {
          if (code == 503) {
            _error = 'No internet connection. Please check your network and try again.';
          } else if (code == 408) {
            _error = 'Request timed out. Please try again.';
          } else {
            _error = 'Something went wrong. Please try again.';
          }
          _loading = false;
        });
      }
    }
  }

  String get _fileExtension {
    switch (_docType) {
      case _DocType.pdf:
        return 'pdf';
      case _DocType.png:
        return 'png';
      case _DocType.jpeg:
        return 'jpg';
      case _DocType.unknown:
        final uri = Uri.parse(widget.url);
        final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        final ext = seg.split('.').last.toLowerCase();
        return (ext == 'pdf' || ext == 'png' || ext == 'jpg' || ext == 'jpeg') ? ext : 'png';
    }
  }

  String get _docTypeLabel {
    switch (_docType) {
      case _DocType.pdf:
        return 'PDF Document';
      case _DocType.png:
        return 'PNG Image';
      case _DocType.jpeg:
        return 'JPEG Image';
      case _DocType.unknown:
        return 'Document';
    }
  }

  Future<void> _download() async {
    if (_bytes == null || _saving) return;
    setState(() => _saving = true);
    try {
      final fileName = '${widget.title.replaceAll(' ', '_')}_'
          '${DateTime.now().millisecondsSinceEpoch}.$_fileExtension';

      await saveFileToDownloads(fileName, _bytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded successfully: $fileName'),
            backgroundColor: const Color(0xFF00C48C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download: $e'),
            backgroundColor: const Color(0xFFFF4D6A),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final isPdf = _docType == _DocType.pdf;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 900),
        width: isMobile ? size.width : size.width * 0.85,
        height: isMobile ? size.height * 0.85 : size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _docTypeLabel,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_loading && _error == null) ...[
                    // Download Button
                    GestureDetector(
                      onTap: _saving ? null : _download,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primaryCyan.withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_saving)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryCyan,
                                ),
                              )
                            else
                              const Icon(Icons.download_rounded, color: AppColors.primaryCyan, size: 14),
                            const SizedBox(width: 6),
                            const Text(
                              'Download',
                              style: TextStyle(
                                color: AppColors.primaryCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Close Button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
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
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.cardBorder, height: 1),

            // Content preview
            Expanded(
              child: Container(
                color: AppColors.backgroundDark,
                width: double.infinity,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryCyan,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFFF4D6A),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppColors.textGray,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _loading = true;
                                        _error = null;
                                      });
                                      _loadDocument();
                                    },
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
                              ),
                            ),
                          )
                        : _bytes == null
                            ? const Center(
                                child: Text(
                                  'No data available.',
                                  style: TextStyle(color: AppColors.textGray),
                                ),
                              )
                            : isPdf
                                ? ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                     child: PdfPreview(
                                       build: (format) => _bytes!,
                                       useActions: false,
                                    ),
                                  )
                                : _docType == _DocType.unknown
                                    ? const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.insert_drive_file_outlined,
                                              color: AppColors.textSubtle,
                                              size: 64,
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'Unable to preview this document format.',
                                              style: TextStyle(
                                                color: AppColors.textGray,
                                                fontSize: 14,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                        ),
                                        child: InteractiveViewer(
                                          maxScale: 4.0,
                                          minScale: 0.5,
                                          child: Center(
                                            child: Image.memory(
                                              _bytes!,
                                              width: 800,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
