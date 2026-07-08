import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';

class ActionIconButton extends StatefulWidget {
  const ActionIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.showBorder = false,
    this.label,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final bool showBorder;
  final String? label;

  @override
  State<ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<ActionIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.textGray;
    final hasLabel = widget.label != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.tooltip ?? '',
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: hasLabel ? 10 : 6,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: _hovered
                  ? color.withOpacity(0.12)
                  : widget.showBorder
                      ? color.withOpacity(0.04)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: widget.showBorder
                  ? Border.all(
                      color: _hovered
                          ? color.withOpacity(0.7)
                          : color.withOpacity(0.35),
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: _hovered ? color : color.withOpacity(0.7),
                  size: 18,
                ),
                if (hasLabel) ...[
                  const SizedBox(width: 4),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: _hovered ? color : color.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
