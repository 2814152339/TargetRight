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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();
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
    required this.color,
  });

  final double t;
  final double safeTop;
  final Color color;

  static const List<_DripSpec> _drips = <_DripSpec>[
    _DripSpec(
      anchorFactor: -0.19,
      phaseOffset: 0.06,
      speed: 0.94,
      shoulder: 5.6,
      neck: 2.1,
      primaryLength: 32,
      tailLength: 30,
      tipRadius: 3.3,
      rebound: 5.5,
      detachedDrop: false,
    ),
    _DripSpec(
      anchorFactor: -0.095,
      phaseOffset: 0.34,
      speed: 1.07,
      shoulder: 6.2,
      neck: 2.3,
      primaryLength: 48,
      tailLength: 38,
      tipRadius: 3.8,
      rebound: 6.0,
      detachedDrop: false,
    ),
    _DripSpec(
      anchorFactor: 0.00,
      phaseOffset: 0.18,
      speed: 0.88,
      shoulder: 6.8,
      neck: 2.6,
      primaryLength: 62,
      tailLength: 56,
      tipRadius: 4.2,
      rebound: 7.0,
      detachedDrop: true,
    ),
    _DripSpec(
      anchorFactor: 0.095,
      phaseOffset: 0.57,
      speed: 1.13,
      shoulder: 6.2,
      neck: 2.3,
      primaryLength: 44,
      tailLength: 36,
      tipRadius: 3.8,
      rebound: 5.8,
      detachedDrop: false,
    ),
    _DripSpec(
      anchorFactor: 0.19,
      phaseOffset: 0.79,
      speed: 0.95,
      shoulder: 5.6,
      neck: 2.1,
      primaryLength: 30,
      tailLength: 28,
      tipRadius: 3.3,
      rebound: 5.2,
      detachedDrop: false,
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

    for (final drip in _drips) {
      _drawDrip(
        canvas,
        centerX: centerX,
        sourceWidth: sourceWidth,
        baseY: sourceBottom + 0.8,
        spec: drip,
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
    final pill = RRect.fromRectAndRadius(rect, Radius.circular(height / 2));

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
    final left = centerX - sourceWidth * 0.235;
    final right = centerX + sourceWidth * 0.235;
    final path = Path()..moveTo(left, baseY - 1.8);

    for (final drip in _drips) {
      final anchorX = centerX + sourceWidth * drip.anchorFactor;
      final shoulder = drip.shoulder * 0.82;
      final dipDepth = drip.detachedDrop ? baseY + 1.35 : baseY - 0.18;
      final controlY = drip.detachedDrop ? baseY + 1.1 : baseY - 0.72;
      final neckWidth = drip.detachedDrop ? drip.neck * 0.9 : drip.neck * 0.44;

      path
        ..lineTo(anchorX - shoulder, baseY - 1.8)
        ..cubicTo(
          anchorX - shoulder * 0.56,
          baseY - 1.8,
          anchorX - neckWidth,
          controlY,
          anchorX,
          dipDepth,
        )
        ..cubicTo(
          anchorX + neckWidth,
          controlY,
          anchorX + shoulder * 0.56,
          baseY - 1.8,
          anchorX + shoulder,
          baseY - 1.8,
        );
    }

    path
      ..lineTo(right, baseY - 1.8)
      ..lineTo(right, baseY)
      ..lineTo(left, baseY)
      ..close();

    canvas.drawPath(path, fillPaint);
  }

  void _drawDrip(
    Canvas canvas, {
    required double centerX,
    required double sourceWidth,
    required double baseY,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final phase = (t * spec.speed + spec.phaseOffset) % 1.0;
    if (phase < 0.05) {
      return;
    }

    final anchorX = centerX + sourceWidth * spec.anchorFactor;
    if (!spec.detachedDrop) {
      _drawDirectCircleDrop(
        canvas,
        phase: phase,
        anchorX: anchorX,
        baseY: baseY,
        spec: spec,
        fillPaint: fillPaint,
        shadowPaint: shadowPaint,
      );
      return;
    }

    final shoulderGrow = _easeOutCubic(_normalize(phase, 0.06, 0.28));
    final stretchPhase = _normalize(phase, 0.16, 0.74);
    final tailPhase = _normalize(phase, 0.74, 1.0);
    final reboundPhase = _normalize(phase, 0.82, 1.0);

    final shoulder = _lerp(spec.shoulder * 0.78, spec.shoulder, shoulderGrow);
    final neck = _lerp(spec.shoulder * 0.48, spec.neck, stretchPhase);

    var length = phase < 0.16
        ? _easeOutCubic(_normalize(phase, 0.05, 0.16)) * 7
        : 6 +
              _easeInOutCubic(stretchPhase) * spec.primaryLength +
              _easeInCubic(tailPhase) * spec.tailLength;
    length -= _easeInOutCubic(reboundPhase) * spec.rebound;
    length = math.max(1.4, length).toDouble();

    final tipRadius = _lerp(
      spec.tipRadius * 0.72,
      spec.tipRadius,
      _easeOutCubic(_normalize(phase, 0.38, 1.0)),
    );

    final tipCenterY = baseY + length;

    final path = length < 8
        ? _buildBulgePath(
            anchorX: anchorX,
            baseY: baseY,
            shoulder: shoulder,
            neck: neck,
            bulge: math.max(1.5, length),
          )
        : _buildDripPath(
            anchorX: anchorX,
            baseY: baseY,
            shoulder: shoulder,
            neck: neck,
            length: length,
            tipRadius: tipRadius,
          );

    canvas.drawPath(path.shift(const Offset(0, 1.3)), shadowPaint);
    canvas.drawPath(path, fillPaint);

    if (spec.detachedDrop && phase > 0.76) {
      final detachedPhase = _normalize(phase, 0.76, 1.0);
      final detachedRadius = _lerp(
        spec.tipRadius * 0.36,
        spec.tipRadius * 0.62,
        detachedPhase,
      );
      final detachedX = anchorX;
      final detachedY = tipCenterY + 8 + detachedPhase * detachedPhase * 64;

      canvas.drawCircle(
        Offset(detachedX, detachedY + 1),
        detachedRadius,
        shadowPaint,
      );
      canvas.drawCircle(
        Offset(detachedX, detachedY),
        detachedRadius,
        fillPaint,
      );
    }
  }

  void _drawDirectCircleDrop(
    Canvas canvas, {
    required double phase,
    required double anchorX,
    required double baseY,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final emergePhase = _normalize(phase, 0.05, 0.28);
    final fallPhase = _normalize(phase, 0.28, 1.0);
    final radius = spec.tipRadius * 1.02;
    final hiddenCenterY = baseY - radius * 0.78;
    final exposedCenterY = baseY + radius;
    final emergeY = _lerp(
      hiddenCenterY,
      exposedCenterY,
      _easeInOutCubic(emergePhase),
    );
    final fallDistance = 18 + spec.primaryLength + spec.tailLength * 0.92;
    final fallY = exposedCenterY + _easeInCubic(fallPhase) * fallDistance;
    final centerY = phase < 0.28 ? emergeY : fallY;

    canvas.drawCircle(Offset(anchorX, centerY + 1), radius, shadowPaint);
    canvas.drawCircle(Offset(anchorX, centerY), radius, fillPaint);
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
    required this.primaryLength,
    required this.tailLength,
    required this.tipRadius,
    required this.rebound,
    required this.detachedDrop,
  });

  final double anchorFactor;
  final double phaseOffset;
  final double speed;
  final double shoulder;
  final double neck;
  final double primaryLength;
  final double tailLength;
  final double tipRadius;
  final double rebound;
  final bool detachedDrop;
}
