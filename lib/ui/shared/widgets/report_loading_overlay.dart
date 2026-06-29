import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/connectivity_service.dart';

class ReportLoadingOverlay extends StatefulWidget {
  const ReportLoadingOverlay({
    super.key,
    this.title = 'Generating Report',
    this.message = 'Please wait while we process your request.',
    this.internetLostTitle = 'Connection Lost',
    this.internetLostMessage =
        'Report generation failed due to network issues.',
    this.onInternetLost,
    this.onDismiss,
    this.monitorConnectivity = true,
  });

  final String title;
  final String message;
  final String internetLostTitle;
  final String internetLostMessage;
  final VoidCallback? onInternetLost;
  final VoidCallback? onDismiss;
  final bool monitorConnectivity;

  @override
  State<ReportLoadingOverlay> createState() => _ReportLoadingOverlayState();
}

class _ReportLoadingOverlayState extends State<ReportLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _internetLost = false;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.monitorConnectivity) {
      _connectivitySub =
          ConnectivityService.instance.onlineStream.listen((online) {
        if (!online && !_internetLost && mounted) {
          setState(() => _internetLost = true);
          widget.onInternetLost?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pulseController.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _internetLost,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _internetLost
                ? _buildFailedContent()
                : _buildLoadingContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return Container(
      key: const ValueKey('loading'),
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 40,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) => Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    ),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: AppColors.primaryCyan,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.message,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, _) {
                return Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: const [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0x14FFFFFF),
                            Colors.transparent,
                            Colors.transparent,
                          ],
                          stops: [
                            0.0,
                            (_shimmerController.value - 0.15).clamp(0.0, 1.0),
                            _shimmerController.value.clamp(0.0, 1.0),
                            (_shimmerController.value + 0.15).clamp(0.0, 1.0),
                            1.0,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedContent() {
    return Container(
      key: const ValueKey('failed'),
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 40,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: AppColors.accentRed,
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.internetLostTitle,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.internetLostMessage,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => widget.onDismiss?.call(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.accentRed.withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        color: AppColors.accentRed,
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Dismiss',
                        style: TextStyle(
                          color: AppColors.accentRed,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
