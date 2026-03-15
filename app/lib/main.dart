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
  static const List<String> _defaultTitles = <String>[
    '\u6dfb\u52a0\u63d0\u9192',
    '\u8be5\u559d\u6c34\u5566',
    '\u8d77\u6765\u52a8\u4e00\u52a8',
    '\u4f11\u606f\u65f6\u95f4\u5230',
  ];

  static const List<ReplicaCardData> _cards = <ReplicaCardData>[
    ReplicaCardData(
      index: 1,
      title: 'mobile',
      color: Color(0xFFFF0008),
      slotColor: Color(0xFF8D0000),
      angle: 0.0,
      left: 0.270,
      top: 0,
      width: 0.700,
      height: 0.100,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.080,
      titleDx: 0.0,
      titleDy: -1.0,
    ),
    ReplicaCardData(
      index: 2,
      title: 'auxiliary',
      color: Color(0xFFEF7A00),
      slotColor: Color(0xFF7A3500),
      angle: -0.194,
      left: 0.215,
      top: 108,
      width: 0.705,
      height: 0.100,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.080,
      titleDx: -3.0,
      titleDy: 1.0,
    ),
    ReplicaCardData(
      index: 3,
      title: 'cross-\nplatform',
      color: Color(0xFFE8EE00),
      slotColor: Color(0xFF6A6700),
      angle: -0.535,
      left: 0.105,
      top: 224,
      width: 0.705,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.024,
      slotInsetVertical: 0.082,
      titleDx: -10.0,
      titleDy: -1.0,
      titleLines: 2,
    ),
    ReplicaCardData(
      index: 4,
      title: 'back-end',
      color: Color(0xFF68F40D),
      slotColor: Color(0xFF2A6500),
      angle: -0.402,
      left: -0.010,
      top: 386,
      width: 0.705,
      height: 0.103,
      slotWidthFactor: 0.300,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -1.0,
      titleDy: -1.0,
    ),
    ReplicaCardData(
      index: 5,
      title: 'online',
      color: Color(0xFF18FF00),
      slotColor: Color(0xFF006B00),
      angle: -0.126,
      left: 0.315,
      top: 538,
      width: 0.690,
      height: 0.101,
      slotWidthFactor: 0.297,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: 0.0,
      titleDy: 0.0,
    ),
    ReplicaCardData(
      index: 6,
      title: 'primary',
      color: Color(0xFF18ED7D),
      slotColor: Color(0xFF006D45),
      angle: -0.118,
      left: 0.315,
      top: 690,
      width: 0.690,
      height: 0.101,
      slotWidthFactor: 0.297,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: 1.0,
      titleDy: 0.0,
    ),
    ReplicaCardData(
      index: 7,
      title: 'cross-\nplatform',
      color: Color(0xFF24DDE5),
      slotColor: Color(0xFF006D74),
      angle: -0.290,
      left: 0.260,
      top: 845,
      width: 0.700,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -5.0,
      titleDy: -1.0,
      titleLines: 2,
    ),
    ReplicaCardData(
      index: 8,
      title: 'cross-\nplatform',
      color: Color(0xFF1F7BF4),
      slotColor: Color(0xFF003A86),
      angle: -0.353,
      left: 0.035,
      top: 997,
      width: 0.700,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -8.0,
      titleDy: 2.0,
      titleLines: 2,
    ),
    ReplicaCardData(
      index: 9,
      title: 'redundant',
      color: Color(0xFF1713FF),
      slotColor: Color(0xFF010076),
      angle: -0.452,
      left: 0.090,
      top: 1158,
      width: 0.705,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -1.0,
      titleDy: 3.0,
    ),
    ReplicaCardData(
      index: 10,
      title: 'design',
      color: Color(0xFFA62CF8),
      slotColor: Color(0xFF46007A),
      angle: -0.435,
      left: -0.020,
      top: 1318,
      width: 0.705,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -1.0,
      titleDy: 3.0,
    ),
    ReplicaCardData(
      index: 11,
      title: 'system',
      color: Color(0xFFD92DFF),
      slotColor: Color(0xFF5E006E),
      angle: -0.350,
      left: 0.020,
      top: 1482,
      width: 0.705,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -1.0,
      titleDy: 2.0,
    ),
    ReplicaCardData(
      index: 12,
      title: 'network',
      color: Color(0xFFFF3D8E),
      slotColor: Color(0xFF7A0A3D),
      angle: -0.260,
      left: 0.070,
      top: 1640,
      width: 0.705,
      height: 0.103,
      slotWidthFactor: 0.305,
      slotInsetRight: 0.022,
      slotInsetVertical: 0.082,
      titleDx: -1.0,
      titleDy: 2.0,
    ),
  ];
  static const double _stepExtent = 150.0;

  final ScrollController _scrollController = ScrollController();
  bool _isSnapping = false;
  double _lastDragDelta = 0.0;
  static const double _dragResponse = 1.18;
  late final List<String?> _customReminderTitles;
  late final List<String?> _customReminderEmojis;
  late final List<String?> _customReminderDescriptions;

  @override
  void initState() {
    super.initState();
    _customReminderTitles = List<String?>.filled(_cards.length, null);
    _customReminderEmojis = List<String?>.filled(_cards.length, null);
    _customReminderDescriptions = List<String?>.filled(_cards.length, null);
  }

  void _snapToNearestSlot([double velocity = 0.0]) {
    if (!_scrollController.hasClients || _isSnapping) {
      return;
    }

    final position = _scrollController.position;
    final current = position.pixels;
    final rawIndex = current / _stepExtent;
    final floorIndex = rawIndex.floor();
    final fraction = rawIndex - floorIndex;
    final inferredDirection = velocity.abs() > 30
        ? (velocity < 0 ? 1 : -1)
        : (_lastDragDelta < 0 ? 1 : (_lastDragDelta > 0 ? -1 : 0));
    int nearestIndex;
    if (inferredDirection > 0) {
      nearestIndex = fraction >= 0.18 ? floorIndex + 1 : floorIndex;
    } else if (inferredDirection < 0) {
      nearestIndex = fraction <= 0.82 ? floorIndex : floorIndex + 1;
    } else {
      nearestIndex = rawIndex.round();
    }
    nearestIndex = nearestIndex.clamp(0, _cards.length - 1);

    final initialTarget = (nearestIndex * _stepExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((initialTarget - current).abs() < 1.0) {
      return;
    }

    _isSnapping = true;
    final distance = initialTarget - current;
    final directionSign = inferredDirection == 0
        ? (distance >= 0 ? 1.0 : -1.0)
        : inferredDirection.toDouble();
    final inertiaDistance =
        _stepExtent * (velocity.abs() > 260 ? 4.8 : 3.9) * directionSign;
    final coastTarget = (current + inertiaDistance + distance * 0.35).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final finalIndex = (coastTarget / _stepExtent).round().clamp(
      0,
      _cards.length - 1,
    );
    final target = (finalIndex * _stepExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final finalDistance = target - coastTarget;
    final snapOvershoot = (finalDistance * 0.08).clamp(-10.0, 10.0);
    final snapTarget = (target + snapOvershoot).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    Future<void> settle() async {
      if ((coastTarget - current).abs() > 4) {
        await _scrollController.animateTo(
          coastTarget,
          duration: Duration(milliseconds: velocity.abs() > 260 ? 1260 : 1020),
          curve: Curves.easeOutQuart,
        );
      }
      await _scrollController.animateTo(
        snapTarget,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }

    settle().whenComplete(() {
      _isSnapping = false;
    });
  }

  void _maybeSnap(ScrollEndNotification notification) {
    final velocity = notification.dragDetails?.primaryVelocity ?? 0.0;
    _snapToNearestSlot(velocity);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int get _firstEmptyReminderIndex {
    for (var i = 0; i < _customReminderTitles.length; i++) {
      if (_customReminderTitles[i] == null) {
        return i;
      }
    }
    return -1;
  }

  // ignore: unused_element
  Future<void> _showAddReminderDialog() async {
    final firstEmptyIndex = _firstEmptyReminderIndex;
    if (firstEmptyIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u4e8b\u9879\u5361\u7247\u5df2\u7ecf\u5168\u90e8\u6dfb\u52a0\u5b8c\u6210',
          ),
        ),
      );
      return;
    }
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('\u65b0\u589e\u63d0\u9192'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 16,
            decoration: const InputDecoration(
              hintText: '\u8f93\u5165\u63d0\u9192\u5185\u5bb9',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('\u53d6\u6d88'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('\u786e\u5b9a'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || title == null || title.isEmpty) {
      return;
    }
    setState(() {
      _customReminderTitles[firstEmptyIndex] = title;
    });
  }

  // ignore: unused_element
  String _titleForCard(int index) {
    if (index < _defaultTitles.length) {
      return _defaultTitles[index];
    }
    final custom = _customReminderTitles[index];
    if (custom != null) {
      return custom;
    }
    if (index == _firstEmptyReminderIndex) {
      return '\u6dfb\u52a0\u4e8b\u9879';
    }
    return '';
  }

  // ignore: unused_element
  bool _isPlaceholderCard(int index) =>
      index >= 4 && _customReminderTitles[index] == null;

  // ignore: unused_element
  bool _isActiveSaturation(int index) =>
      index < 4 || _customReminderTitles[index] != null;

  Future<void> _openReminderDialogForCard(int tappedIndex) async {
    final isEditing = _customReminderTitles[tappedIndex] != null;
    final targetIndex = isEditing ? tappedIndex : _firstEmptyReminderIndex;
    if (targetIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u4e8b\u9879\u5361\u7247\u5df2\u7ecf\u5168\u90e8\u6dfb\u52a0\u5b8c\u6210',
          ),
        ),
      );
      return;
    }
    final titleController = TextEditingController(
      text: _customReminderTitles[targetIndex] ?? '',
    );
    final emojiController = TextEditingController(
      text: _customReminderEmojis[targetIndex] ?? '',
    );
    final descriptionController = TextEditingController(
      text: _customReminderDescriptions[targetIndex] ?? '',
    );
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isEditing ? '\u7f16\u8f91\u4e8b\u9879' : '\u65b0\u589e\u4e8b\u9879',
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  autofocus: true,
                  maxLength: 16,
                  decoration: const InputDecoration(
                    labelText: '\u4e8b\u9879\u6807\u9898',
                    hintText: '\u4f8b\u5982\uff1a\u559d\u4e00\u676f\u6c34',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emojiController,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Emoji \u8868\u60c5',
                    hintText: '\u4f8b\u5982\uff1a\u{1F4A7}',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '\u4e8b\u9879\u63cf\u8ff0',
                    hintText: '\u8865\u5145\u63d0\u9192\u8be6\u60c5',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('\u53d6\u6d88'),
            ),
            FilledButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('\u4fdd\u5b58'),
            ),
          ],
        );
      },
    );
    titleController.dispose();
    emojiController.dispose();
    descriptionController.dispose();
    if (!mounted || shouldSave != true) {
      return;
    }
    setState(() {
      _customReminderTitles[targetIndex] = titleController.text.trim();
      _customReminderEmojis[targetIndex] = emojiController.text.trim();
      _customReminderDescriptions[targetIndex] = descriptionController.text
          .trim();
    });
  }

  String _displayTitleFor(int index) {
    final custom = _customReminderTitles[index];
    if (custom != null) {
      return custom;
    }
    if (index < _defaultTitles.length) {
      return _defaultTitles[index];
    }
    if (index == _firstEmptyReminderIndex) {
      return '\u6dfb\u52a0\u4e8b\u9879';
    }
    return '';
  }

  String _displayEmojiFor(int index) => _customReminderEmojis[index] ?? '';

  bool _displayPlaceholderFor(int index) =>
      _customReminderTitles[index] == null;

  bool _displaySaturationFor(int index) =>
      index < 4 || _customReminderTitles[index] != null;

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
                            final settledActiveIndex =
                                (offset / _stepExtent) - 3;
                            final progress = (offset / maxExtent).clamp(
                              0.0,
                              1.0,
                            );
                            final fractionalIndex = settledActiveIndex;

                            return Stack(
                              children: <Widget>[
                                Positioned(
                                  left: media.width * 0.050,
                                  top: media.height * 0.30,
                                  child: LeftSegmentIndicator(
                                    progress: progress,
                                    count: _cards.length,
                                  ),
                                ),
                                SingleChildScrollView(
                                  controller: _scrollController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: SizedBox(
                                    // Add enough trailing extent so card 12 can
                                    // still reach the center slot before stop.
                                    height:
                                        media.height +
                                        (_cards.length - 1) * _stepExtent +
                                        1,
                                  ),
                                ),
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onVerticalDragUpdate: (details) {
                                      if (!_scrollController.hasClients) {
                                        return;
                                      }
                                      _lastDragDelta = details.delta.dy;
                                      final next =
                                          (_scrollController.offset -
                                                  details.delta.dy *
                                                      _dragResponse)
                                              .clamp(
                                                0.0,
                                                _scrollController
                                                    .position
                                                    .maxScrollExtent,
                                              );
                                      _scrollController.jumpTo(next);
                                    },
                                    onVerticalDragEnd: (details) {
                                      _snapToNearestSlot(
                                        details.primaryVelocity ?? 0.0,
                                      );
                                    },
                                    onVerticalDragCancel: () {
                                      _snapToNearestSlot();
                                    },
                                    child: Stack(
                                      children: <Widget>[
                                        for (var i = 0; i < _cards.length; i++)
                                          FanReplicaCard(
                                            item: _cards[i],
                                            itemIndex: i,
                                            activeIndex: fractionalIndex,
                                            panelProgress: widget.progress,
                                            screenSize: media,
                                            displayTitle: _displayTitleFor(i),
                                            displayEmoji: _displayEmojiFor(i),
                                            isPlaceholder:
                                                _displayPlaceholderFor(i),
                                            showGlassPlus:
                                                _customReminderTitles[i] ==
                                                null,
                                            useFullSaturation:
                                                _displaySaturationFor(i),
                                            onTap: () {
                                              _openReminderDialogForCard(i);
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
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
    required this.angle,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.slotWidthFactor,
    required this.slotInsetRight,
    required this.slotInsetVertical,
    required this.titleDx,
    required this.titleDy,
    this.titleLines = 1,
  });

  final int index;
  final String title;
  final Color color;
  final Color slotColor;
  final double angle;
  final double left;
  final double top;
  final double width;
  final double height;
  final double slotWidthFactor;
  final double slotInsetRight;
  final double slotInsetVertical;
  final double titleDx;
  final double titleDy;
  final int titleLines;
}

class ReplicaTrackSlot {
  const ReplicaTrackSlot({
    required this.left,
    required this.top,
    required this.angle,
    this.scale = 1,
    this.opacity = 1,
  });

  final double left;
  final double top;
  final double angle;
  final double scale;
  final double opacity;
}

class PositionedReplicaCard extends StatelessWidget {
  const PositionedReplicaCard({
    super.key,
    required this.item,
    required this.screenWidth,
    required this.designTopGap,
    required this.scrollOffset,
  });

  final ReplicaCardData item;
  final double screenWidth;
  final double designTopGap;
  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    final width = screenWidth * item.width;
    final height = screenWidth * item.height;
    final parallax = (scrollOffset * 0.015).clamp(-12.0, 12.0);
    final top = designTopGap + item.top - parallax;

    return Positioned(
      left: screenWidth * item.left,
      top: top,
      child: Transform.rotate(
        angle: item.angle,
        child: ReplicaCard(item: item, width: width, height: height),
      ),
    );
  }
}

class FanReplicaCard extends StatelessWidget {
  static const List<ReplicaTrackSlot> _track = <ReplicaTrackSlot>[
    ReplicaTrackSlot(left: 0.16, top: 0.01, angle: -0.56, scale: 0.94),
    ReplicaTrackSlot(left: 0.26, top: 0.13, angle: -0.37, scale: 0.98),
    ReplicaTrackSlot(left: 0.33, top: 0.25, angle: -0.19, scale: 0.99),
    ReplicaTrackSlot(left: 0.34, top: 0.39, angle: 0.00, scale: 1.00),
    ReplicaTrackSlot(left: 0.28, top: 0.51, angle: 0.19, scale: 0.99),
    ReplicaTrackSlot(left: 0.20, top: 0.63, angle: 0.37, scale: 0.98),
    ReplicaTrackSlot(left: 0.10, top: 0.76, angle: 0.56, scale: 0.96),
  ];

  const FanReplicaCard({
    super.key,
    required this.item,
    required this.itemIndex,
    required this.activeIndex,
    required this.panelProgress,
    required this.screenSize,
    required this.displayTitle,
    required this.displayEmoji,
    required this.isPlaceholder,
    required this.showGlassPlus,
    required this.useFullSaturation,
    required this.onTap,
  });

  final ReplicaCardData item;
  final int itemIndex;
  final double activeIndex;
  final double panelProgress;
  final Size screenSize;
  final String displayTitle;
  final String displayEmoji;
  final bool isPlaceholder;
  final bool showGlassPlus;
  final bool useFullSaturation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final settledIndex = itemIndex - activeIndex;
    final entryShift = (1 - Curves.easeOutCubic.transform(panelProgress)) * 3.2;
    final trackIndex = settledIndex + entryShift;
    final lowerIndex = trackIndex.floor();
    final upperIndex = trackIndex.ceil();
    final t = (trackIndex - lowerIndex).clamp(0.0, 1.0);

    final lowerSlot = _slotFor(lowerIndex);
    final upperSlot = _slotFor(upperIndex);
    final width = screenSize.width * item.width * 0.84;
    final height = screenSize.width * item.height * 1.72;
    final left = _lerp(lowerSlot.left, upperSlot.left, t) * screenSize.width;
    final top = _lerp(lowerSlot.top, upperSlot.top, t) * screenSize.height;
    final angle = _lerp(lowerSlot.angle, upperSlot.angle, t);
    final scale = _lerp(lowerSlot.scale, upperSlot.scale, t);
    final opacity = _lerp(
      lowerSlot.opacity,
      upperSlot.opacity,
      t,
    ).clamp(0.0, 1.0);

    return Positioned(
      left: left,
      top: top,
      child: Transform.translate(
        offset: Offset(-width * 0.08, -height / 2),
        child: Transform.rotate(
          angle: angle,
          alignment: Alignment.centerLeft,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: IgnorePointer(
              ignoring: opacity <= 0,
              child: Opacity(
                opacity: opacity,
                child: ReplicaCard(
                  item: item,
                  width: width,
                  height: height,
                  displayTitle: displayTitle,
                  displayEmoji: displayEmoji,
                  isPlaceholder: isPlaceholder,
                  showGlassPlus: showGlassPlus,
                  useFullSaturation: useFullSaturation,
                  onTap: onTap,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static ReplicaTrackSlot _slotFor(int index) {
    if (index < 0) {
      final first = _track.first;
      final second = _track[1];
      final dx = first.left - second.left;
      final dy = first.top - second.top;
      final da = first.angle - second.angle;
      final distance = -index.toDouble();
      return ReplicaTrackSlot(
        left: first.left + dx * distance,
        top: first.top + dy * distance,
        angle: first.angle + da * distance,
        scale: first.scale,
        opacity: 1,
      );
    }
    if (index > _track.length - 1) {
      final last = _track.last;
      final previous = _track[_track.length - 2];
      final dx = last.left - previous.left;
      final dy = last.top - previous.top;
      final da = last.angle - previous.angle;
      final distance = index - (_track.length - 1).toDouble();
      return ReplicaTrackSlot(
        left: last.left + dx * distance,
        top: last.top + dy * distance,
        angle: last.angle + da * distance,
        scale: last.scale,
        opacity: 1,
      );
    }
    return _track[index];
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class ReplicaCard extends StatelessWidget {
  const ReplicaCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.displayTitle,
    this.displayEmoji = '',
    this.isPlaceholder = false,
    this.showGlassPlus = false,
    this.useFullSaturation = true,
    this.onTap,
    this.shadowBlur = 8,
    this.shadowSpread = 2,
    this.isFocused = false,
  });

  final ReplicaCardData item;
  final double width;
  final double height;
  final String? displayTitle;
  final String displayEmoji;
  final bool isPlaceholder;
  final bool showGlassPlus;
  final bool useFullSaturation;
  final VoidCallback? onTap;
  final double shadowBlur;
  final double shadowSpread;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = displayTitle ?? item.title;
    final baseColor = _displayColor(item.color, useFullSaturation);
    final showEmoji = displayEmoji.trim().isNotEmpty && !isPlaceholder;
    final trailingColor = isPlaceholder
        ? Colors.grey.withValues(alpha: 0.16)
        : (showEmoji
              ? Colors.transparent
              : _displayColor(item.slotColor, useFullSaturation));
    final radius = height * 0.23;
    final slotInsetRight = width * item.slotInsetRight;
    final slotInsetVertical = height * item.slotInsetVertical;
    final slotWidth = width * item.slotWidthFactor;
    final leftPadding = width * 0.045;
    final bigNumberWidth = width * 0.145;
    final titleFont = height * 0.255;
    final numberFont = height * 0.46;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.58),
                        blurRadius: 5,
                        spreadRadius: 2,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: slotInsetRight,
                top: slotInsetVertical,
                bottom: slotInsetVertical,
                child: SizedBox(
                  width: slotWidth,
                  child: showEmoji
                      ? Center(
                          child: Text(
                            displayEmoji,
                            style: TextStyle(fontSize: height * 0.44),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: trailingColor,
                            borderRadius: BorderRadius.circular(height * 0.20),
                            border: isPlaceholder
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: 0.34),
                                    width: 1.0,
                                  )
                                : null,
                            gradient: isPlaceholder
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: <Color>[
                                      Colors.white.withValues(alpha: 0.28),
                                      Colors.white.withValues(alpha: 0.08),
                                    ],
                                  )
                                : null,
                          ),
                          child: showGlassPlus
                              ? Center(
                                  child: _GlassPlusIcon(
                                    size: height * 0.28,
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                                )
                              : null,
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
                            color: const Color(0xFF111111),
                            letterSpacing: -2.8,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: width * 0.025),
                    Expanded(
                      child: Transform.translate(
                        offset: Offset(item.titleDx, item.titleDy),
                        child: Text(
                          resolvedTitle,
                          maxLines: item.titleLines,
                          style: TextStyle(
                            fontSize: titleFont,
                            height: item.titleLines > 1 ? 0.92 : 0.88,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF161616),
                            letterSpacing: -1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _displayColor(Color color, bool useFullSaturation) {
    if (useFullSaturation) {
      return color;
    }
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation((hsl.saturation * 0.18).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.06).clamp(0.0, 1.0))
        .toColor();
  }
}

class _GlassPlusIcon extends StatelessWidget {
  const _GlassPlusIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final thickness = size * 0.18;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: thickness,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(thickness / 2),
            ),
          ),
          Container(
            width: size,
            height: thickness,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(thickness / 2),
            ),
          ),
        ],
      ),
    );
  }
}

class LeftSegmentIndicator extends StatelessWidget {
  const LeftSegmentIndicator({
    super.key,
    required this.progress,
    required this.count,
  });

  final double progress;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 120,
      child: CustomPaint(painter: LeftSegmentIndicatorPainter(progress, count)),
    );
  }
}

class LeftSegmentIndicatorPainter extends CustomPainter {
  LeftSegmentIndicatorPainter(this.progress, this.count);

  final double progress;
  final int count;

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

    const startX = 1.5;
    const endX = 21.5;
    final gap = count > 1 ? (size.height - 18) / (count - 1) : 0.0;
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
    return oldDelegate.progress != progress || oldDelegate.count != count;
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
