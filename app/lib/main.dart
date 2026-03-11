import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
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
      duration: const Duration(milliseconds: 2200),
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

    return Scaffold(
      backgroundColor: bgColor,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: DynamicIslandDripPainter(
              t: _controller.value,
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
  DynamicIslandDripPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final cx = size.width / 2;

    const islandWidth = 126.0;
    const islandHeight = 36.0;
    const top = 54.0;
    const radius = islandHeight / 2;

    final left = cx - islandWidth / 2;
    final right = cx + islandWidth / 2;
    final bottom = top + islandHeight;

    final phase = _phase(t);
    final bulge = _bulgeAmount(phase);
    final drop = _dropLength(phase);
    final neck = _neckWidth(phase);
    final shoulder = _shoulderWidth(phase);
    final bottomRadius = _dropBottomRadius(phase);

    final path = Path();

    path.moveTo(left + radius, top);
    path.arcToPoint(
      Offset(left, top + radius),
      radius: const Radius.circular(radius),
      clockwise: false,
    );
    path.lineTo(left, bottom - radius);
    path.arcToPoint(
      Offset(left + radius, bottom),
      radius: const Radius.circular(radius),
      clockwise: false,
    );

    final liquidLeft = cx - shoulder;
    final liquidRight = cx + shoulder;

    path.lineTo(liquidLeft, bottom);

    if (drop <= 1.0) {
      path.cubicTo(
        cx - shoulder * 0.55,
        bottom,
        cx - neck,
        bottom + bulge,
        cx,
        bottom + bulge,
      );
      path.cubicTo(
        cx + neck,
        bottom + bulge,
        cx + shoulder * 0.55,
        bottom,
        liquidRight,
        bottom,
      );
    } else {
      final neckLeft = cx - neck;
      final neckRight = cx + neck;

      final tipCenterY = bottom + drop;
      final tipTopY = tipCenterY - bottomRadius;

      path.cubicTo(
        liquidLeft + 10,
        bottom,
        neckLeft + 10,
        bottom + drop * 0.14,
        neckLeft,
        bottom + drop * 0.32,
      );

      path.cubicTo(
        neckLeft - 2,
        bottom + drop * 0.55,
        cx - bottomRadius * 0.95,
        tipTopY,
        cx - bottomRadius,
        tipCenterY,
      );

      path.arcToPoint(
        Offset(cx + bottomRadius, tipCenterY),
        radius: Radius.circular(bottomRadius),
        clockwise: false,
      );

      path.cubicTo(
        cx + bottomRadius * 0.95,
        tipTopY,
        neckRight + 2,
        bottom + drop * 0.55,
        neckRight,
        bottom + drop * 0.32,
      );

      path.cubicTo(
        neckRight - 10,
        bottom + drop * 0.14,
        liquidRight - 10,
        bottom,
        liquidRight,
        bottom,
      );
    }

    path.lineTo(right - radius, bottom);
    path.arcToPoint(
      Offset(right, bottom - radius),
      radius: const Radius.circular(radius),
      clockwise: false,
    );
    path.lineTo(right, top + radius);
    path.arcToPoint(
      Offset(right - radius, top),
      radius: const Radius.circular(radius),
      clockwise: false,
    );
    path.close();

    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  double _phase(double value) => value;

  double _bulgeAmount(double p) {
    if (p < 0.18) {
      final x = p / 0.18;
      return _easeOutCubic(x) * 12;
    }
    if (p < 0.45) {
      final x = (p - 0.18) / 0.27;
      return 12 + _easeOutCubic(x) * 8;
    }
    return 20;
  }

  double _dropLength(double p) {
    if (p < 0.12) {
      return 0;
    }

    if (p < 0.30) {
      final x = (p - 0.12) / 0.18;
      return _easeInCubic(x) * 40;
    }

    if (p < 0.62) {
      final x = (p - 0.30) / 0.32;
      return 40 + _easeInOutCubic(x) * 95;
    }

    final x = (p - 0.62) / 0.38;
    return 135 + _easeInCubic(x) * 170;
  }

  double _neckWidth(double p) {
    if (p < 0.12) {
      return 24;
    }

    if (p < 0.45) {
      final x = (p - 0.12) / 0.33;
      return 24 - x * 8;
    }

    if (p < 0.75) {
      final x = (p - 0.45) / 0.30;
      return 16 - x * 5;
    }

    final x = (p - 0.75) / 0.25;
    return 11 - x * 3;
  }

  double _shoulderWidth(double p) {
    if (p < 0.12) {
      return 28;
    }

    if (p < 0.40) {
      final x = (p - 0.12) / 0.28;
      return 28 + x * 14;
    }

    if (p < 0.75) {
      return 42;
    }

    final x = (p - 0.75) / 0.25;
    return 42 - x * 5;
  }

  double _dropBottomRadius(double p) {
    if (p < 0.20) {
      return 8;
    }

    if (p < 0.55) {
      final x = (p - 0.20) / 0.35;
      return 8 + _easeOutCubic(x) * 12;
    }

    final x = (p - 0.55) / 0.45;
    return 20 + _easeOutCubic(x) * 10;
  }

  double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();

  double _easeInCubic(double x) => x * x * x;

  double _easeInOutCubic(double x) {
    return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  @override
  bool shouldRepaint(covariant DynamicIslandDripPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.color != color;
  }
}
