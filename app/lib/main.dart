import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  runApp(const DynamicIslandDripApp());
}

class DynamicIslandDripApp extends StatelessWidget {
  const DynamicIslandDripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DynamicIslandDripPage(),
    );
  }
}

class DynamicIslandDripPage extends StatefulWidget {
  const DynamicIslandDripPage({super.key});

  @override
  State<DynamicIslandDripPage> createState() => _DynamicIslandDripPageState();
}

class _DynamicIslandDripPageState extends State<DynamicIslandDripPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<double> _lastPhases;
  int _cycleIndex = 0;
  double _lastValue = 0;
  double _orbFill = 0.24;

  @override
  void initState() {
    super.initState();
    _lastPhases = List<double>.filled(DynamicIslandDripPainter._drips.length, 0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4480),
    )
      ..addListener(() {
        final value = _controller.value;
        var nextCycleIndex = _cycleIndex;
        var nextOrbFill = _orbFill;
        var needsUpdate = false;

        if (value < _lastValue) {
          nextCycleIndex++;
          needsUpdate = true;
        }

        final activeStretchIndex =
            ((3 * nextCycleIndex) + 2) % DynamicIslandDripPainter._drips.length;

        for (var i = 0; i < DynamicIslandDripPainter._drips.length; i++) {
          final spec = DynamicIslandDripPainter._drips[i];
          final phase = DynamicIslandDripPainter._phaseFor(value, spec);
          final threshold = i == activeStretchIndex ? 0.95 : 0.84;
          if (_crossedThreshold(_lastPhases[i], phase, threshold)) {
            nextOrbFill = math.min(
              0.78,
              nextOrbFill + (i == activeStretchIndex ? 0.05 : 0.026),
            );
            needsUpdate = true;
          }
          _lastPhases[i] = phase;
        }

        if (needsUpdate) {
          setState(() {
            _cycleIndex = nextCycleIndex;
            _orbFill = nextOrbFill;
          });
        }
        _lastValue = value;
      })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFF5C52D);
    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: bgColor,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: DynamicIslandDripPainter(
              t: _controller.value,
              safeTop: safeTop,
              activeStretchIndex: ((3 * _cycleIndex) + 2) % 5,
              orbFill: _orbFill,
              color: Colors.black,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }

  bool _crossedThreshold(double previous, double current, double threshold) {
    if (current >= previous) {
      return previous < threshold && current >= threshold;
    }
    return previous < threshold || current >= threshold;
  }
}

class DynamicIslandDripPainter extends CustomPainter {
  DynamicIslandDripPainter({
    required this.t,
    required this.safeTop,
    required this.activeStretchIndex,
    required this.orbFill,
    required this.color,
  });

  final double t;
  final double safeTop;
  final int activeStretchIndex;
  final double orbFill;
  final Color color;

  static const Color _orbBlueTop = Color(0xFF74A7FF);
  static const Color _orbBlueBottom = Color(0xFF2F63F2);

