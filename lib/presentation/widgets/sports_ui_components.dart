import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';

/// Pulsująca animowana kropka na żywo (dla wskaźników LIVE, REC, SERWIS)
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool isPulsing;

  const PulseDot({
    super.key,
    this.color = AppTheme.redLive,
    this.size = 8.0,
    this.isPulsing = true,
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPulsing) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _animation.value * 0.8),
                blurRadius: widget.size * 1.2,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Nowoczesna pigułka statusu sportowego (np. LIVE, MASTER REC, PWA OFFLINE)
class SportBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool showPulse;
  final VoidCallback? onTap;

  const SportBadge({
    super.key,
    required this.label,
    this.color = AppTheme.cyanAccent,
    this.icon,
    this.showPulse = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPulse) ...[
            PulseDot(color: color, size: 7),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: badge,
      );
    }
    return badge;
  }
}

/// Wskaźnik jakości połączenia P2P (WebRTC / Wi-Fi) z paskami i opóźnieniem w ms
class NetworkSignalBadge extends StatelessWidget {
  final int latencyMs;
  final String label;

  const NetworkSignalBadge({
    super.key,
    required this.latencyMs,
    this.label = 'P2P LINK',
  });

  Color get _statusColor {
    if (latencyMs < 50) return AppTheme.greenLive;
    if (latencyMs < 150) return AppTheme.amberAccent;
    return AppTheme.redLive;
  }

  int get _signalBars {
    if (latencyMs < 40) return 4;
    if (latencyMs < 100) return 3;
    if (latencyMs < 200) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    final bars = _signalBars;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Paski sygnału
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (index) {
              final isFilled = index < bars;
              return Container(
                width: 2.5,
                height: 4.0 + (index * 2.5),
                margin: const EdgeInsets.symmetric(horizontal: 0.7),
                decoration: BoxDecoration(
                  color: isFilled ? color : Colors.white24,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ${latencyMs}ms',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Półprzezroczysty kafelek ze szklanym obramowaniem (Glassmorphism Card)
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16.0,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppTheme.glassCardGradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? const Color(0xFF222E42),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }
    return content;
  }
}
