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
      anchorFactor: -0.28,
      phaseOffset: 0.02,
      speed: 1.08,
      shoulder: 4.2,
      neck: 1.5,
      primaryLength: 30,
      tailLength: 34,
      tipRadius: 2.8,
      drift: 1.8,
      detachedDrop: true,
    ),
    _DripSpec(
      anchorFactor: -0.18,
      phaseOffset: 0.31,
      speed: 0.92,
      shoulder: 5.0,
      neck: 1.8,
      primaryLength: 42,
      tailLength: 48,
      tipRadius: 3.1,
      drift: 1.2,
      detachedDrop: false,
    ),
    _DripSpec(
      anchorFactor: -0.09,
      phaseOffset: 0.71,
      speed: 1.22,
      shoulder: 3.8,
      neck: 1.3,
      primaryLength: 24,
      tailLength: 28,
      tipRadius: 2.4,
      drift: 0.8,
      detachedDrop: true,
    ),
    _DripSpec(
      anchorFactor: 0.00,
      phaseOffset: 0.16,
      speed: 0.86,
      shoulder: 5.8,
      neck: 2.0,
      primaryLength: 54,
      tailLength: 74,
      tipRadius: 3.8,
      drift: 1.0,
      detachedDrop: true,
    ),
    _DripSpec(
      anchorFactor: 0.10,
      phaseOffset: 0.52,
      speed: 1.34,
      shoulder: 3.6,
      neck: 1.2,
      primaryLength: 20,
      tailLength: 24,
      tipRadius: 2.2,
      drift: 1.5,
      detachedDrop: false,
    ),
    _DripSpec(
      anchorFactor: 0.20,
      phaseOffset: 0.83,
      speed: 1.03,
      shoulder: 4.6,
      neck: 1.6,
      primaryLength: 34,
      tailLength: 44,
      tipRadius: 2.9,
      drift: 1.1,
      detachedDrop: true,
    ),
    _DripSpec(
      anchorFactor: 0.30,
      phaseOffset: 0.43,
      speed: 0.95,
      shoulder: 4.1,
      neck: 1.4,
      primaryLength: 28,
      tailLength: 36,
      tipRadius: 2.6,
      drift: 0.9,
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
    final sourceWidth = math.min(126.0, size.width * 0.34);
    final hasDynamicIslandInset = safeTop >= 44;

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

    for (final drip in _drips) {
      _drawDrip(
        canvas,
        centerX: centerX,
        sourceWidth: sourceWidth,
        baseY: sourceBottom - 1,
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
    final topY = math.max(0.0, top + 18).toDouble();
    final path = Path()
      ..moveTo(left + 10, topY)
      ..lineTo(right - 10, topY)
      ..quadraticBezierTo(right, topY, right, topY + 8)
      ..cubicTo(
        right - width * 0.18,
        bottom + 1.5,
        centerX + width * 0.12,
        bottom + 0.6,
        centerX,
        bottom + 2.5,
      )
      ..cubicTo(
        centerX - width * 0.12,
        bottom + 0.6,
        left + width * 0.18,
        bottom + 1.5,
        left,
        topY + 8,
      )
      ..quadraticBezierTo(left, topY, left + 10, topY)
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
    if (phase < 0.06) {
      return;
    }

    final anchorX = centerX + sourceWidth * spec.anchorFactor;
    final drift =
        math.sin((t + spec.phaseOffset) * math.pi * 2) * spec.drift;
    final shoulderGrow = _easeOutCubic(_normalize(phase, 0.06, 0.28));
    final stretchPhase = _normalize(phase, 0.16, 0.74);
    final tailPhase = _normalize(phase, 0.74, 1.0);

    final shoulder = _lerp(spec.shoulder * 0.78, spec.shoulder, shoulderGrow);
    final neck = _lerp(spec.shoulder * 0.48, spec.neck, stretchPhase);

    final length = phase < 0.16
        ? _easeOutCubic(_normalize(phase, 0.06, 0.16)) * 6
        : 6 +
            _easeInOutCubic(stretchPhase) * spec.primaryLength +
            _easeInCubic(tailPhase) * spec.tailLength;

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
            drift: drift,
          );

    canvas.drawPath(path.shift(const Offset(0, 1.3)), shadowPaint);
    canvas.drawPath(path, fillPaint);

    if (spec.detachedDrop && phase > 0.76) {
      final detachedPhase = _normalize(phase, 0.76, 1.0);
      final detachedRadius =
          _lerp(spec.tipRadius * 0.36, spec.tipRadius * 0.62, detachedPhase);
      final detachedX = anchorX + drift * 1.6 + math.sin(detachedPhase * 5) * 2;
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
    required double drift,
  }) {
    final tipCenterX = anchorX + drift;
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
    required this.drift,
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
  final double drift;
  final bool detachedDrop;
}