  static const List<_DripSpec> _drips = <_DripSpec>[
    _DripSpec(
      anchorFactor: -0.315,
      phaseOffset: 0.06,
      speed: 0.94,
      shoulder: 6.4,
      neck: 2.3,
      tipRadius: 4.4,
      travel: 82,
      anchorLift: -4.2,
    ),
    _DripSpec(
      anchorFactor: -0.158,
      phaseOffset: 0.34,
      speed: 1.07,
      shoulder: 7.0,
      neck: 2.6,
      tipRadius: 4.9,
      travel: 94,
      anchorLift: -2.0,
    ),
    _DripSpec(
      anchorFactor: 0.00,
      phaseOffset: 0.18,
      speed: 0.88,
      shoulder: 8.0,
      neck: 3.0,
      tipRadius: 5.9,
      travel: 146,
      anchorLift: 0.0,
    ),
    _DripSpec(
      anchorFactor: 0.158,
      phaseOffset: 0.57,
      speed: 1.13,
      shoulder: 7.0,
      neck: 2.6,
      tipRadius: 4.9,
      travel: 92,
      anchorLift: -2.0,
    ),
    _DripSpec(
      anchorFactor: 0.315,
      phaseOffset: 0.79,
      speed: 0.95,
      shoulder: 6.4,
      neck: 2.3,
      tipRadius: 4.4,
      travel: 80,
      anchorLift: -4.2,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final shadowPaint = Paint()
      ..color = const Color(0x24000000)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..isAntiAlias = true;

    final centerX = size.width / 2;
    final hasDynamicIslandInset = safeTop >= 44;
    final sourceWidth = hasDynamicIslandInset
        ? math.min(118.0, size.width * 0.32)
        : math.min(126.0, size.width * 0.34);
    final orbCenter = Offset(centerX, size.height * 0.60);
    final orbRadius = math.min(size.width * 0.235, 94.0);

    final islandTop = hasDynamicIslandInset
        ? math.max(2.0, safeTop - 47.0)
        : math.max(10.0, safeTop + 6.0);
    const islandHeight = 36.0;
    final sourceBottom = hasDynamicIslandInset
        ? math.max(24.0, safeTop - 8.0)
        : islandTop + islandHeight;

    if (hasDynamicIslandInset) {
      _drawSourceLip(
        canvas,
        centerX: centerX,
        width: sourceWidth,
        top: islandTop,
        bottom: sourceBottom,
        fillPaint: fillPaint,
      );
    } else {
      _drawFallbackIsland(
        canvas,
        centerX: centerX,
        width: sourceWidth,
        top: islandTop,
        height: islandHeight,
        fillPaint: fillPaint,
        shadowPaint: shadowPaint,
      );
    }

    _drawOrbBack(
      canvas,
      center: orbCenter,
      radius: orbRadius,
      fillPaint: fillPaint,
      shadowPaint: shadowPaint,
    );

    _drawAttachmentFilm(
      canvas,
      centerX: centerX,
      sourceWidth: sourceWidth,
      baseY: sourceBottom + 1.0,
      fillPaint: fillPaint,
    );

    for (var i = 0; i < _drips.length; i++) {
      _drawDrip(
        canvas,
        index: i,
        centerX: centerX,
        sourceWidth: sourceWidth,
        baseY: sourceBottom + 0.8,
        orbCenter: orbCenter,
        orbRadius: orbRadius,
        spec: _drips[i],
        fillPaint: fillPaint,
        shadowPaint: shadowPaint,
      );
    }

    _drawOrbFront(
      canvas,
      center: orbCenter,
      radius: orbRadius,
    );
  }

  void _drawFallbackIsland(
    Canvas canvas, {
    required double centerX,
    required double width,
    required double top,
    required double height,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final rect = Rect.fromCenter(
      center: Offset(centerX, top + height / 2),
      width: width,
      height: height,
    );
    final pill = RRect.fromRectAndRadius(
      rect,
      Radius.circular(height / 2),
    );

    canvas.drawRRect(pill.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawRRect(pill, fillPaint);
  }

  void _drawSourceLip(
    Canvas canvas, {
    required double centerX,
    required double width,
    required double top,
    required double bottom,
    required Paint fillPaint,
  }) {
    final left = centerX - width / 2;
    final right = centerX + width / 2;
    final topY = math.max(0.0, top + 17).toDouble();
    const inset = 14.0;
    final path = Path()
      ..moveTo(left + inset, topY)
      ..lineTo(right - inset, topY)
      ..quadraticBezierTo(right - 1, topY, right - 1, topY + 7)
      ..cubicTo(
        right - width * 0.10,
        bottom - 0.8,
        centerX + width * 0.24,
        bottom + 0.7,
        centerX,
        bottom + 1.8,
      )
      ..cubicTo(
        centerX - width * 0.24,
        bottom + 0.7,
        left + width * 0.10,
        bottom - 0.8,
        left + 1,
        topY + 7,
      )
      ..quadraticBezierTo(left + 1, topY, left + inset, topY)
      ..close();

    canvas.drawPath(path, fillPaint);
  }

  void _drawAttachmentFilm(
    Canvas canvas, {
    required double centerX,
    required double sourceWidth,
    required double baseY,
    required Paint fillPaint,
  }) {
    for (final drip in _drips) {
      final anchorX = centerX + sourceWidth * drip.anchorFactor;
      final shoulder = drip.shoulder * 0.88;
      final anchorY = baseY + drip.anchorLift;
      final capPath = Path()
        ..moveTo(anchorX - shoulder, baseY - 0.8)
        ..cubicTo(
          anchorX - shoulder * 0.58,
          baseY - 0.8,
          anchorX - drip.neck,
          anchorY + 0.9,
          anchorX,
          anchorY + 1.2,
        )
        ..cubicTo(
          anchorX + drip.neck,
          anchorY + 0.9,
          anchorX + shoulder * 0.58,
          baseY - 0.8,
          anchorX + shoulder,
          baseY - 0.8,
        )
        ..lineTo(anchorX + shoulder * 0.88, baseY + 0.35)
        ..cubicTo(
          anchorX + drip.neck * 0.7,
          anchorY + 1.6,
          anchorX + drip.neck * 0.36,
          anchorY + 1.8,
          anchorX,
          anchorY + 1.95,
        )
        ..cubicTo(
          anchorX - drip.neck * 0.36,
          anchorY + 1.8,
          anchorX - drip.neck * 0.7,
          anchorY + 1.6,
          anchorX - shoulder * 0.88,
          baseY + 0.35,
        )
        ..close();

      canvas.drawPath(capPath, fillPaint);
    }
  }

  void _drawDrip(
    Canvas canvas, {
    required int index,
    required double centerX,
    required double sourceWidth,
    required double baseY,
    required Offset orbCenter,
    required double orbRadius,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final phase = (t * spec.speed + spec.phaseOffset) % 1.0;
    final anchorX = centerX + sourceWidth * spec.anchorFactor;
    final anchorY = baseY + spec.anchorLift;

    if (index == activeStretchIndex) {
      _drawStretchDrip(
        canvas,
        phase: phase,
        anchorX: anchorX,
        anchorY: anchorY,
        orbCenter: orbCenter,
        orbRadius: orbRadius,
        spec: spec,
        fillPaint: fillPaint,
        shadowPaint: shadowPaint,
      );
      return;
    }

    _drawDirectDrop(
      canvas,
      phase: phase,
      anchorX: anchorX,
      anchorY: anchorY,
      orbCenter: orbCenter,
      orbRadius: orbRadius,
      spec: spec,
      fillPaint: fillPaint,
      shadowPaint: shadowPaint,
    );
  }

  void _drawStretchDrip(
    Canvas canvas, {
    required double phase,
    required double anchorX,
    required double anchorY,
    required Offset orbCenter,
    required double orbRadius,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final gather = _normalize(phase, 0.00, 0.16);
    final stretch = _normalize(phase, 0.16, 0.68);
    final rebound = _normalize(phase, 0.68, 0.80);
    final bulb = _normalize(phase, 0.80, 0.90);
    final release = _normalize(phase, 0.90, 1.0);
    final impactY =
        (_orbTopAtX(orbCenter, orbRadius, anchorX) ?? (orbCenter.dy - orbRadius)) +
            spec.tipRadius * 0.16;

    final shoulder = _lerp(
      spec.shoulder * 0.82,
      spec.shoulder,
      _easeOutCubic(gather),
    );
    final neck = _lerp(
      spec.shoulder * 0.50,
      spec.neck,
      _easeInOutCubic(stretch),
    );

    final stretchedLength =
        8 + _easeInOutCubic(stretch) * (spec.travel * 0.64);
    final reboundedLength =
        stretchedLength - _easeInOutCubic(rebound) * (spec.travel * 0.08);
    final attachedLength =
        reboundedLength + _easeOutCubic(bulb) * (spec.travel * 0.10);
    final attachedTipRadius = _lerp(
      spec.tipRadius * 0.72,
      spec.tipRadius * 1.16,
      _easeOutCubic(_normalize(phase, 0.22, 0.90)),
    );

    if (phase < 0.90) {
      final length = phase < 0.16
          ? 1.4 + _easeOutCubic(gather) * 7.0
          : phase < 0.68
              ? stretchedLength
              : phase < 0.80
                  ? reboundedLength
                  : attachedLength;

      final path = length < 8
          ? _buildBulgePath(
              anchorX: anchorX,
              baseY: anchorY,
              shoulder: shoulder,
              neck: neck,
              bulge: length,
            )
          : _buildDripPath(
              anchorX: anchorX,
              baseY: anchorY,
              shoulder: shoulder,
              neck: neck,
              length: length,
              tipRadius: attachedTipRadius,
            );

      canvas.drawPath(path.shift(const Offset(0, 1.3)), shadowPaint);
      canvas.drawPath(
        path,
        _gradientLiquidPaint(
          path.getBounds(),
          bottomY: anchorY + length + attachedTipRadius,
          orbCenter: orbCenter,
          orbRadius: orbRadius,
        ),
      );
      return;
    }

    final residualPath = _buildBulgePath(
      anchorX: anchorX,
      baseY: anchorY,
      shoulder: spec.shoulder * 0.72,
      neck: spec.neck * 0.76,
      bulge: _lerp(5.2, 1.6, _easeInOutCubic(release)),
    );
    canvas.drawPath(residualPath.shift(const Offset(0, 1.1)), shadowPaint);
    canvas.drawPath(residualPath, fillPaint);

    final dropRadius = _lerp(
      spec.tipRadius * 1.12,
      spec.tipRadius * 1.28,
      _easeOutCubic(release),
    );
    final dropY = _lerp(
      anchorY + attachedLength + 8,
      impactY,
      _easeInCubic(release),
    );
    _drawOrbAwareDrop(
      canvas,
      x: anchorX,
      y: dropY,
      radius: dropRadius,
      orbCenter: orbCenter,
      orbRadius: orbRadius,
      shadowPaint: shadowPaint,
    );
  }

  void _drawDirectDrop(
    Canvas canvas, {
    required double phase,
    required double anchorX,
    required double anchorY,
    required Offset orbCenter,
    required double orbRadius,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final gather = _normalize(phase, 0.00, 0.10);
    final tether = _normalize(phase, 0.10, 0.18);
    final fall = _normalize(phase, 0.18, 0.84);
    final fade = _normalize(phase, 0.88, 1.0);
    final recover = _normalize(phase, 0.48, 1.0);
    final impactY =
        (_orbTopAtX(orbCenter, orbRadius, anchorX) ?? (orbCenter.dy - orbRadius)) +
            spec.tipRadius * 0.12;

    if (phase < 0.10) {
      final beadPath = _buildBulgePath(
        anchorX: anchorX,
        baseY: anchorY,
        shoulder: _lerp(spec.shoulder * 0.56, spec.shoulder * 0.78, gather),
        neck: _lerp(spec.neck * 0.72, spec.neck * 0.98, gather),
        bulge: 1.3 + _easeOutCubic(gather) * 6.3,
      );
      canvas.drawPath(beadPath.shift(const Offset(0, 1.0)), shadowPaint);
      canvas.drawPath(beadPath, fillPaint);
      return;
    }

    if (phase < 0.18) {
      final path = _buildDripPath(
        anchorX: anchorX,
        baseY: anchorY,
        shoulder: _lerp(spec.shoulder * 0.70, spec.shoulder * 0.82, tether),
        neck: _lerp(spec.neck * 0.98, spec.neck * 0.78, tether),
        length: 6 + _easeOutCubic(tether) * 10,
        tipRadius: _lerp(spec.tipRadius * 0.74, spec.tipRadius * 0.98, tether),
      );
      canvas.drawPath(path.shift(const Offset(0, 1.1)), shadowPaint);
      canvas.drawPath(
        path,
        _gradientLiquidPaint(
          path.getBounds(),
          bottomY: anchorY + 16,
          orbCenter: orbCenter,
          orbRadius: orbRadius,
        ),
      );
      return;
    }

    final beadPath = _buildBulgePath(
      anchorX: anchorX,
      baseY: anchorY,
      shoulder: _lerp(spec.shoulder * 0.56, spec.shoulder * 0.42, recover),
      neck: _lerp(spec.neck * 0.82, spec.neck * 0.62, recover),
      bulge: _lerp(3.4, 1.3, _easeInOutCubic(recover)),
    );
    canvas.drawPath(beadPath.shift(const Offset(0, 0.9)), shadowPaint);
    canvas.drawPath(beadPath, fillPaint);

    final dropRadius =
        spec.tipRadius * 1.16 * _clamp01(1 - _easeInCubic(fade));
    if (dropRadius <= 0.08) {
      return;
    }

    final dropY = _lerp(
      anchorY + 12,
      impactY,
      _easeInCubic(fall),
    );
    _drawOrbAwareDrop(
      canvas,
      x: anchorX,
      y: dropY,
      radius: dropRadius,
      orbCenter: orbCenter,
      orbRadius: orbRadius,
      shadowPaint: shadowPaint,
    );
  }

  void _drawOrbBack(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius + 12),
        width: radius * 1.5,
        height: radius * 0.34,
      ),
      Paint()
        ..color = const Color(0x20000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final orbRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[
            Color(0x33FFFFFF),
            Color(0x14FFFFFF),
            Color(0x08FFFFFF),
          ],
          stops: <double>[0.0, 0.62, 1.0],
        ).createShader(orbRect)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    _drawOrbLiquid(
      canvas,
      center: center,
      radius: radius,
      fillPaint: fillPaint,
    );
  }

  void _drawOrbLiquid(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Paint fillPaint,
  }) {
    final orbRect = Rect.fromCircle(center: center, radius: radius);
    final liquidTop = center.dy + radius * (1 - 2 * orbFill);
    final left = center.dx - radius;
    final right = center.dx + radius;
    final waveA = 4.5 + math.sin(t * math.pi * 2).abs() * 2.6;
    final waveB = 1.8 + math.cos(t * math.pi * 2.6).abs() * 1.4;

    final liquidPath = Path()
      ..moveTo(left, center.dy + radius)
      ..lineTo(left, liquidTop);

    for (var x = left; x <= right; x += 4) {
      final progress = (x - left) / (right - left);
      final edgeFalloff = math.sin(progress * math.pi);
      final wave =
          math.sin((progress * 2.3 + t * 1.2) * math.pi * 2) * waveA * edgeFalloff +
              math.sin((progress * 4.8 - t * 1.8) * math.pi * 2) *
                  waveB *
                  edgeFalloff;
      liquidPath.lineTo(x, liquidTop + wave);
    }

    liquidPath
      ..lineTo(right, center.dy + radius)
      ..close();

    canvas.save();
    canvas.clipPath(Path()..addOval(orbRect));
    canvas.drawPath(
      liquidPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _orbBlueTop.withAlpha(224),
            _orbBlueBottom.withAlpha(236),
            _orbBlueBottom,
          ],
        ).createShader(orbRect)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      liquidPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0x55FFFFFF),
    );
    canvas.restore();
  }

