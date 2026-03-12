import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
    with TickerProviderStateMixin {
  static const double _panelRevealDistance = 106;
  late final AnimationController _controller;
  late final AnimationController _panelController;
  late final List<double> _lastPhases;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSub;
  bool _isTrackingPanelDrag = false;
  double _panelDragStartX = 0;
  double _panelDragStartValue = 0;
  int _cycleIndex = 0;
  double _lastValue = 0;
  double _orbFill = 0.24;
  Duration _lastElapsed = Duration.zero;
  double _targetTilt = 0;
  double _liquidTilt = 0;
  double _tiltVelocity = 0;
  double _shakeKick = 0;
  double _sloshing = 0;

  @override
  void initState() {
    super.initState();
    _lastPhases = List<double>.filled(
      DynamicIslandDripPainter._drips.length,
      0,
    );
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _startMotionTracking();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 4930),
          )
          ..addListener(() {
            final value = _controller.value;
            final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
            final dt = _frameDelta(elapsed);
            var nextCycleIndex = _cycleIndex;
            var nextOrbFill = _orbFill;
            var needsUpdate = false;

            if (value < _lastValue) {
              nextCycleIndex++;
              needsUpdate = true;
            }

            final activeStretchIndex = _stretchIndexForCycle(nextCycleIndex);

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

            _updateLiquidMotion(dt);

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
    _accelerometerSub?.cancel();
    _userAccelerometerSub?.cancel();
    _panelController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Colors.white;
    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _handlePanelDragStart,
        onHorizontalDragUpdate: _handlePanelDragUpdate,
        onHorizontalDragEnd: _handlePanelDragEnd,
        onHorizontalDragCancel: () => _isTrackingPanelDrag = false,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _controller,
            _panelController,
          ]),
          builder: (context, _) {
            final panelProgress = Curves.easeOutCubic.transform(
              _panelController.value,
            );
            final sceneOffsetX = panelProgress * 22;
            final sceneOpacity = 1 - panelProgress;
            final sceneScale = 1 - panelProgress * 0.035;

            return LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: <Widget>[
                    _SlideOutReplicaPanel(progress: panelProgress),
                    IgnorePointer(
                      ignoring: panelProgress > 0.08,
                      child: Opacity(
                        opacity: sceneOpacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(sceneOffsetX, 0),
                          child: Transform.scale(
                            scale: sceneScale,
                            alignment: Alignment.center,
                            child: Stack(
                              children: <Widget>[
                                CustomPaint(
                                  painter: DynamicIslandDripPainter(
                                    t: _controller.value,
                                    safeTop: safeTop,
                                    activeStretchIndex: _stretchIndexForCycle(
                                      _cycleIndex,
                                    ),
                                    previousStretchIndex: _stretchIndexForCycle(
                                      _cycleIndex - 1,
                                    ),
                                    orbFill: _orbFill,
                                    liquidTilt: _liquidTilt,
                                    sloshing: _sloshing,
                                    color: Colors.black,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                                Positioned(
                                  left: 16,
                                  top: safeTop + 18,
                                  child: _ProfileEntry(
                                    nickname: '用户昵称',
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (context) =>
                                              const ProfilePlaceholderPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  bool _crossedThreshold(double previous, double current, double threshold) {
    if (current >= previous) {
      return previous < threshold && current >= threshold;
    }
    return previous < threshold || current >= threshold;
  }

  int _stretchIndexForCycle(int cycle) {
    const allowed = <int>[0, 4, 1, 3];
    return allowed[cycle % allowed.length];
  }

  void _startMotionTracking() {
    try {
      _accelerometerSub =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen((event) {
            _targetTilt = (-event.x / 7.2).clamp(-1.0, 1.0).toDouble();
          });

      _userAccelerometerSub =
          userAccelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen((event) {
            final horizontalKick = (-event.x / 12)
                .clamp(-0.28, 0.28)
                .toDouble();
            final shakeEnergy =
                (((event.x.abs() * 0.9) + (event.y.abs() * 0.6)) / 14).clamp(
                  0.0,
                  0.45,
                );
            _shakeKick += horizontalKick * 0.28;
            _sloshing = (_sloshing + horizontalKick * (0.65 + shakeEnergy))
                .clamp(-1.15, 1.15)
                .toDouble();
          });
    } catch (_) {
      _accelerometerSub = null;
      _userAccelerometerSub = null;
    }
  }

  double _frameDelta(Duration elapsed) {
    final rawDelta = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (rawDelta <= 0 || rawDelta > 0.1) {
      return 1 / 60;
    }
    return rawDelta;
  }

  void _updateLiquidMotion(double dt) {
    final springPull = (_targetTilt - _liquidTilt) * 10.5;
    _tiltVelocity += springPull * dt;
    _tiltVelocity += _shakeKick;
    _shakeKick = 0;

    final frameDamping = math.pow(0.90, dt * 60).toDouble();
    _tiltVelocity *= frameDamping;
    _liquidTilt += _tiltVelocity * dt * 60;
    _liquidTilt = _liquidTilt.clamp(-1.15, 1.15).toDouble();

    final sloshDamping = math.pow(0.92, dt * 60).toDouble();
    _sloshing *= sloshDamping;
  }

  void _handlePanelDragStart(DragStartDetails details) {
    final isFromLeftEdge = details.localPosition.dx <= 30;
    final canResumeOpenPanel = _panelController.value > 0.02;
    _isTrackingPanelDrag = isFromLeftEdge || canResumeOpenPanel;
    if (!_isTrackingPanelDrag) {
      return;
    }
    _panelDragStartX = details.globalPosition.dx;
    _panelDragStartValue = _panelController.value;
  }

  void _handlePanelDragUpdate(DragUpdateDetails details) {
    if (!_isTrackingPanelDrag) {
      return;
    }

    final deltaX = details.globalPosition.dx - _panelDragStartX;
    final nextValue = (_panelDragStartValue + deltaX / _panelRevealDistance)
        .clamp(0.0, 1.0);
    _panelController.value = nextValue;
  }

  void _handlePanelDragEnd(DragEndDetails details) {
    if (!_isTrackingPanelDrag) {
      return;
    }
    _isTrackingPanelDrag = false;

    final velocity = details.primaryVelocity ?? 0;
    final target = velocity > 220
        ? 1.0
        : velocity < -220
        ? 0.0
        : (_panelController.value >= 0.52 ? 1.0 : 0.0);

    _panelController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({required this.nickname, required this.onTap});

  final String nickname;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '你好,$nickname',
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfilePlaceholderPage extends StatelessWidget {
  const ProfilePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('我的'),
      ),
      body: const Center(
        child: Text(
          '我的页面待设计',
          style: TextStyle(fontSize: 18, color: Colors.black),
        ),
      ),
    );
  }
}

class _SlideOutReplicaPanel extends StatefulWidget {
  const _SlideOutReplicaPanel({required this.progress});

  final double progress;

  @override
  State<_SlideOutReplicaPanel> createState() => _SlideOutReplicaPanelState();
}

class _SlideOutReplicaPanelState extends State<_SlideOutReplicaPanel> {
  static const List<ReplicaCardData> _cards = <ReplicaCardData>[
    ReplicaCardData(
      index: 1,
      title: 'mobile',
      color: Color(0xFFFF0008),
      slotColor: Color(0xFF8D0000),
      titleLines: 1,
      angleBias: 0.108,
      radiusBias: -18,
      yBias: -14,
      xBias: 18,
      scaleBias: 0.060,
    ),
    ReplicaCardData(
      index: 2,
      title: 'auxiliary',
      color: Color(0xFFEF7A00),
      slotColor: Color(0xFF7A3500),
      titleLines: 1,
      angleBias: 0.060,
      radiusBias: -8,
      yBias: -10,
      xBias: 10,
      scaleBias: 0.028,
    ),
    ReplicaCardData(
      index: 3,
      title: 'cross-\nplatform',
      color: Color(0xFFE8EE00),
      slotColor: Color(0xFF6A6700),
      titleLines: 2,
      angleBias: 0.018,
      radiusBias: 4,
      yBias: -2,
      xBias: 2,
      scaleBias: 0.006,
    ),
    ReplicaCardData(
      index: 4,
      title: 'back-end',
      color: Color(0xFF68F40D),
      slotColor: Color(0xFF2A6500),
      titleLines: 1,
      angleBias: -0.018,
      radiusBias: 12,
      yBias: 12,
      xBias: -10,
      scaleBias: -0.010,
    ),
    ReplicaCardData(
      index: 5,
      title: 'online',
      color: Color(0xFF18FF00),
      slotColor: Color(0xFF006B00),
      titleLines: 1,
      angleBias: 0.036,
      radiusBias: -12,
      yBias: 0,
      xBias: 14,
      scaleBias: 0.010,
    ),
    ReplicaCardData(
      index: 6,
      title: 'primary',
      color: Color(0xFF18ED7D),
      slotColor: Color(0xFF006D45),
      titleLines: 1,
      angleBias: 0.012,
      radiusBias: -8,
      yBias: 7,
      xBias: 8,
      scaleBias: 0.004,
    ),
    ReplicaCardData(
      index: 7,
      title: 'cross-\nplatform',
      color: Color(0xFF24DDE5),
      slotColor: Color(0xFF006D74),
      titleLines: 2,
      angleBias: -0.012,
      radiusBias: 0,
      yBias: 14,
      xBias: -6,
      scaleBias: -0.004,
    ),
    ReplicaCardData(
      index: 8,
      title: 'cross-\nplatform',
      color: Color(0xFF1F7BF4),
      slotColor: Color(0xFF003A86),
      titleLines: 2,
      angleBias: -0.028,
      radiusBias: 9,
      yBias: 22,
      xBias: -14,
      scaleBias: -0.010,
    ),
    ReplicaCardData(
      index: 9,
      title: 'redundant',
      color: Color(0xFF1713FF),
      slotColor: Color(0xFF010076),
      titleLines: 1,
      angleBias: -0.050,
      radiusBias: 18,
      yBias: 30,
      xBias: -24,
      scaleBias: -0.018,
    ),
    ReplicaCardData(
      index: 10,
      title: 'design',
      color: Color(0xFFA62CF8),
      slotColor: Color(0xFF46007A),
      titleLines: 1,
      angleBias: -0.072,
      radiusBias: 28,
      yBias: 38,
      xBias: -34,
      scaleBias: -0.028,
    ),
  ];
  static const double _stepExtent = 150.0;

  final ScrollController _scrollController = ScrollController();
  bool _isSnapping = false;

  void _maybeSnap(ScrollEndNotification notification) {
    if (!_scrollController.hasClients || _isSnapping) {
      return;
    }

    final position = _scrollController.position;
    final current = position.pixels;
    final velocity = notification.dragDetails?.primaryVelocity ?? 0.0;
    var nearestIndex = (current / _stepExtent).round().clamp(
      0,
      _cards.length - 1,
    );

    if (velocity < -120) {
      nearestIndex = math.max(0, nearestIndex - 1);
    } else if (velocity > 120) {
      nearestIndex = math.min(_cards.length - 1, nearestIndex + 1);
    }

    final target = (nearestIndex * _stepExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - current).abs() < 1.0) {
      return;
    }

    _isSnapping = true;
    _scrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          _isSnapping = false;
        });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final reveal = math.max(0.001, widget.progress);
    final overlayOpacity = Curves.easeOutCubic.transform(widget.progress);
    final entryOffset = -42 * (1 - overlayOpacity);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: widget.progress < 0.06,
        child: Opacity(
          opacity: overlayOpacity,
          child: ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: reveal,
              child: Transform.translate(
                offset: Offset(entryOffset, 0),
                child: SizedBox(
                  width: media.width,
                  height: media.height,
                  child: ColoredBox(
                    color: const Color(0xFFE7E7E7),
                    child: SafeArea(
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: (notification) {
                          _maybeSnap(notification);
                          return false;
                        },
                        child: AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, _) {
                            final offset = _scrollController.hasClients
                                ? _scrollController.offset
                                : 0.0;
                            final maxExtent = math.max(
                              1.0,
                              (_cards.length - 1) * _stepExtent,
                            );
                            final fractionalIndex = (offset / _stepExtent)
                                .clamp(0.0, _cards.length - 1.0);
                            final progress = (offset / maxExtent).clamp(
                              0.0,
                              1.0,
                            );

                            return Stack(
                              children: <Widget>[
                                Positioned(
                                  left: media.width * 0.050,
                                  top: media.height * 0.435,
                                  child: LeftSegmentIndicator(
                                    progress: progress,
                                  ),
                                ),
                                SingleChildScrollView(
                                  controller: _scrollController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: SizedBox(
                                    height: _cards.length * _stepExtent + 1,
                                  ),
                                ),
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onVerticalDragUpdate: (details) {
                                      if (!_scrollController.hasClients) {
                                        return;
                                      }
                                      final next =
                                          (_scrollController.offset -
                                                  details.delta.dy)
                                              .clamp(
                                                0.0,
                                                _scrollController
                                                    .position
                                                    .maxScrollExtent,
                                              );
                                      _scrollController.jumpTo(next);
                                    },
                                    onVerticalDragEnd: (details) {
                                      final fakeNotification =
                                          ScrollEndNotification(
                                            metrics: _scrollController.position,
                                            context: context,
                                            dragDetails: DragEndDetails(
                                              primaryVelocity:
                                                  details.primaryVelocity,
                                            ),
                                          );
                                      _maybeSnap(fakeNotification);
                                    },
                                    child: Stack(
                                      children: <Widget>[
                                        for (var i = 0; i < _cards.length; i++)
                                          FanReplicaCard(
                                            item: _cards[i],
                                            itemIndex: i,
                                            activeIndex: fractionalIndex,
                                            screenSize: media,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: media.width * 0.010,
                                  top: media.height * 0.095,
                                  bottom: media.height * 0.095,
                                  child: VisualScrollRail(progress: progress),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReplicaCardData {
  const ReplicaCardData({
    required this.index,
    required this.title,
    required this.color,
    required this.slotColor,
    this.titleLines = 1,
    this.angleBias = 0,
    this.radiusBias = 0,
    this.yBias = 0,
    this.xBias = 0,
    this.scaleBias = 0,
  });

  final int index;
  final String title;
  final Color color;
  final Color slotColor;
  final int titleLines;
  final double angleBias;
  final double radiusBias;
  final double yBias;
  final double xBias;
  final double scaleBias;
}

class FanReplicaCard extends StatelessWidget {
  const FanReplicaCard({
    super.key,
    required this.item,
    required this.itemIndex,
    required this.activeIndex,
    required this.screenSize,
  });

  final ReplicaCardData item;
  final int itemIndex;
  final double activeIndex;
  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    final delta = itemIndex - activeIndex;
    final absDelta = delta.abs();

    final fanCenter = Offset(
      screenSize.width * -0.58,
      screenSize.height * 0.79,
    );
    final baseRadius = screenSize.width * 1.30 + item.radiusBias;

    final baseAngle = -0.12;
    final stepAngle = 0.108;
    final edgeTighten = absDelta > 1.9 ? (absDelta - 1.9) * 0.012 : 0.0;
    final angle =
        (baseAngle +
                delta * stepAngle -
                delta.sign * edgeTighten +
                item.angleBias)
            .clamp(-1.18, -0.18);

    final cardWidth = screenSize.width * 0.705;
    final cardHeight = screenSize.width * 0.104;

    final arcX = fanCenter.dx + math.cos(angle) * baseRadius;
    final arcY = fanCenter.dy + math.sin(angle) * baseRadius;

    final x = arcX + item.xBias;
    final y = arcY + item.yBias;

    final tangentRotation = angle + math.pi / 2 - 0.08 + item.angleBias * 0.22;
    final focus = (1 - (absDelta / 2.85)).clamp(0.0, 1.0);
    final scale = 0.89 + focus * 0.12 + item.scaleBias;
    final opacity = 0.42 + focus * 0.58;
    final blur = 5.0 + focus * 10.0;
    final spread = 0.8 + focus * 2.4;
    final inwardShift = (1 - focus) * -12;

    return Positioned(
      left: x,
      top: y,
      child: Transform.translate(
        offset: Offset(-cardWidth * 0.16, -cardHeight / 2),
        child: Transform.rotate(
          angle: tangentRotation,
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: Offset(inwardShift, 0),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerLeft,
              child: Opacity(
                opacity: opacity,
                child: ReplicaCard(
                  item: item,
                  width: cardWidth,
                  height: cardHeight,
                  shadowBlur: blur,
                  shadowSpread: spread,
                  isFocused: focus > 0.94,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReplicaCard extends StatelessWidget {
  const ReplicaCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.shadowBlur = 8,
    this.shadowSpread = 2,
    this.isFocused = false,
  });

  final ReplicaCardData item;
  final double width;
  final double height;
  final double shadowBlur;
  final double shadowSpread;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final radius = height * 0.23;
    final slotInsetRight = width * 0.022;
    final slotInsetVertical = height * 0.082;
    final slotWidth = width * 0.305;
    final leftPadding = width * 0.045;
    final bigNumberWidth = width * 0.145;
    final titleFont = height * 0.255;
    final numberFont = height * 0.46;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: item.color.withValues(
                      alpha: isFocused ? 0.72 : 0.56,
                    ),
                    blurRadius: shadowBlur,
                    spreadRadius: shadowSpread,
                    offset: Offset(0, isFocused ? 3 : 1),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: slotInsetRight,
            top: slotInsetVertical,
            bottom: slotInsetVertical,
            child: Container(
              width: slotWidth,
              decoration: BoxDecoration(
                color: item.slotColor,
                borderRadius: BorderRadius.circular(height * 0.20),
              ),
            ),
          ),
          Positioned(
            left: leftPadding,
            top: 0,
            bottom: 0,
            right: slotWidth + slotInsetRight + width * 0.055,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: bigNumberWidth,
                  child: Transform.translate(
                    offset: const Offset(-1.5, 1.0),
                    child: Text(
                      '${item.index}',
                      style: TextStyle(
                        fontSize: numberFont,
                        height: 0.86,
                        fontWeight: FontWeight.w900,
                        color: Color.lerp(
                          const Color(0xFF111111),
                          Colors.black,
                          isFocused ? 0.25 : 0.0,
                        )!,
                        letterSpacing: -2.8,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: width * 0.025),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: item.titleLines,
                    style: TextStyle(
                      fontSize: titleFont,
                      height: item.titleLines > 1 ? 0.92 : 0.88,
                      fontWeight: isFocused ? FontWeight.w900 : FontWeight.w800,
                      color: Color.lerp(
                        const Color(0xFF161616),
                        Colors.black,
                        isFocused ? 0.20 : 0.0,
                      )!,
                      letterSpacing: -1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LeftSegmentIndicator extends StatelessWidget {
  const LeftSegmentIndicator({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 120,
      child: CustomPaint(painter: LeftSegmentIndicatorPainter(progress)),
    );
  }
}

class LeftSegmentIndicatorPainter extends CustomPainter {
  LeftSegmentIndicatorPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final inactive = Paint()
      ..color = const Color(0xFFAEAEAE)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final active = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    const count = 10;
    const startX = 1.5;
    const endX = 21.5;
    const gap = 8.8;
    const startY = 9.0;

    for (var i = 0; i < count; i++) {
      final y = startY + i * gap;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), inactive);
    }

    final activeIndex = (progress * (count - 1)).round().clamp(0, count - 1);
    final y = startY + activeIndex * gap;
    canvas.drawLine(Offset(startX, y), Offset(endX, y), active);
  }

  @override
  bool shouldRepaint(covariant LeftSegmentIndicatorPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class VisualScrollRail extends StatelessWidget {
  const VisualScrollRail({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final thumbHeight = constraints.maxHeight * 0.22;
          final maxTravel = constraints.maxHeight - thumbHeight;
          final thumbTop = maxTravel * progress;

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFDFDF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: thumbTop,
                child: Container(
                  height: thumbHeight,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
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
    required this.previousStretchIndex,
    required this.orbFill,
    required this.liquidTilt,
    required this.sloshing,
    required this.color,
  });

  final double t;
  final double safeTop;
  final int activeStretchIndex;
  final int previousStretchIndex;
  final double orbFill;
  final double liquidTilt;
  final double sloshing;
  final Color color;

  static const Color _orbBlueTop = Color(0xFF8CCCFF);
  static const Color _orbBlueBottom = Color(0xFF4A93FF);

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
      shadowPaint: shadowPaint,
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

    _drawOrbFront(canvas, center: orbCenter, radius: orbRadius);
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
    const inset = 7.2;
    final path = Path()
      ..moveTo(left + inset, topY + 0.2)
      ..cubicTo(
        centerX - width * 0.320,
        topY - 0.55,
        centerX + width * 0.320,
        topY - 0.55,
        right - inset,
        topY + 0.2,
      )
      ..quadraticBezierTo(right - 1, topY, right - 1, topY + 7)
      ..cubicTo(
        right - width * 0.046,
        bottom - 0.8,
        centerX + width * 0.350,
        bottom + 0.7,
        centerX,
        bottom + 1.8,
      )
      ..cubicTo(
        centerX - width * 0.350,
        bottom + 0.7,
        left + width * 0.046,
        bottom - 0.8,
        left + 1,
        topY + 7,
      )
      ..quadraticBezierTo(left + 1, topY, left + inset, topY + 0.2)
      ..close();

    canvas.drawPath(path, fillPaint);
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
    final phase = _phaseFor(t, spec);
    final anchorX = centerX + sourceWidth * spec.anchorFactor;
    final anchorY = baseY + spec.anchorLift;

    if (index == activeStretchIndex) {
      _drawStretchDrip(
        canvas,
        phase: t,
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

    if (index == previousStretchIndex && t < 0.16) {
      _drawResidualCap(
        canvas,
        phase: _normalize(t, 0.0, 0.16),
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
      orbCenter: orbCenter,
      orbRadius: orbRadius,
      spec: spec,
      fillPaint: fillPaint,
      shadowPaint: shadowPaint,
    );
  }

  void _drawResidualCap(
    Canvas canvas, {
    required double phase,
    required double anchorX,
    required double anchorY,
    required _DripSpec spec,
    required Paint fillPaint,
    required Paint shadowPaint,
  }) {
    final path = _buildBulgePath(
      anchorX: anchorX,
      baseY: anchorY,
      shoulder: _lerp(spec.shoulder * 0.42, spec.shoulder * 0.24, phase),
      neck: _lerp(spec.neck * 0.34, spec.neck * 0.16, phase),
      bulge: _lerp(2.1, 0.7, phase),
    );
    canvas.drawPath(path.shift(const Offset(0, 0.8)), shadowPaint);
    canvas.drawPath(path, fillPaint);
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
    final gather = _normalize(phase, 0.00, 0.18);
    const splitStart = 0.68;
    const connectedEnd = 0.24;
    final stretch = _normalize(phase, 0.18, splitStart);
    final split = _normalize(phase, splitStart, 1.0);
    final impactY =
        (_orbTopAtX(orbCenter, orbRadius, anchorX) ??
            (orbCenter.dy - orbRadius)) +
        spec.tipRadius * 0.16;

    final fullShoulder = _lerp(
      spec.shoulder * 0.80,
      spec.shoulder,
      _easeOutCubic(gather),
    );
    final fullNeck = _lerp(
      spec.shoulder * 0.48,
      spec.neck,
      _easeInOutCubic(stretch),
    );

    const minAttachedLength = 6.6;
    final attachedLength =
        minAttachedLength + _easeInOutCubic(stretch) * (spec.travel * 0.58);
    final attachedTipRadius = _lerp(
      spec.tipRadius * 0.72,
      spec.tipRadius * 1.06,
      _easeOutCubic(_normalize(phase, 0.22, splitStart)),
    );
    final releaseLength = attachedLength + spec.tipRadius * 0.76;
    final releaseTipRadius = spec.tipRadius * 1.14;

    if (phase < splitStart) {
      final length = phase < 0.18
          ? _lerp(1.2, minAttachedLength, _easeOutCubic(gather))
          : attachedLength;

      final path = length < 4.2
          ? _buildBulgePath(
              anchorX: anchorX,
              baseY: anchorY,
              shoulder: fullShoulder,
              neck: fullNeck,
              bulge: length,
            )
          : _buildDripPath(
              anchorX: anchorX,
              baseY: anchorY,
              shoulder: fullShoulder,
              neck: fullNeck,
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

    if (split < connectedEnd) {
      final connected = _easeInOutCubic(_normalize(split, 0.0, connectedEnd));
      final connectedLength = _lerp(attachedLength, releaseLength, connected);
      final connectedPath = _buildDripPath(
        anchorX: anchorX,
        baseY: anchorY,
        shoulder: _lerp(fullShoulder, spec.shoulder * 0.92, connected),
        neck: _lerp(fullNeck, spec.neck * 0.20, connected),
        length: connectedLength,
        tipRadius: _lerp(
          attachedTipRadius,
          releaseTipRadius,
          _easeOutCubic(connected),
        ),
      );

      canvas.drawPath(connectedPath.shift(const Offset(0, 1.15)), shadowPaint);
      canvas.drawPath(
        connectedPath,
        _gradientLiquidPaint(
          connectedPath.getBounds(),
          bottomY: anchorY + connectedLength + releaseTipRadius,
          orbCenter: orbCenter,
          orbRadius: orbRadius,
        ),
      );
      return;
    }

    final releasedSplit = _normalize(split, connectedEnd, 1.0);
    final detachPhase = _easeOutCubic(_normalize(releasedSplit, 0.0, 0.24));
    final tailRecover = _easeOutCubic(_normalize(releasedSplit, 0.06, 0.26));
    final upperLength = _lerp(releaseLength, 5.0, tailRecover);
    final upperPath = _buildDripPath(
      anchorX: anchorX,
      baseY: anchorY,
      shoulder: _lerp(fullShoulder, spec.shoulder * 0.32, tailRecover),
      neck: _lerp(
        _lerp(spec.neck * 0.20, spec.neck * 0.14, detachPhase),
        spec.neck * 0.08,
        tailRecover,
      ),
      length: upperLength,
      tipRadius: _lerp(
        _lerp(spec.tipRadius * 0.34, spec.tipRadius * 0.18, detachPhase),
        spec.tipRadius * 0.08,
        tailRecover,
      ),
    );
    canvas.drawPath(upperPath.shift(const Offset(0, 1.1)), shadowPaint);
    canvas.drawPath(
      upperPath,
      _gradientLiquidPaint(
        upperPath.getBounds(),
        bottomY: anchorY + upperLength,
        orbCenter: orbCenter,
        orbRadius: orbRadius,
      ),
    );

    final dropForm = _easeOutCubic(_normalize(releasedSplit, 0.0, 0.20));
    final dropRadius = _lerp(
      releaseTipRadius * 0.96,
      spec.tipRadius * 1.10,
      dropForm,
    );
    final separationY = anchorY + releaseLength;
    final dropFall = _lerp(releasedSplit, _easeInQuart(releasedSplit), 0.72);
    final dropY = _lerp(separationY + dropRadius * 0.06, impactY, dropFall);
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
    final emerge = _normalize(phase, 0.06, 0.58);
    final fall = _normalize(phase, 0.58, 1.0);
    final impactY =
        (_orbTopAtX(orbCenter, orbRadius, anchorX) ??
            (orbCenter.dy - orbRadius)) +
        spec.tipRadius * 0.12;
    final radius =
        spec.tipRadius *
        (spec.tipRadius >= 5.5
            ? 1.12
            : spec.tipRadius >= 4.9
            ? 1.06
            : 1.02);
    final hiddenCenterY = anchorY - radius * 1.02;
    final exposedCenterY = anchorY + radius * 1.02;
    final emergeY = _lerp(
      hiddenCenterY,
      exposedCenterY,
      _easeInOutCubic(emerge),
    );

    if (phase < 0.36) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          anchorX - radius * 2.2,
          anchorY,
          anchorX + radius * 2.2,
          anchorY + radius * 2.4,
        ),
      );
      _drawDropCircle(
        canvas,
        x: anchorX,
        y: emergeY,
        radius: radius,
        orbCenter: orbCenter,
        orbRadius: orbRadius,
        shadowPaint: shadowPaint,
      );
      canvas.restore();
      return;
    }

    final dropY = _lerp(
      exposedCenterY + radius * 0.08,
      impactY,
      _easeInQuart(fall),
    );
    _drawOrbAwareDrop(
      canvas,
      x: anchorX,
      y: dropY,
      radius: radius,
      orbCenter: orbCenter,
      orbRadius: orbRadius,
      shadowPaint: shadowPaint,
    );
  }

  void _drawOrbBack(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Paint shadowPaint,
  }) {
    final motionOffset = _orbMotionOffset(radius);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx + motionOffset.dx * 1.05,
          center.dy + radius + 18 + motionOffset.dy * 0.72,
        ),
        width: radius * 1.86,
        height: radius * 0.42,
      ),
      Paint()
        ..color = const Color(0x18000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx + motionOffset.dx * 0.92,
          center.dy + radius + 12 + motionOffset.dy * 0.64,
        ),
        width: radius * 1.5,
        height: radius * 0.34,
      ),
      Paint()
        ..color = const Color(0x24000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
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

    _drawOrbLiquid(canvas, center: center, radius: radius);
  }

  void _drawOrbLiquid(
    Canvas canvas, {
    required Offset center,
    required double radius,
  }) {
    final orbRect = Rect.fromCircle(center: center, radius: radius);
    final liquidTop = center.dy + radius * (1 - 2 * orbFill);
    final left = center.dx - radius;
    final right = center.dx + radius;
    final waveA = 4.5 + math.sin(t * math.pi * 2).abs() * 2.6;
    final waveB = 1.8 + math.cos(t * math.pi * 2.6).abs() * 1.4;
    final tiltHeight = liquidTilt * radius * 0.22;
    final sloshHeight = sloshing * radius * 0.10;
    final minSurfaceY = center.dy - radius * 0.92;
    final maxSurfaceY = center.dy + radius * 0.90;

    final liquidPath = Path()
      ..moveTo(left, center.dy + radius)
      ..lineTo(left, liquidTop);

    for (var x = left; x <= right; x += 4) {
      final progress = (x - left) / (right - left);
      final edgeFalloff = math.sin(progress * math.pi);
      final slope = ((progress - 0.5) * 2) * tiltHeight;
      final wave =
          math.sin((progress * 2.3 + t * 1.2) * math.pi * 2) *
              waveA *
              edgeFalloff +
          math.sin((progress * 4.8 - t * 1.8) * math.pi * 2) *
              waveB *
              edgeFalloff;
      final sloshWave =
          math.sin(
                (progress * 1.45 - t * 1.15 + sloshing * 0.35) * math.pi * 2,
              ) *
              sloshHeight *
              edgeFalloff +
          math.sin((progress * 2.8 + t * 0.82) * math.pi * 2) *
              sloshHeight *
              0.32 *
              edgeFalloff;
      final surfaceY = (liquidTop + slope + wave + sloshWave).clamp(
        minSurfaceY,
        maxSurfaceY,
      );
      liquidPath.lineTo(x, surfaceY);
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
    final motionOffset = _orbMotionOffset(radius);
    final orbRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _orbBlueTop.withAlpha(220),
    );

    canvas.drawCircle(
      center,
      radius - 1.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0x52FFFFFF),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx - radius * 0.26 + motionOffset.dx,
          center.dy - radius * 0.34 + motionOffset.dy,
        ),
        width: radius * 0.44,
        height: radius * 0.78,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[const Color(0x7FFFFFFF), const Color(0x18FFFFFF)],
        ).createShader(orbRect)
        ..style = PaintingStyle.fill,
    );

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(
          center.dx + radius * 0.04 + motionOffset.dx,
          center.dy + radius * 0.04 + motionOffset.dy,
        ),
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
    if (mergeTop == null || y < mergeTop - radius * 1.04) {
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

    final bridgeEnd = mergeTop + radius * 0.50;
    final absorbEnd = mergeTop + radius * 1.02;

    if (y < bridgeEnd) {
      final blend = _normalize(y, mergeTop - radius * 1.04, bridgeEnd);
      final contactY = _lerp(
        mergeTop - radius * 0.08,
        mergeTop + radius * 0.05,
        blend,
      );
      final shoulder = _lerp(radius * 0.92, radius * 0.34, blend);

      final orbCap = Path()
        ..moveTo(x - radius * 0.82, mergeTop + radius * 0.03)
        ..cubicTo(
          x - radius * 0.54,
          mergeTop - radius * 0.18 * (1 - blend),
          x - radius * 0.18,
          mergeTop - radius * 0.14 * (1 - blend),
          x,
          mergeTop - radius * 0.04 * (1 - blend),
        )
        ..cubicTo(
          x + radius * 0.18,
          mergeTop - radius * 0.14 * (1 - blend),
          x + radius * 0.54,
          mergeTop - radius * 0.18 * (1 - blend),
          x + radius * 0.82,
          mergeTop + radius * 0.03,
        )
        ..lineTo(x + radius * 0.62, mergeTop + radius * 0.28)
        ..quadraticBezierTo(
          x,
          mergeTop + radius * 0.14,
          x - radius * 0.62,
          mergeTop + radius * 0.28,
        )
        ..close();
      canvas.drawPath(orbCap, Paint()..color = _orbBlueTop.withAlpha(224));

      final mergePath = Path()
        ..moveTo(x - shoulder, y - radius * 0.08)
        ..cubicTo(
          x - radius * 1.02,
          y + radius * 0.66,
          x - radius * 0.86,
          contactY + radius * 0.24,
          x,
          contactY,
        )
        ..cubicTo(
          x + radius * 0.86,
          contactY + radius * 0.24,
          x + radius * 1.02,
          y + radius * 0.66,
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
        ..moveTo(x - radius * 0.64, mergeTop + radius * 0.04)
        ..quadraticBezierTo(
          x,
          mergeTop - radius * 0.22 * (1 - blend),
          x + radius * 0.64,
          mergeTop + radius * 0.04,
        )
        ..lineTo(x + radius * 0.50, mergeTop + radius * 0.24)
        ..quadraticBezierTo(
          x,
          mergeTop + radius * 0.08,
          x - radius * 0.50,
          mergeTop + radius * 0.24,
        )
        ..close();
      canvas.drawPath(seamPath, Paint()..color = _orbBlueTop.withAlpha(228));
      return;
    }

    if (y < absorbEnd) {
      final absorb = _normalize(y, bridgeEnd, absorbEnd);
      final capWidth = _lerp(radius * 1.02, radius * 0.30, absorb);
      final capHeight = _lerp(radius * 0.34, radius * 0.08, absorb);
      final capY = _lerp(
        mergeTop + radius * 0.10,
        mergeTop + radius * 0.18,
        absorb,
      );
      final absorbPath = Path()
        ..moveTo(x - capWidth, capY)
        ..quadraticBezierTo(x, capY - capHeight, x + capWidth, capY)
        ..quadraticBezierTo(x, capY + capHeight * 0.7, x - capWidth, capY)
        ..close();
      canvas.drawPath(absorbPath, Paint()..color = _orbBlueTop.withAlpha(224));
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
      _clamp01((bottomY - 42) / ((orbCenter.dy - orbRadius * 0.08) - 42)),
    );
    final targetBlue = Color.lerp(_orbBlueTop, _orbBlueBottom, 0.34)!;
    final lowerColor = Color.lerp(color, targetBlue, blend)!;
    final midColor = Color.lerp(color, lowerColor, 0.86)!;
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[color, midColor, lowerColor],
      ).createShader(bounds)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
  }

  Offset _orbMotionOffset(double radius) {
    final horizontal = (liquidTilt * 0.62 + sloshing * 0.88) * radius * 0.14;
    final vertical =
        (liquidTilt.abs() * 0.22 + sloshing.abs() * 0.36) * radius * 0.055;
    return Offset(horizontal, vertical);
  }

  static double _phaseFor(double t, _DripSpec spec) {
    final speed = math.min(spec.speed, 1.0);
    return (t * speed + spec.phaseOffset) % 1.0;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();

  static double _easeInQuart(double x) => x * x * x * x;

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
        oldDelegate.previousStretchIndex != previousStretchIndex ||
        oldDelegate.orbFill != orbFill ||
        oldDelegate.liquidTilt != liquidTilt ||
        oldDelegate.sloshing != sloshing ||
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
