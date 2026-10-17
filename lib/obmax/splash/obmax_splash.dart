import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/obmax_colors.dart';

/// The animated OB Max splash, drawn from five aligned 1024 px layers.
///
/// It plays once (2600 ms), then holds the last frame with the gold halo
/// pulsing until [ready] is true. [onFinished] fires once, when the animation
/// is over (or skipped by a key or a tap) and [ready] is true.
///
/// With [holdFinalFrame] it starts on the last frame: used by screens that
/// keep the splash on screen while the session restores.
class ObMaxSplash extends StatefulWidget {
  const ObMaxSplash({
    super.key,
    this.ready = false,
    this.onFinished,
    this.holdFinalFrame = false,
  });

  final bool ready;
  final VoidCallback? onFinished;
  final bool holdFinalFrame;

  static const duration = Duration(milliseconds: 2600);

  static const layerAssets = [
    'assets/obmax/splash/bg.png',
    'assets/obmax/splash/star_off.png',
    'assets/obmax/splash/star_on.png',
    'assets/obmax/splash/ob.png',
    'assets/obmax/splash/max.png',
  ];

  @override
  State<ObMaxSplash> createState() => _ObMaxSplashState();
}

class _ObMaxSplashState extends State<ObMaxSplash>
    with TickerProviderStateMixin {
  late final AnimationController _timeline = AnimationController(
    vsync: this,
    duration: ObMaxSplash.duration,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  final _streams = <ImageStream>[];
  final _listeners = <ImageStreamListener>[];
  List<ui.Image?> _images = List.filled(5, null);
  bool _loadStarted = false;
  bool _skipped = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _timeline.addListener(_onTick);
    _timeline.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeFinish();
    });
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    unawaited(_load());
  }

  /// Precaches the five layers and keeps their decoded images for the
  /// painter, then starts the timeline. Nothing animates half-loaded.
  Future<void> _load() async {
    final config = createLocalImageConfiguration(context);
    final completers = <Completer<void>>[];
    for (var i = 0; i < ObMaxSplash.layerAssets.length; i++) {
      final completer = Completer<void>();
      completers.add(completer);
      final stream = AssetImage(ObMaxSplash.layerAssets[i]).resolve(config);
      final listener = ImageStreamListener(
        (info, _) {
          _images[i] = info.image;
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_, _) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      stream.addListener(listener);
      _streams.add(stream);
      _listeners.add(listener);
    }
    await Future.wait(completers.map((c) => c.future));
    if (!mounted) return;
    setState(() => _images = List.of(_images));
    if (widget.holdFinalFrame) {
      _timeline.value = 1;
    } else {
      unawaited(_timeline.forward());
    }
  }

  void _onTick() {
    // The halo starts pulsing once the star is fully lit.
    if (_timeline.value * ObMaxSplash.duration.inMilliseconds >= 1300 &&
        !_pulse.isAnimating) {
      unawaited(_pulse.repeat());
    }
  }

  @override
  void didUpdateWidget(ObMaxSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _maybeFinish();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _finished) return false;
    _skip();
    return widget.ready;
  }

  void _skip() {
    _skipped = true;
    if (widget.ready && _timeline.value > 0) {
      _timeline.value = 1;
      _maybeFinish();
    }
  }

  void _maybeFinish() {
    if (_finished || !widget.ready) return;
    final done = _timeline.isCompleted || _skipped && _timeline.value > 0;
    if (!done) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    for (var i = 0; i < _streams.length; i++) {
      _streams[i].removeListener(_listeners[i]);
    }
    _timeline.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent _) => _skip(),
      child: ColoredBox(
        color: ObMaxColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // About 45 % of the height on a TV, 60 % of the width on a phone.
            final side = math.min(
              constraints.maxHeight * 0.45,
              constraints.maxWidth * 0.60,
            );
            return Center(
              child: SizedBox.square(
                dimension: side,
                child: CustomPaint(
                  painter: _ObMaxSplashPainter(
                    images: _images,
                    timeline: _timeline,
                    pulse: _pulse,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// All layers in one painter: the additive halo and the shine clipped to the
/// letters need to blend with what is already drawn, which separate widgets
/// (each with its own compositing layer) cannot guarantee.
class _ObMaxSplashPainter extends CustomPainter {
  _ObMaxSplashPainter({
    required this.images,
    required this.timeline,
    required this.pulse,
  }) : super(repaint: Listenable.merge([timeline, pulse]));

  final List<ui.Image?> images;
  final Animation<double> timeline;
  final Animation<double> pulse;

  static const _totalMs = 2600.0;

  // Layer content centres in the 1024 px source frame, for scaling in place.
  static const _starCenter = Offset(512, 505);
  static const _obCenter = Offset(509.5, 441);
  static const _maxCenter = Offset(515, 646.5);

  /// Progress of [t] (ms) through [start, end], clamped to 0..1.
  static double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  static double _lerp(double a, double b, double v) => a + (b - a) * v;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = images[0], starOff = images[1], starOn = images[2];
    final ob = images[3], max = images[4];
    if (bg == null) return;

    final t = timeline.value * _totalMs;
    final k = size.width / 1024; // source px -> canvas px
    final full = Offset.zero & size;

    // bg: 0-400 ms, fade in, 1.08 -> 1 (easeOutCubic).
    final bgP = Curves.easeOutCubic.transform(_phase(t, 0, 400));
    _drawLayer(
      canvas,
      bg,
      full,
      scale: _lerp(1.08, 1, bgP),
      center: size.center(Offset.zero),
      opacity: bgP,
    );

    // Halo: from 700 ms, blurred star_on added on top of the background.
    // 0 -> 0.7 while the star lights up, then 0.55 +/- 0.15.
    if (starOn != null && t >= 700) {
      final double intensity = t < 1300
          ? 0.7 * _phase(t, 700, 1300)
          : 0.55 + 0.15 * math.cos(2 * math.pi * pulse.value);
      final sigma = 18 * size.width / 720;
      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
        ..color = Color.fromRGBO(255, 255, 255, intensity)
        ..filterQuality = FilterQuality.medium;
      canvas.drawImageRect(starOn, _src(starOn), full, paint);
    }

    // star_off: 150-700 ms, 0.55 -> 1 with overshoot, fading in.
    if (starOff != null && t >= 150) {
      final p = _phase(t, 150, 700);
      _drawLayer(
        canvas,
        starOff,
        full,
        scale: _lerp(0.55, 1, Curves.easeOutBack.transform(p)),
        center: _starCenter * k,
        opacity: Curves.easeOut.transform(_phase(t, 150, 450)),
      );
    }

    // star_on: 700-1300 ms, clockwise sweep from the top point.
    if (starOn != null && t >= 700) {
      final p = _phase(t, 700, 1300);
      if (p >= 1) {
        canvas.drawImageRect(starOn, _src(starOn), full, _imagePaint());
      } else if (p > 0) {
        canvas.saveLayer(full, Paint());
        canvas.drawImageRect(starOn, _src(starOn), full, _imagePaint());
        final edge = math.min(p + 0.015, 1.0);
        final mask = SweepGradient(
          center: Alignment(
            _starCenter.dx / 512 - 1,
            _starCenter.dy / 512 - 1,
          ),
          // A negative startAngle leaves the 12-to-3 o'clock quarter outside
          // the gradient, so the sweep starts at 3 o'clock and is turned back
          // a quarter to begin at the top point.
          transform: const GradientRotation(-math.pi / 2),
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, p, edge, 1],
        ).createShader(full);
        canvas.drawRect(
          full,
          Paint()
            ..shader = mask
            ..blendMode = BlendMode.dstIn,
        );
        canvas.restore();
      }
    }

    // Letters, in their own layer so the shine only touches them.
    final showOb = ob != null && t >= 1000;
    final showMax = max != null && t >= 1150;
    if (!showOb && !showMax) return;
    canvas.saveLayer(full, Paint());
    // ob: 1000-1350 ms, drops from -40 px, 1.25 -> 1, overshoot.
    if (showOb) {
      _drawWord(canvas, ob, full, k, t, start: 1000, end: 1350, fromDy: -40,
          center: _obCenter * k, size: size);
    }
    // max: 1150-1500 ms, rises from +40 px, same effect.
    if (showMax) {
      _drawWord(canvas, max, full, k, t, start: 1150, end: 1500, fromDy: 40,
          center: _maxCenter * k, size: size);
    }
    // Shine: 1650-2150 ms, a diagonal white band across the letters only.
    if (t > 1650 && t < 2150) {
      final p = Curves.easeInOut.transform(_phase(t, 1650, 2150));
      final x = _lerp(-0.6, 1.6, p);
      final shine = LinearGradient(
        begin: Alignment(-1 + 2 * (x - 0.25), -1),
        end: Alignment(-1 + 2 * (x + 0.25), 1),
        colors: const [
          Color(0x00FFFFFF),
          Color(0xB3FFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: const [0.3, 0.5, 0.7],
      ).createShader(full);
      canvas.drawRect(
        full,
        Paint()
          ..shader = shine
          ..blendMode = BlendMode.srcATop,
      );
    }
    canvas.restore();
  }

  void _drawWord(
    Canvas canvas,
    ui.Image image,
    Rect full,
    double k,
    double t, {
    required double start,
    required double end,
    required double fromDy,
    required Offset center,
    required Size size,
  }) {
    final p = _phase(t, start, end);
    final bounce = Curves.easeOutBack.transform(p);
    // The 40 px offsets are in the 720 px reference frame of the preview.
    final dy = fromDy * size.width / 720 * (1 - bounce);
    _drawLayer(
      canvas,
      image,
      full.shift(Offset(0, dy)),
      scale: _lerp(1.25, 1, bounce),
      center: center + Offset(0, dy),
      opacity: Curves.easeOut.transform(_phase(t, start, start + 140)),
    );
  }

  static Rect _src(ui.Image image) =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  static Paint _imagePaint([double opacity = 1]) => Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromRGBO(255, 255, 255, opacity);

  void _drawLayer(
    Canvas canvas,
    ui.Image image,
    Rect dst, {
    required double scale,
    required Offset center,
    required double opacity,
  }) {
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawImageRect(image, _src(image), dst, _imagePaint(opacity));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ObMaxSplashPainter old) => old.images != images;
}