  void _drawOrbFront(
    Canvas canvas, {
    required Offset center,
    required double radius,
  }) {
    final orbRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0x7AFFFFFF),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - radius * 0.26, center.dy - radius * 0.34),
        width: radius * 0.44,
        height: radius * 0.78,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0x7FFFFFFF),
            const Color(0x18FFFFFF),
          ],
        ).createShader(orbRect)
        ..style = PaintingStyle.fill,
    );

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx + radius * 0.04, center.dy + radius * 0.04),
        width: radius * 1.58,
        height: radius * 1.62,
      ),
      math.pi * 0.15,
      math.pi * 0.46,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x3FFFFFFF),
    );
  }

  void _drawOrbAwareDrop(
    Canvas canvas, {
    required double x,
    required double y,
    required double radius,
    required Offset orbCenter,
    required double orbRadius,
    required Paint shadowPaint,
  }) {
    final mergeTop = _orbTopAtX(orbCenter, orbRadius, x);
    if (mergeTop == null || y < mergeTop - radius * 1.02) {
      _drawDropCircle(
        canvas,
        x: x,
        y: y,
        radius: radius,
        orbCenter: orbCenter,
        orbRadius: orbRadius,
        shadowPaint: shadowPaint,
      );
      return;
    }

    if (y < mergeTop + radius * 0.38) {
      final blend = _normalize(y, mergeTop - radius * 1.02, mergeTop + radius * 0.38);
      final contactY = _lerp(mergeTop - radius * 0.04, mergeTop + radius * 0.04, blend);
      final shoulder = _lerp(radius * 0.82, radius * 0.42, blend);
      final mergePath = Path()
        ..moveTo(x - shoulder, y - radius * 0.08)
        ..cubicTo(
          x - radius * 0.98,
          y + radius * 0.62,
          x - radius * 0.72,
          contactY + radius * 0.22,
          x,
          contactY,
        )
        ..cubicTo(
          x + radius * 0.72,
          contactY + radius * 0.22,
          x + radius * 0.98,
          y + radius * 0.62,
          x + shoulder,
          y - radius * 0.08,
        )
        ..arcToPoint(
          Offset(x - shoulder, y - radius * 0.08),
          radius: Radius.circular(radius),
          clockwise: false,
        )
        ..close();

      canvas.drawPath(mergePath.shift(const Offset(0, 1)), shadowPaint);
      canvas.drawPath(
        mergePath,
        _gradientLiquidPaint(
          mergePath.getBounds(),
          bottomY: mergeTop + radius,
          orbCenter: orbCenter,
          orbRadius: orbRadius,
        ),
      );

      final seamPath = Path()
        ..moveTo(x - radius * 0.56, mergeTop + radius * 0.02)
        ..quadraticBezierTo(
          x,
          mergeTop - radius * 0.16 * (1 - blend),
          x + radius * 0.56,
          mergeTop + radius * 0.02,
        )
        ..lineTo(x + radius * 0.40, mergeTop + radius * 0.20)
        ..quadraticBezierTo(
          x,
          mergeTop + radius * 0.06,
          x - radius * 0.40,
          mergeTop + radius * 0.20,
        )
        ..close();
      canvas.drawPath(
        seamPath,
        Paint()..color = _orbBlueTop.withAlpha(220),
      );
      return;
    }
  }

  void _drawDropCircle(
    Canvas canvas, {
    required double x,
    required double y,
    required double radius,
    required Offset orbCenter,
    required double orbRadius,
    required Paint shadowPaint,
  }) {
    canvas.drawCircle(Offset(x, y + 1), radius, shadowPaint);
    final rect = Rect.fromCircle(center: Offset(x, y), radius: radius);
    canvas.drawCircle(
      Offset(x, y),
      radius,
      _gradientLiquidPaint(
        rect,
        bottomY: y + radius,
        orbCenter: orbCenter,
        orbRadius: orbRadius,
      ),
    );
  }

  double? _orbTopAtX(Offset center, double radius, double x) {
    final dx = x - center.dx;
    if (dx.abs() > radius) {
      return null;
    }
    return center.dy - math.sqrt(radius * radius - dx * dx);
  }

  Path _buildBulgePath({
    required double anchorX,
    required double baseY,
    required double shoulder,
    required double neck,
    required double bulge,
  }) {
    return Path()
      ..moveTo(anchorX - shoulder, baseY)
      ..cubicTo(
        anchorX - shoulder * 0.7,
        baseY,
        anchorX - neck,
        baseY + bulge,
        anchorX,
        baseY + bulge,
      )
      ..cubicTo(
        anchorX + neck,
        baseY + bulge,
        anchorX + shoulder * 0.7,
        baseY,
        anchorX + shoulder,
        baseY,
      )
      ..close();
  }

  Path _buildDripPath({
    required double anchorX,
    required double baseY,
    required double shoulder,
    required double neck,
    required double length,
    required double tipRadius,
  }) {
    final tipCenterX = anchorX;
    final tipCenterY = baseY + length;
    final tipRadiusY = tipRadius * 1.22;

    return Path()
      ..moveTo(anchorX - shoulder, baseY)
      ..cubicTo(
        anchorX - shoulder * 0.66,
        baseY + length * 0.03,
        anchorX - neck * 1.2,
        baseY + length * 0.28,
        anchorX - neck,
        baseY + length * 0.48,
      )
      ..cubicTo(
        anchorX - neck * 0.7,
        baseY + length * 0.78,
        tipCenterX - tipRadius,
        tipCenterY - tipRadiusY * 0.8,
        tipCenterX - tipRadius,
        tipCenterY,
      )
      ..arcToPoint(
        Offset(tipCenterX + tipRadius, tipCenterY),
        radius: Radius.elliptical(tipRadius, tipRadiusY),
        clockwise: false,
      )
      ..cubicTo(
        tipCenterX + tipRadius,
        tipCenterY - tipRadiusY * 0.8,
        anchorX + neck * 0.7,
        baseY + length * 0.78,
        anchorX + neck,
        baseY + length * 0.48,
      )
      ..cubicTo(
        anchorX + neck * 1.2,
        baseY + length * 0.28,
        anchorX + shoulder * 0.66,
        baseY + length * 0.03,
        anchorX + shoulder,
        baseY,
      )
      ..close();
  }

  static double _normalize(double value, double start, double end) {
    if (value <= start) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return (value - start) / (end - start);
  }

  static double _clamp01(double value) {
    return math.max(0.0, math.min(1.0, value)).toDouble();
  }

  Paint _gradientLiquidPaint(
    Rect bounds, {
    required double bottomY,
    required Offset orbCenter,
    required double orbRadius,
  }) {
    final blend = _easeOutCubic(
      _clamp01((bottomY - 70) / ((orbCenter.dy - orbRadius * 0.12) - 70)),
    );
    final lowerColor = Color.lerp(color, _orbBlueTop, blend)!;
    final midColor = Color.lerp(color, lowerColor, 0.42)!;
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[color, midColor, lowerColor],
      ).createShader(bounds)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
  }

  static double _phaseFor(double t, _DripSpec spec) {
    return (t * spec.speed + spec.phaseOffset) % 1.0;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();

  static double _easeInCubic(double x) => x * x * x;

  static double _easeInOutCubic(double x) {
    if (x < 0.5) {
      return 4 * x * x * x;
    }
    return 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  @override
  bool shouldRepaint(covariant DynamicIslandDripPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.safeTop != safeTop ||
        oldDelegate.activeStretchIndex != activeStretchIndex ||
        oldDelegate.orbFill != orbFill ||
        oldDelegate.color != color;
  }
}

class _DripSpec {
  const _DripSpec({
    required this.anchorFactor,
    required this.phaseOffset,
    required this.speed,
    required this.shoulder,
    required this.neck,
    required this.tipRadius,
    required this.travel,
    required this.anchorLift,
  });

  final double anchorFactor;
  final double phaseOffset;
  final double speed;
  final double shoulder;
  final double neck;
  final double tipRadius;
  final double travel;
  final double anchorLift;
}
