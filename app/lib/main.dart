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
  int _cycleIndex = 0;
  double _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )
      ..addListener(() {
        final value = _controller.value;
        if (value < _lastValue) {
          setState(() {
            _cycleIndex++;
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
              color: Colors.black,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class DynamicIslandDripPainter extends CustomPainter {
  DynamicIslandDripPainter({
    required this.t,
    required this.safeTop,
    required this.activeStretchIndex,
    required this.color,
  });

  final double t;
  final double safeTop;
  final int activeStretchIndex;
  final Color color;

  static const List<_DripSpec> _drips = <_DripSpec>[
    _DripSpec(
      anchorFactor: -0.255,
      phaseOffset: 0.06,
      speed: 0.94,
      shoulder: 5.4,
      neck: 2.0,
      tipRadius: 3.3,
      travel: 58,
      anchorLift: -3.2,
    ),
    _DripSpec(
      anchorFactor: -0.128,
      phaseOffset: 0.34,
      speed: 1.07,
      shoulder: 5.9,
      neck: 2.2,
      tipRadius: 3.6,
      travel: 72,
      anchorLift: -1.4,
    ),
    _DripSpec(
      anchorFactor: 0.00,
      phaseOffset: 0.18,
      speed: 0.88,
      shoulder: 6.8,
      neck: 2.6,
      tipRadius: 4.2,
      travel: 104,
      anchorLift: 0.0,
    ),
    _DripSpec(
      anchorFactor: 0.128,
      phaseOffset: 0.57,
      speed: 1.13,
      shoulder: 5.9,
      neck: 2.2,
      tipRadius: 3.6,
      travel: 70,
      anchorLift: -1.4,
    ),
    _DripSpec(
      anchorFactor: 0.255,
      phaseOffset: 0.79,
      speed: 0.95,
      shoulder: 5.4,
      neck: 2.0,
      tipRadius: 3.3,
      travel: 56,
      anchorLift: -3.2,
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
        ? math.min(112.0, size.width * 0.30)
        : math.min(126.0, size.width * 0.34);

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
        spec: _drips[i],
        fillPaint: fillPaint,
        shadowPaint: shadowPaint,
      );
    }
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
    final first = _drips.first;
    final last = _drips.last;
    final left = centerX + sourceWidth * first.anchorFactor - first.shoulder - 2.5;
    final right =
        centerX + sourceWidth * last.anchorFactor + last.shoulder + 2.5;
    const baseline = -1.8;
    final path = Path()..moveTo(left, baseY + baseline);

    for (final drip in _drips) {
      final anchorX = centerX + sourceWidth * drip.anchorFactor;
      final shoulder = drip.shoulder * 0.84;
      final anchorY = baseY + drip.anchorLift;

      path
        ..lineTo(anchorX - shoulder, baseY + baseline)
        ..cubicTo(
          anchorX - shoulder * 0.56,
          baseY + baseline,
          anchorX - drip.neck * 0.9,
          anchorY - 0.4,
          anchorX,
          anchorY,
        )
        ..cubicTo(
          anchorX + drip.neck * 0.9,
          anchorY - 0.4,
          anchorX + shoulder * 0.56,
          baseY + baseline,
          anchorX + shoulder,
          baseY + baseline,
        );
    }

    path
      ..lineTo(right, baseY + baseline)
      ..lineTo(right, baseY)
      ..lineTo(left, baseY)
      ..close();

    canvas.drawPath(path, fillPaint);
  }

  void _drawDrip(
    Canvas canvas, {
    required int index,
    required double centerX,
    required double sourceWidth,
    required double baseY,
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
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final gather = _normalize(phase, 0.00, 0.20);
    final stretch = _normalize(phase, 0.20, 0.72);
    final tail = _normalize(phase, 0.72, 0.84);
    final rebound = _normalize(phase, 0.84, 0.93);
    final settle = _normalize(phase, 0.93, 1.0);

    final shoulder = _lerp(
      spec.shoulder * 0.80,
      spec.shoulder,
      _easeOutCubic(gather),
    );
    final neck = _lerp(
      spec.shoulder * 0.52,
      spec.neck,
      _easeInOutCubic(stretch),
    );

    final stretchLength = 7 + _easeInOutCubic(stretch) * (spec.travel * 0.62);
    final tailLength = stretchLength + _easeOutCubic(tail) * (spec.travel * 0.20);
    final reboundLength = tailLength - _easeInOutCubic(rebound) * 6.0;
    final finalLength = _lerp(reboundLength, 2.2, settle);

    final length = phase < 0.20
        ? 1.2 + _easeOutCubic(gather) * 6.4
        : phase < 0.84
            ? tailLength
            : phase < 0.93
                ? reboundLength
                : finalLength;

    final tipRadius = _lerp(
      spec.tipRadius * 0.70,
      spec.tipRadius,
      _easeOutCubic(_normalize(phase, 0.28, 0.88)),
    );

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
            tipRadius: tipRadius,
          );

    canvas.drawPath(path.shift(const Offset(0, 1.3)), shadowPaint);
    canvas.drawPath(path, fillPaint);
  }

  void _drawDirectDrop(
    Canvas canvas, {
    required double phase,
    required double anchorX,
    required double anchorY,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final gather = _normalize(phase, 0.00, 0.18);
    final release = _normalize(phase, 0.18, 0.30);
    final fall = _normalize(phase, 0.24, 0.72);
    final fade = _normalize(phase, 0.74, 1.0);

    final beadShoulder = _lerp(
      spec.shoulder * 0.52,
      spec.shoulder * 0.72,
      _easeOutCubic(gather),
    );
    final beadNeck = _lerp(
      spec.neck * 0.70,
      spec.neck * 0.92,
      _easeOutCubic(gather),
    );

    final bulge = phase < 0.18
        ? 1.1 + _easeOutCubic(gather) * 5.8
        : phase < 0.30
            ? _lerp(6.9, 2.4, _easeInOutCubic(release))
            : _lerp(2.4, 1.2, _easeInOutCubic(_normalize(phase, 0.30, 1.0)));

    final beadPath = _buildBulgePath(
      anchorX: anchorX,
      baseY: anchorY,
      shoulder: beadShoulder,
      neck: beadNeck,
      bulge: bulge,
    );
    canvas.drawPath(beadPath.shift(const Offset(0, 1.0)), shadowPaint);
    canvas.drawPath(beadPath, fillPaint);

    final dropGrow = _easeOutCubic(_normalize(phase, 0.22, 0.40));
    final dropShrink = 1 - _easeInCubic(fade);
    final dropRadius = spec.tipRadius * dropGrow * math.max(0.0, dropShrink);
    if (dropRadius <= 0.05) {
      return;
    }

    final dropY = anchorY + 7 + _easeInCubic(fall) * spec.travel;
    final dropX = anchorX;

    canvas.drawCircle(
      Offset(dropX, dropY + 1),
      dropRadius,
      shadowPaint,
    );
    canvas.drawCircle(
      Offset(dropX, dropY),
      dropRadius,
      fillPaint,
    );
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
