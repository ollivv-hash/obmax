import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/obmax_colors.dart';

/// OB Max version of the player's loading overlay: the logo spinning on its
/// vertical axis like a coin, a soft gold glow, and the label in French in
/// the gold and cream of the logo.
class ObMaxLoadingOverlay extends StatefulWidget {
  const ObMaxLoadingOverlay({super.key, this.label, this.size = 96});

  /// Upstream passes English labels (hard-coded in the video player).
  final String? label;
  final double size;

  static const _french = {
    'loading stream...': 'Chargement…',
    'stopping previous playback...': 'Arrêt de la lecture précédente…',
    'restoring position...': 'Reprise de la lecture…',
  };

  /// [label] in French when OB Max knows it, as given otherwise.
  static String? translate(String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return _french[trimmed.toLowerCase()] ?? trimmed;
  }

  @override
  State<ObMaxLoadingOverlay> createState() => _ObMaxLoadingOverlayState();
}

class _ObMaxLoadingOverlayState extends State<ObMaxLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  static const _labelGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [ObMaxColors.primary, ObMaxColors.highlight, ObMaxColors.primary],
  );

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = ObMaxLoadingOverlay.translate(widget.label);
    final size = widget.size;
    final pulse = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Repaints every frame, so it gets a layer of its own.
        RepaintBoundary(
          child: SizedBox.square(
            dimension: size * 1.5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Gold glow breathing behind the logo.
                AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) => Container(
                    width: size * 1.5,
                    height: size * 1.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          ObMaxColors.primary.withValues(
                            alpha: 0.32 + 0.23 * pulse.value,
                          ),
                          ObMaxColors.tertiary.withValues(alpha: 0.10),
                          ObMaxColors.primary.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _spin,
                  builder: (context, child) {
                    // Eased per half turn, so the logo lingers face-on.
                    final t = _spin.value * 2;
                    final half = t.floor();
                    final eased = Curves.easeInOutCubic.transform(t - half);
                    final angle = (half + eased) * math.pi;
                    // The back of a coin would show the logo mirrored.
                    final facingAway = math.cos(angle) < 0;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(angle)
                        ..scaleByDouble(facingAway ? -1 : 1, 1, 1, 1),
                      child: child,
                    );
                  },
                  child: Image.asset(
                    'assets/obmax/logo.png',
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label != null) ...[
          SizedBox(height: size * 0.12),
          FadeTransition(
            opacity: Tween<double>(begin: 0.55, end: 1).animate(pulse),
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: _labelGradient.createShader,
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: math.max(14, size * 0.17),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  shadows: const [
                    Shadow(color: Color(0xAA080A23), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
