import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      title: '12:05',
      debugShowCheckedModeBanner: false,
      home: DynamicIslandDripPage(),
    );
  }
}

enum _EdgeDragMode { none, leftPanel, rightPanel, bottomSheet }

enum _ReminderAlertMode { systemAlarm, vibrationOnly }

class _ReminderTaskConfig {
  const _ReminderTaskConfig({
    required this.index,
    required this.title,
    required this.emoji,
    required this.description,
    required this.time,
    required this.alertMode,
  });

  final int index;
  final String title;
  final String emoji;
  final String description;
  final TimeOfDay time;
  final _ReminderAlertMode alertMode;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'index': index,
      'title': title,
      'emoji': emoji,
      'description': description,
      'hour': time.hour,
      'minute': time.minute,
      'alertMode': alertMode.name,
    };
  }

  static _ReminderTaskConfig? fromJson(Map<String, dynamic> json) {
    final index = json['index'];
    final title = json['title'];
    final emoji = json['emoji'];
    final description = json['description'];
    final hour = json['hour'];
    final minute = json['minute'];
    final alertModeName = json['alertMode'];
    if (index is! int ||
        title is! String ||
        emoji is! String ||
        description is! String ||
        hour is! int ||
        minute is! int ||
        alertModeName is! String) {
      return null;
    }
    _ReminderAlertMode? mode;
    for (final value in _ReminderAlertMode.values) {
      if (value.name == alertModeName) {
        mode = value;
        break;
      }
    }
    if (mode == null) {
      return null;
    }
    return _ReminderTaskConfig(
      index: index,
      title: title,
      emoji: emoji,
      description: description,
      time: TimeOfDay(hour: hour, minute: minute),
      alertMode: mode,
    );
  }
}

class _CloudStats {
  const _CloudStats({
    this.userMl = 0,
    this.totalMl = 0,
    this.dailyMlByDate = const <String, double>{},
  });

  final double userMl;
  final double totalMl;
  final Map<String, double> dailyMlByDate;
}

abstract class _CloudStatsRepository {
  Future<_CloudStats> fetchStats();

  Future<_CloudStats> uploadContribution(double ml);
}

class _LocalCloudStatsRepository implements _CloudStatsRepository {
  static const String _userMlKey = 'cloud_stats_user_ml';
  static const String _totalMlKey = 'cloud_stats_total_ml';
  static const String _dailyMlByDateKey = 'cloud_stats_daily_ml_by_date';

  double _userMl = 0;
  double _totalMl = 0;
  Map<String, double> _dailyMlByDate = <String, double>{};
  SharedPreferences? _prefs;

  Future<SharedPreferences> _preferences() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Map<String, double> _decodeDailyMl(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <String, double>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <String, double>{};
    }
    return decoded.map<String, double>((String key, dynamic value) {
      final number = value;
      if (number is num) {
        return MapEntry<String, double>(key, number.toDouble());
      }
      return const MapEntry<String, double>('', 0);
    })..remove('');
  }

  @override
  Future<_CloudStats> fetchStats() async {
    final prefs = await _preferences();
    _userMl = prefs.getDouble(_userMlKey) ?? _userMl;
    _totalMl = prefs.getDouble(_totalMlKey) ?? _totalMl;
    _dailyMlByDate = _decodeDailyMl(prefs.getString(_dailyMlByDateKey));
    return _CloudStats(
      userMl: _userMl,
      totalMl: _totalMl,
      dailyMlByDate: Map<String, double>.unmodifiable(_dailyMlByDate),
    );
  }

  @override
  Future<_CloudStats> uploadContribution(double ml) async {
    final prefs = await _preferences();
    _userMl = prefs.getDouble(_userMlKey) ?? _userMl;
    _totalMl = prefs.getDouble(_totalMlKey) ?? _totalMl;
    _dailyMlByDate = _decodeDailyMl(prefs.getString(_dailyMlByDateKey));
    _userMl += ml;
    _totalMl += ml;
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _dailyMlByDate[dateKey] = (_dailyMlByDate[dateKey] ?? 0) + ml;
    await prefs.setDouble(_userMlKey, _userMl);
    await prefs.setDouble(_totalMlKey, _totalMl);
    await prefs.setString(_dailyMlByDateKey, jsonEncode(_dailyMlByDate));
    return _CloudStats(
      userMl: _userMl,
      totalMl: _totalMl,
      dailyMlByDate: Map<String, double>.unmodifiable(_dailyMlByDate),
    );
  }
}

class _InAppReminderScheduler {
  _InAppReminderScheduler({required this.onTrigger});

  final Future<void> Function(_ReminderTaskConfig task) onTrigger;
  final Map<int, Timer> _timers = <int, Timer>{};
  final Map<int, _ReminderTaskConfig> _tasks = <int, _ReminderTaskConfig>{};

  void updateTasks(List<_ReminderTaskConfig> tasks) {
    final nextTasks = <int, _ReminderTaskConfig>{
      for (final task in tasks) task.index: task,
    };
    final removedIds = _tasks.keys
        .where((id) => !nextTasks.containsKey(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _timers.remove(id)?.cancel();
      _tasks.remove(id);
    }
    for (final task in tasks) {
      final previous = _tasks[task.index];
      _tasks[task.index] = task;
      if (previous == null ||
          previous.time != task.time ||
          previous.alertMode != task.alertMode ||
          previous.title != task.title ||
          previous.description != task.description) {
        _scheduleTask(task);
      }
    }
  }

  void _scheduleTask(_ReminderTaskConfig task) {
    _timers.remove(task.index)?.cancel();
    final now = DateTime.now();
    var nextTime = DateTime(
      now.year,
      now.month,
      now.day,
      task.time.hour,
      task.time.minute,
    );
    if (!nextTime.isAfter(now.add(const Duration(seconds: 1)))) {
      nextTime = nextTime.add(const Duration(days: 1));
    }
    _timers[task.index] = Timer(nextTime.difference(now), () async {
      await onTrigger(task);
      if (_tasks.containsKey(task.index)) {
        _scheduleTask(_tasks[task.index]!);
      }
    });
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _tasks.clear();
  }
}

class DynamicIslandDripPage extends StatefulWidget {
  const DynamicIslandDripPage({super.key});

  @override
  State<DynamicIslandDripPage> createState() => _DynamicIslandDripPageState();
}

class _DynamicIslandDripPageState extends State<DynamicIslandDripPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _defaultOrbFillBaseline = 0.015;
  static const double _panelRevealDistance = 84;
  static const double _rightPanelRevealDistance = 88;
  static const double _bottomSheetRevealDistance = 168;
  static const String _orbStoredMlKey = 'orb_stored_ml';
  static const MethodChannel _alarmKitChannel = MethodChannel(
    'jinshi/alarmkit',
  );
  late final AnimationController _controller;
  late final AnimationController _panelController;
  late final AnimationController _oceanPanelController;
  late final AnimationController _calendarSheetController;
  late final List<double> _lastPhases;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSub;
  _EdgeDragMode _activeDragMode = _EdgeDragMode.none;
  double _panelDragStartX = 0;
  double _panelDragStartValue = 0;
  double _oceanDragStartX = 0;
  double _oceanDragStartValue = 0;
  double _calendarDragStartY = 0;
  double _calendarDragStartValue = 0;
  bool _gestureArmedFromOrb = false;
  int _cycleIndex = 0;
  double _lastValue = 0;
  double _orbFill = _defaultOrbFillBaseline;
  Duration _lastElapsed = Duration.zero;
  double _targetTilt = 0;
  double _liquidTilt = 0;
  double _shadowTilt = 0;
  double _tiltVelocity = 0;
  double _shakeKick = 0;
  double _sloshing = 0;
  bool _debugOrbForceFull = false;
  double _orbStoredMl = 0;
  double _uploadStartMl = 0;
  bool _uploadCommitted = false;
  bool _alarmDialogVisible = false;
  Timer? _alarmEffectTimer;
  late final AnimationController _uploadProgressController;
  late final AnimationController _uploadRevealController;
  late final _CloudStatsRepository _cloudStatsRepository;
  late final _InAppReminderScheduler _reminderScheduler;
  _CloudStats _cloudStats = const _CloudStats();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPhases = List<double>.filled(
      DynamicIslandDripPainter._drips.length,
      0,
    );
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _oceanPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _calendarSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _uploadProgressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _commitOrbUpload();
      }
    });
    _uploadRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && mounted) {
          setState(() {
            _uploadCommitted = false;
            _uploadStartMl = 0;
          });
        }
      });
    _cloudStatsRepository = _LocalCloudStatsRepository();
    _reminderScheduler = _InAppReminderScheduler(onTrigger: _handleReminderDue);
    _startMotionTracking();
    _loadCloudStats();
    _initializeOrbState();
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
                needsUpdate = true;
              }
              _lastPhases[i] = phase;
            }

            _updateLiquidMotion(dt);
            final targetOrbFill = _orbFillTarget;
            final easedFill = _lerpDouble(
              _orbFill,
              targetOrbFill,
              (1 - math.pow(0.92, dt * 60)).toDouble(),
            );
            if ((easedFill - _orbFill).abs() > 0.0008) {
              needsUpdate = true;
            }

            if (needsUpdate) {
              setState(() {
                _cycleIndex = nextCycleIndex;
                _orbFill = easedFill.clamp(0.0, 1.0);
              });
            }
            _lastValue = value;
          })
          ..repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelerometerSub?.cancel();
    _userAccelerometerSub?.cancel();
    _alarmEffectTimer?.cancel();
    _reminderScheduler.dispose();
    _uploadProgressController.dispose();
    _uploadRevealController.dispose();
    _panelController.dispose();
    _oceanPanelController.dispose();
    _calendarSheetController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumePendingNativeReward();
    }
  }

  double get _displayOrbMl {
    if (_uploadRevealController.value <= 0.01) {
      return _debugOrbForceFull ? 100 : _orbStoredMl;
    }
    if (_uploadCommitted) {
      return 0;
    }
    return (_uploadStartMl * (1 - _uploadProgressController.value)).clamp(
      0.0,
      _uploadStartMl,
    );
  }

  double get _orbFillTarget =>
      math.max(math.min(_displayOrbMl, 100) / 100, _defaultOrbFillBaseline);

  double get _userCollectedMl => _cloudStats.userMl;

  double get _totalOceanMl => _cloudStats.totalMl;

  double get _baikalEquivalent => _totalOceanMl / 23600000000000000.0;

  bool get _canUploadOrb => _displayOrbMl >= 50;

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
        onHorizontalDragCancel: () {
          _activeDragMode = _EdgeDragMode.none;
          _gestureArmedFromOrb = false;
        },
        onVerticalDragStart: _handleVerticalPanelDragStart,
        onVerticalDragUpdate: _handleVerticalPanelDragUpdate,
        onVerticalDragEnd: _handleVerticalPanelDragEnd,
        onVerticalDragCancel: () {
          _activeDragMode = _EdgeDragMode.none;
          _gestureArmedFromOrb = false;
        },
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _controller,
            _panelController,
            _oceanPanelController,
            _calendarSheetController,
            _uploadProgressController,
            _uploadRevealController,
          ]),
          builder: (context, _) {
            final leftPanelProgress = Curves.easeOutCubic.transform(
              _panelController.value,
            );
            final rightPanelProgress = Curves.easeOutCubic.transform(
              _oceanPanelController.value,
            );
            final calendarProgress = Curves.easeOutCubic.transform(
              _calendarSheetController.value,
            );
            final sceneCover = math.max(
              leftPanelProgress,
              math.max(rightPanelProgress, calendarProgress),
            );
            final sceneOffsetX =
                leftPanelProgress * 22 - rightPanelProgress * 22;
            final sceneOffsetY = -calendarProgress * 18;
            final sceneOpacity = 1 - sceneCover;
            final sceneScale = 1 - sceneCover * 0.035;
            final uploadOverlayActive =
                _uploadRevealController.value > 0.01 ||
                _uploadRevealController.isAnimating;
            final canStartOrbUpload =
                sceneCover <= 0.02 && _canUploadOrb && !uploadOverlayActive;
            final canFinishOrbUpload =
                sceneCover <= 0.02 && uploadOverlayActive;

            return LayoutBuilder(
              builder: (context, constraints) {
                final orbCenter = Offset(
                  constraints.maxWidth / 2,
                  constraints.maxHeight * 0.60,
                );
                final orbRadius = math.min(constraints.maxWidth * 0.235, 94.0);
                return Stack(
                  children: <Widget>[
                    _SlideOutReplicaPanel(
                      progress: leftPanelProgress,
                      onReminderTasksChanged: _handleReminderTasksChanged,
                    ),
                    _OceanStatsPanel(
                      progress: rightPanelProgress,
                      t: _controller.value,
                      appName: '12:05',
                      totalMl: _totalOceanMl,
                      userMl: _userCollectedMl,
                      baikalEquivalent: _baikalEquivalent,
                    ),
                    _CalendarBottomSheet(
                      progress: calendarProgress,
                      currentOrbMl: _displayOrbMl,
                      dailyMlByDate: _cloudStats.dailyMlByDate,
                      liquidTilt: _liquidTilt,
                      sloshing: _sloshing,
                    ),
                    IgnorePointer(
                      ignoring:
                          leftPanelProgress > 0.08 ||
                          rightPanelProgress > 0.08 ||
                          calendarProgress > 0.08,
                      child: Opacity(
                        opacity: sceneOpacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(sceneOffsetX, sceneOffsetY),
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
                                    shadowTilt: _shadowTilt,
                                    sloshing: _sloshing,
                                    color: Colors.black,
                                    orbMl: _displayOrbMl,
                                    uploadProgress:
                                        _uploadProgressController.value,
                                    uploadReveal:
                                        _uploadRevealController.value,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                                Positioned(
                                  left: orbCenter.dx - orbRadius * 1.24,
                                  top: orbCenter.dy - orbRadius * 1.24,
                                  width: orbRadius * 2.48,
                                  height: orbRadius * 2.48,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onLongPressStart:
                                        !canStartOrbUpload
                                        ? null
                                        : (_) => _handleOrbUploadStart(),
                                    onLongPressEnd:
                                        !canFinishOrbUpload
                                        ? null
                                        : (_) => _handleOrbUploadEnd(),
                                    onLongPressCancel:
                                        !canFinishOrbUpload
                                        ? null
                                        : _handleOrbUploadCancel,
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  top: safeTop + 18,
                                  child: _ProfileEntry(
                                    nickname: '\u7528\u6237\u6635\u79f0',
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
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 28,
                                  child: Center(
                                    child: _DebugOrbToggleButton(
                                      filled: _debugOrbForceFull,
                                      onPressed: _toggleDebugOrbFill,
                                    ),
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

    final quantizedShadowTarget = ((_targetTilt * 14).round() / 14)
        .clamp(-1.0, 1.0)
        .toDouble();
    final shadowTarget = quantizedShadowTarget.abs() < 0.09
        ? 0.0
        : quantizedShadowTarget;
    final shadowFollow = 1 - math.pow(0.965, dt * 60).toDouble();
    final nextShadowTilt = _lerpDouble(
      _shadowTilt,
      shadowTarget,
      shadowFollow,
    ).clamp(-1.0, 1.0);
    _shadowTilt = nextShadowTilt.abs() < 0.016 ? 0.0 : nextShadowTilt;

    final sloshDamping = math.pow(0.92, dt * 60).toDouble();
    _sloshing *= sloshDamping;
  }

  void _handlePanelDragStart(DragStartDetails details) {
    if (_calendarSheetController.value > 0.02) {
      _activeDragMode = _EdgeDragMode.none;
      _gestureArmedFromOrb = false;
      return;
    }
    final canResumeLeftPanel = _panelController.value > 0.02;
    final canResumeRightPanel = _oceanPanelController.value > 0.02;

    if (canResumeLeftPanel) {
      _activeDragMode = _EdgeDragMode.leftPanel;
      _gestureArmedFromOrb = false;
      _panelDragStartX = details.globalPosition.dx;
      _panelDragStartValue = _panelController.value;
      return;
    }
    if (canResumeRightPanel) {
      _activeDragMode = _EdgeDragMode.rightPanel;
      _gestureArmedFromOrb = false;
      _oceanDragStartX = details.globalPosition.dx;
      _oceanDragStartValue = _oceanPanelController.value;
      return;
    }
    _activeDragMode = _EdgeDragMode.none;
    _gestureArmedFromOrb = true;
    _panelDragStartX = details.globalPosition.dx;
    _panelDragStartValue = _panelController.value;
    _oceanDragStartX = details.globalPosition.dx;
    _oceanDragStartValue = _oceanPanelController.value;
  }

  void _handlePanelDragUpdate(DragUpdateDetails details) {
    if (_gestureArmedFromOrb && _activeDragMode == _EdgeDragMode.none) {
      final deltaX = details.globalPosition.dx - _panelDragStartX;
      if (deltaX.abs() >= 10) {
        _activeDragMode = deltaX > 0
            ? _EdgeDragMode.leftPanel
            : _EdgeDragMode.rightPanel;
        _gestureArmedFromOrb = false;
      }
    }
    if (_activeDragMode == _EdgeDragMode.leftPanel) {
      final deltaX = details.globalPosition.dx - _panelDragStartX;
      final nextValue = (_panelDragStartValue + deltaX / _panelRevealDistance)
          .clamp(0.0, 1.0);
      _panelController.value = nextValue;
      return;
    }
    if (_activeDragMode == _EdgeDragMode.rightPanel) {
      final deltaX = _oceanDragStartX - details.globalPosition.dx;
      final nextValue =
          (_oceanDragStartValue + deltaX / _rightPanelRevealDistance).clamp(
            0.0,
            1.0,
          );
      _oceanPanelController.value = nextValue;
      return;
    }
  }

  void _handlePanelDragEnd(DragEndDetails details) {
    switch (_activeDragMode) {
      case _EdgeDragMode.leftPanel:
        final velocity = details.primaryVelocity ?? 0;
        final target = velocity > 220
            ? 1.0
            : velocity < -220
            ? 0.0
            : (_panelController.value >= 0.28 ? 1.0 : 0.0);

        _panelController.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
        break;
      case _EdgeDragMode.rightPanel:
        final velocity = details.primaryVelocity ?? 0;
        final target = velocity < -220
            ? 1.0
            : velocity > 220
            ? 0.0
            : (_oceanPanelController.value >= 0.28 ? 1.0 : 0.0);

        _oceanPanelController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        break;
      case _EdgeDragMode.none:
      case _EdgeDragMode.bottomSheet:
        break;
    }
    _activeDragMode = _EdgeDragMode.none;
    _gestureArmedFromOrb = false;
  }

  void _handleVerticalPanelDragStart(DragStartDetails details) {
    final canResumeCalendar = _calendarSheetController.value > 0.02;
    if (_panelController.value > 0.02 || _oceanPanelController.value > 0.02) {
      return;
    }
    _activeDragMode = _EdgeDragMode.bottomSheet;
    _gestureArmedFromOrb = false;
    _calendarDragStartY = details.globalPosition.dy;
    _calendarDragStartValue = canResumeCalendar
        ? _calendarSheetController.value
        : 0.0;
  }

  void _handleVerticalPanelDragUpdate(DragUpdateDetails details) {
    if (_activeDragMode != _EdgeDragMode.bottomSheet) {
      return;
    }
    final deltaY = _calendarDragStartY - details.globalPosition.dy;
    final nextValue =
        (_calendarDragStartValue + deltaY / _bottomSheetRevealDistance).clamp(
          0.0,
          1.0,
        );
    _calendarSheetController.value = nextValue;
  }

  void _handleVerticalPanelDragEnd(DragEndDetails details) {
    if (_activeDragMode != _EdgeDragMode.bottomSheet) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final target = velocity < -220
        ? 1.0
        : velocity > 220
        ? 0.0
        : (_calendarSheetController.value >= 0.28 ? 1.0 : 0.0);
    _calendarSheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    _activeDragMode = _EdgeDragMode.none;
    _gestureArmedFromOrb = false;
  }

  void _toggleDebugOrbFill() {
    setState(() {
      _debugOrbForceFull = !_debugOrbForceFull;
      _orbStoredMl = _debugOrbForceFull ? 100 : 0;
    });
    _saveOrbStoredMl();
  }

  Future<void> _loadOrbStoredMl() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMl = prefs.getDouble(_orbStoredMlKey) ?? 0;
    if (!mounted) {
      return;
    }
    setState(() {
      _orbStoredMl = storedMl;
    });
  }

  Future<void> _initializeOrbState() async {
    await _loadOrbStoredMl();
    await _consumePendingNativeReward();
  }

  Future<void> _saveOrbStoredMl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_orbStoredMlKey, _orbStoredMl);
  }

  Future<void> _consumePendingNativeReward() async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      final result = await _alarmKitChannel.invokeMethod<num?>(
        'consumePendingRewardMl',
      );
      final rewardMl = result?.toDouble() ?? 0;
      if (rewardMl <= 0 || !mounted) {
        return;
      }
      setState(() {
        _orbStoredMl += rewardMl;
        _debugOrbForceFull = false;
      });
      await _saveOrbStoredMl();
    } on PlatformException {
      // Ignore native bridge failures and keep app usable.
    }
  }

  Future<void> _loadCloudStats() async {
    final stats = await _cloudStatsRepository.fetchStats();
    if (!mounted) {
      return;
    }
    setState(() {
      _cloudStats = stats;
    });
  }

  void _handleReminderTasksChanged(List<_ReminderTaskConfig> tasks) {
    if (Platform.isIOS) {
      _syncAlarmKitTasks(tasks);
      return;
    }
    _reminderScheduler.updateTasks(tasks);
  }

  Future<void> _syncAlarmKitTasks(List<_ReminderTaskConfig> tasks) async {
    try {
      await _alarmKitChannel.invokeMethod<void>(
        'syncReminderAlarms',
        <String, dynamic>{
          'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
        },
      );
    } on PlatformException {
      _reminderScheduler.updateTasks(tasks);
    }
  }

  void _handleOrbUploadStart() {
    if (!_canUploadOrb ||
        _uploadRevealController.isAnimating ||
        _uploadRevealController.value > 0.01) {
      return;
    }
    _uploadStartMl = _debugOrbForceFull ? 100 : _orbStoredMl;
    _uploadCommitted = false;
    _uploadProgressController.stop();
    _uploadProgressController.value = 0;
    _uploadRevealController.forward(from: 0);
    _uploadProgressController.forward(from: 0);
  }

  void _handleOrbUploadEnd() {
    if (_uploadRevealController.value <= 0.0 &&
        !_uploadRevealController.isAnimating) {
      return;
    }
    if (!_uploadCommitted) {
      _uploadProgressController.stop();
      _uploadProgressController.value = 0;
    }
    _uploadRevealController.reverse(from: _uploadRevealController.value);
  }

  void _handleOrbUploadCancel() {
    _handleOrbUploadEnd();
  }

  Future<void> _commitOrbUpload() async {
    if (_uploadCommitted) {
      return;
    }
    _uploadCommitted = true;
    final uploadedMl = _uploadStartMl;
    setState(() {
      _debugOrbForceFull = false;
      _orbStoredMl = 0;
    });
    await _saveOrbStoredMl();
    final stats = await _cloudStatsRepository.uploadContribution(uploadedMl);
    if (!mounted) {
      return;
    }
    setState(() {
      _cloudStats = stats;
    });
  }

  Future<void> _handleReminderDue(_ReminderTaskConfig task) async {
    if (!mounted || _alarmDialogVisible) {
      return;
    }
    _alarmDialogVisible = true;
    _startAlarmFeedback(task.alertMode);
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(task.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('提醒时间：${task.time.format(context)}'),
              if (task.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(task.description),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('未完成'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('已完成'),
            ),
          ],
        );
      },
    );
    _stopAlarmFeedback();
    _alarmDialogVisible = false;
    if (completed == true && mounted) {
      setState(() {
        _orbStoredMl += 10;
        _debugOrbForceFull = false;
      });
      await _saveOrbStoredMl();
    }
  }

  void _startAlarmFeedback(_ReminderAlertMode mode) {
    _stopAlarmFeedback();
    if (mode == _ReminderAlertMode.systemAlarm) {
      SystemSound.play(SystemSoundType.alert);
      _alarmEffectTimer = Timer.periodic(const Duration(milliseconds: 1300), (
        _,
      ) {
        SystemSound.play(SystemSoundType.alert);
      });
      return;
    }
    HapticFeedback.heavyImpact();
    _alarmEffectTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopAlarmFeedback() {
    _alarmEffectTimer?.cancel();
    _alarmEffectTimer = null;
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class _DebugOrbToggleButton extends StatelessWidget {
  const _DebugOrbToggleButton({required this.filled, required this.onPressed});

  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            filled ? '恢复初始液位' : '切换到满液位',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({required this.nickname, required this.onTap});
  final String nickname;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final displayName = _isGarbled(nickname)
        ? '\u7528\u6237\u6635\u79f0'
        : nickname;
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
                '\u4f60\u597d,$displayName',
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

  bool _isGarbled(String value) {
    return value.isEmpty ||
        value.contains('?') ||
        value.contains('閻') ||
        value.contains('鐢') ||
        value.contains('娴');
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
        title: const Text('\u6211\u7684'),
      ),
      body: const Center(
        child: Text(
          '\u6211\u7684\u9875\u9762\u5f85\u8bbe\u8ba1',
          style: TextStyle(fontSize: 18, color: Colors.black),
        ),
      ),
    );
  }
}

class _SlideOutReplicaPanel extends StatefulWidget {
  const _SlideOutReplicaPanel({
    required this.progress,
    required this.onReminderTasksChanged,
  });

  final double progress;
  final ValueChanged<List<_ReminderTaskConfig>> onReminderTasksChanged;

  @override
  State<_SlideOutReplicaPanel> createState() => _SlideOutReplicaPanelState();
}

class _SlideOutReplicaPanelState extends State<_SlideOutReplicaPanel> {
  static const String _persistedRemindersKey = 'persisted_reminder_tasks';
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
  late final List<TimeOfDay?> _customReminderTimes;
  late final List<_ReminderAlertMode?> _customReminderAlertModes;

  @override
  void initState() {
    super.initState();
    _customReminderTitles = List<String?>.filled(_cards.length, null);
    _customReminderEmojis = List<String?>.filled(_cards.length, null);
    _customReminderDescriptions = List<String?>.filled(_cards.length, null);
    _customReminderTimes = List<TimeOfDay?>.filled(_cards.length, null);
    _customReminderAlertModes = List<_ReminderAlertMode?>.filled(
      _cards.length,
      null,
    );
    _loadPersistedReminders();
  }

  Future<void> _loadPersistedReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_persistedRemindersKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final task = _ReminderTaskConfig.fromJson(item);
        if (task == null || task.index < 0 || task.index >= _cards.length) {
          continue;
        }
        _customReminderTitles[task.index] = task.title;
        _customReminderEmojis[task.index] = task.emoji;
        _customReminderDescriptions[task.index] = task.description;
        _customReminderTimes[task.index] = task.time;
        _customReminderAlertModes[task.index] = task.alertMode;
      }
    });
    widget.onReminderTasksChanged(_buildReminderTasks());
  }

  Future<void> _persistReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _buildReminderTasks()
        .map((task) => task.toJson())
        .toList(growable: false);
    await prefs.setString(_persistedRemindersKey, jsonEncode(payload));
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
    var selectedTime =
        _customReminderTimes[targetIndex] ??
        const TimeOfDay(hour: 8, minute: 0);
    var selectedAlertMode =
        _customReminderAlertModes[targetIndex] ??
        _ReminderAlertMode.systemAlarm;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? '编辑事项' : '新增事项'),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      maxLength: 16,
                      decoration: const InputDecoration(
                        labelText: '事项标题',
                        hintText: '例如：喝一杯水',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emojiController,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Emoji 表情',
                        hintText: '例如：💧',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: '事项描述',
                        hintText: '补充提醒详情',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('提醒时间'),
                      subtitle: Text(selectedTime.format(context)),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedTime = picked;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: const Text('系统闹铃'),
                            selected:
                                selectedAlertMode ==
                                _ReminderAlertMode.systemAlarm,
                            onSelected: (_) {
                              setDialogState(() {
                                selectedAlertMode =
                                    _ReminderAlertMode.systemAlarm;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('仅震动'),
                            selected:
                                selectedAlertMode ==
                                _ReminderAlertMode.vibrationOnly,
                            onSelected: (_) {
                              setDialogState(() {
                                selectedAlertMode =
                                    _ReminderAlertMode.vibrationOnly;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
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
      _customReminderTimes[targetIndex] = selectedTime;
      _customReminderAlertModes[targetIndex] = selectedAlertMode;
    });
    await _persistReminders();
    widget.onReminderTasksChanged(_buildReminderTasks());
  }

  List<_ReminderTaskConfig> _buildReminderTasks() {
    final tasks = <_ReminderTaskConfig>[];
    for (var i = 0; i < _customReminderTitles.length; i++) {
      final title = _customReminderTitles[i];
      final time = _customReminderTimes[i];
      if (title == null || time == null) {
        continue;
      }
      tasks.add(
        _ReminderTaskConfig(
          index: i,
          title: title,
          emoji: _customReminderEmojis[i] ?? '',
          description: _customReminderDescriptions[i] ?? '',
          time: time,
          alertMode:
              _customReminderAlertModes[i] ??
              _ReminderAlertMode.systemAlarm,
        ),
      );
    }
    return tasks;
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

  bool _displaySaturationFor(int index) => _customReminderTitles[index] != null;

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
    final softened = hsl
        .withSaturation((hsl.saturation * 0.34).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    return Color.lerp(softened, Colors.white, 0.05)!;
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

class _LiquidGlassCard extends StatelessWidget {
  const _LiquidGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 28,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.34),
          width: 1.0,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.10),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _OceanLiquidGlassCard extends StatelessWidget {
  const _OceanLiquidGlassCard({required this.child, required this.t});
  final Widget child;
  final double t;
  static const double _radius = 34;
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(22, 18, 22, 18);
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _OceanGlassShellPainter(t: t, radius: _radius),
            ),
          ),
          Padding(
            padding: _padding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 86),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _OceanGlassShellPainter extends CustomPainter {
  const _OceanGlassShellPainter({required this.t, required this.radius});
  final double t;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      outer,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.002)
        ..style = PaintingStyle.fill,
    );
    _paintPeripheralMist(canvas, size, outer);
    _paintWaveIntersectionRefraction(
      canvas,
      size,
      outer,
      bandThickness: 8,
      featherSigma: 9,
      scaleX: 1.018,
      scaleY: 1.028,
      shiftX: 2,
      shiftY: -1,
      tint: const Color(0x0E94D8FF),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
            const Color(0x1490D4FF),
          ],
          stops: const <double>[0.0, 0.14, 0.78, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    final shadowRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height + 8),
      width: size.width * 0.68,
      height: size.height * 0.14,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.black.withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(shadowRect),
    );
  }

  void _paintPeripheralMist(Canvas canvas, Size size, RRect outer) {
    canvas.save();
    canvas.clipRRect(outer);

    final leftRect = Rect.fromLTWH(0, 0, size.width * 0.18, size.height);
    canvas.drawRect(
      leftRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.34, 1.0],
        ).createShader(leftRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    final rightRect = Rect.fromLTWH(
      size.width * 0.82,
      0,
      size.width * 0.18,
      size.height,
    );
    canvas.drawRect(
      rightRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.34, 1.0],
        ).createShader(rightRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    final topRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.24);
    canvas.drawRect(
      topRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.26, 1.0],
        ).createShader(topRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final bottomRect = Rect.fromLTWH(
      0,
      size.height * 0.56,
      size.width,
      size.height * 0.44,
    );
    canvas.drawRect(
      bottomRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.24, 1.0],
        ).createShader(bottomRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.restore();
  }

  void _paintWaveIntersectionRefraction(
    Canvas canvas,
    Size size,
    RRect outer, {
    required double bandThickness,
    required double featherSigma,
    required double scaleX,
    required double scaleY,
    required double shiftX,
    required double shiftY,
    required Color tint,
  }) {
    final seaTop = size.height * 0.62;
    final band = Path()
      ..moveTo(0, _oceanWaveY(size, 0, seaTop) - bandThickness);
    for (double x = 0; x <= size.width; x += 5) {
      band.lineTo(x, _oceanWaveY(size, x, seaTop) - bandThickness);
    }
    for (double x = size.width; x >= 0; x -= 5) {
      band.lineTo(x, _oceanWaveY(size, x, seaTop) + bandThickness);
    }
    band.close();
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.clipRRect(outer);
    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.5);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-size.width * 0.5 + shiftX, -size.height * 0.5 + shiftY);
    _paintOceanRefraction(canvas, size, tint);
    canvas.restore();
    canvas.drawPath(
      band,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, featherSigma)
        ..color = Colors.white,
    );
    canvas.restore();
  }

  double _oceanWaveY(Size size, double x, double seaTop) {
    final progress = x / size.width;
    final primaryPhase = t * math.pi * 2;
    final secondaryPhase = t * math.pi * 4 + math.pi * 0.35;
    return seaTop +
        math.sin(progress * math.pi * 2.3 + primaryPhase) * 8 +
        math.sin(progress * math.pi * 5.6 - secondaryPhase) * 4;
  }

  void _paintOceanRefraction(Canvas canvas, Size size, Color tint) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF0A2235),
            Color(0xFF0A2740),
            Color(0xFF061B2B),
          ],
        ).createShader(rect),
    );

    final seaTop = size.height * 0.62;
    final wavePath = Path()..moveTo(0, seaTop);
    final primaryPhase = t * math.pi * 2;
    final secondaryPhase = t * math.pi * 4 + math.pi * 0.35;
    for (double x = 0; x <= size.width; x += 6) {
      final progress = x / size.width;
      final y =
          seaTop +
          math.sin(progress * math.pi * 2.3 + primaryPhase) * 8 +
          math.sin(progress * math.pi * 5.6 - secondaryPhase) * 4;
      wavePath.lineTo(x, y);
    }
    wavePath
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      wavePath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                const Color(0xD14A98E0),
                const Color(0xE12D78C2),
                const Color(0xE0185D9A),
              ],
            ).createShader(
              Rect.fromLTWH(0, seaTop, size.width, size.height - seaTop),
            ),
    );

    final causticPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = tint.withValues(alpha: 0.16);
    for (var i = 0; i < 2; i++) {
      final startX =
          size.width * (0.18 + i * 0.34) + math.sin(t * 1.4 + i) * 10;
      final startY = seaTop + size.height * (0.08 + i * 0.06);
      final endX = startX + 64 + math.cos(t * 1.1 + i) * 18;
      final endY = startY + 38 + math.sin(t * 1.4 + i) * 12;
      causticPaint.strokeWidth = 4.6 + i * 0.8;
      final path = Path()
        ..moveTo(startX, startY)
        ..quadraticBezierTo(
          (startX + endX) / 2 + math.cos(t * 1.8 + i) * 8,
          (startY + endY) / 2 - 16,
          endX,
          endY,
        );
      canvas.drawPath(path, causticPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OceanGlassShellPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.radius != radius;
  }
}

class _OceanStatsPanel extends StatelessWidget {
  const _OceanStatsPanel({
    required this.progress,
    required this.t,
    required this.appName,
    required this.totalMl,
    required this.userMl,
    required this.baikalEquivalent,
  });

  final double progress;
  final double t;
  final String appName;
  final double totalMl;
  final double userMl;
  final double baikalEquivalent;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final reveal = Curves.easeOutCubic.transform(progress);
    final panelOffset = (1 - reveal) * media.width * 0.78;
    final seaStatsTop = media.height * 0.46;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: progress < 0.06,
        child: Opacity(
          opacity: reveal,
          child: Transform.translate(
            offset: Offset(panelOffset, 0),
            child: Container(
              color: const Color(0xFF051B2E),
              child: Stack(
                children: <Widget>[
                  CustomPaint(
                    painter: _OceanScenePainter(t: t),
                    child: const SizedBox.expand(),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    top: media.height * 0.26,
                    child: _OceanLiquidGlassCard(
                      t: t,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            appName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.92),
                              letterSpacing: 2.0,
                              shadows: <Shadow>[
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '\u5df2\u6709${totalMl.toStringAsFixed(0)}ml\u6c47\u5165\u5927\u6d77\uff0c\u5176\u4e2d\u4f60\u79ef\u6512\u4e86${userMl.toStringAsFixed(0)}ml',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.98),
                              shadows: <Shadow>[
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    right: 28,
                    top: seaStatsTop,
                    child: IgnorePointer(
                      child: Text(
                        '\u5f53\u524d\u603b\u91cf\u76f8\u5f53\u4e8e${baikalEquivalent.toStringAsPrecision(1)}\u4e2a\u8d1d\u52a0\u5c14\u6e56',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.86),
                          shadows: <Shadow>[
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OceanScenePainter extends CustomPainter {
  const _OceanScenePainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF0A2235),
            Color(0xFF0A2740),
            Color(0xFF061B2B),
          ],
        ).createShader(rect),
    );

    final seaTop = size.height * 0.34;
    final wavePath = Path()..moveTo(0, seaTop);
    for (double x = 0; x <= size.width; x += 6) {
      final progress = x / size.width;
      final y =
          seaTop +
          math.sin(progress * math.pi * 2.3 + t * math.pi * 2) * 8 +
          math.sin(progress * math.pi * 5.6 - t * math.pi * 1.6) * 4;
      wavePath.lineTo(x, y);
    }
    wavePath
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      wavePath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const <Color>[
                Color(0xD7428DDA),
                Color(0xE42571BF),
                Color(0xF00C4B8A),
              ],
            ).createShader(
              Rect.fromLTWH(
                0,
                seaTop - 18,
                size.width,
                size.height - seaTop + 18,
              ),
            ),
    );

    final causticPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    for (var i = 0; i < 6; i++) {
      final startX =
          size.width * (0.08 + i * 0.15) + math.sin(t * 1.7 + i) * 16;
      final startY =
          seaTop + size.height * (0.08 + i * 0.03) + math.cos(t * 1.3 + i) * 6;
      final midX = startX + 34 + math.sin(t * 2.4 + i * 0.7) * 26;
      final midY = startY + 26 + math.cos(t * 1.5 + i) * 14;
      final endX = midX + 48 + math.cos(t * 1.1 + i * 0.5) * 32;
      final endY = midY + 46 + math.sin(t * 1.9 + i) * 18;
      causticPaint
        ..strokeWidth = 7 + (i.isEven ? 0.0 : 2.5)
        ..shader = ui.Gradient.linear(
          Offset(startX, startY),
          Offset(endX, endY),
          <Color>[
            Colors.white.withValues(alpha: 0.00),
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.02),
          ],
        );
      final path = Path()
        ..moveTo(startX, startY)
        ..quadraticBezierTo(midX, midY, endX, endY);
      canvas.drawPath(path, causticPaint);
    }

    final softGlowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24)
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.22 + i * 0.26) + math.sin(t * 2 + i) * 12;
      final y = seaTop + size.height * (0.18 + i * 0.08);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: 96 + i * 18,
          height: 44 + i * 6,
        ),
        softGlowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OceanScenePainter oldDelegate) =>
      oldDelegate.t != t;
}

class _CalendarBottomSheet extends StatefulWidget {
  const _CalendarBottomSheet({
    required this.progress,
    required this.currentOrbMl,
    required this.dailyMlByDate,
    required this.liquidTilt,
    required this.sloshing,
  });

  final double progress;
  final double currentOrbMl;
  final Map<String, double> dailyMlByDate;
  final double liquidTilt;
  final double sloshing;

  @override
  State<_CalendarBottomSheet> createState() => _CalendarBottomSheetState();
}

class _CalendarBottomSheetState extends State<_CalendarBottomSheet> {
  late final PageController _pageController;
  static const int _basePage = 120;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _basePage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final reveal = Curves.easeOutCubic.transform(widget.progress);
    final offsetY = (1 - reveal) * media.height * 0.82;
    final monthNow = DateTime.now();
    final optimizedTilt = (widget.liquidTilt * 10).round() / 10;
    final optimizedSloshing = (widget.sloshing * 10).round() / 10;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: widget.progress < 0.05,
        child: Opacity(
          opacity: reveal,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: media.height * 0.72,
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 36,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: PageView.builder(
                    controller: _pageController,
                    allowImplicitScrolling: true,
                    itemBuilder: (context, index) {
                      final delta = index - _basePage;
                      final month = DateTime(
                        monthNow.year,
                        monthNow.month + delta,
                      );
                      return RepaintBoundary(
                        child: _MonthCalendarView(
                          month: month,
                          currentOrbMl: widget.currentOrbMl,
                          dailyMlByDate: widget.dailyMlByDate,
                          liquidTilt: optimizedTilt,
                          sloshing: optimizedSloshing,
                        ),
                      );
                    },
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

class _MonthCalendarView extends StatelessWidget {
  static const SliverGridDelegateWithFixedCrossAxisCount _calendarGridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      );

  const _MonthCalendarView({
    required this.month,
    required this.currentOrbMl,
    required this.dailyMlByDate,
    required this.liquidTilt,
    required this.sloshing,
  });

  final DateTime month;
  final double currentOrbMl;
  final Map<String, double> dailyMlByDate;
  final double liquidTilt;
  final double sloshing;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = (first.weekday + 6) % 7;
    final total = leading + daysInMonth;
    final rows = (total / 7).ceil();
    final monthLabel =
        '${month.year}.${month.month.toString().padLeft(2, '0')}';

    return Container(
      color: Colors.white,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 18,
            top: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                monthLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 110, 18, 18),
            gridDelegate: _calendarGridDelegate,
            itemCount: rows * 7,
            itemBuilder: (context, index) {
              final dayNumber = index - leading + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }

              final isToday =
                  month.year == DateTime.now().year &&
                  month.month == DateTime.now().month &&
                  dayNumber == DateTime.now().day;
              final dateKey =
                  '${month.year}-${month.month.toString().padLeft(2, '0')}-${dayNumber.toString().padLeft(2, '0')}';
              final uploadedMl = dailyMlByDate[dateKey] ?? 0;
              final dailyMl = isToday ? uploadedMl + currentOrbMl : uploadedMl;
              final waterLevel = (dailyMl / 100).clamp(0.0, 1.0);

              return RepaintBoundary(
                child: _LiquidGlassCard(
                  radius: 18,
                  padding: EdgeInsets.zero,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CalendarWaterPainter(
                            waterLevel: waterLevel,
                            liquidTilt: liquidTilt,
                            sloshing: sloshing,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 8,
                        child: Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isToday ? Colors.black : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarWaterPainter extends CustomPainter {
  const _CalendarWaterPainter({
    required this.waterLevel,
    required this.liquidTilt,
    required this.sloshing,
  });
  final double waterLevel;
  final double liquidTilt;
  final double sloshing;
  @override
  void paint(Canvas canvas, Size size) {
    if (waterLevel <= 0) {
      return;
    }
    final rect = Offset.zero & size;
    final clipPath = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
    final motionLock = ((waterLevel - 0.9) / 0.1).clamp(0.0, 1.0);
    final liquidTopBase = size.height * (1 - waterLevel);
    final tiltHeight = liquidTilt * size.height * 0.065 * (1 - motionLock);
    final sloshHeight = sloshing * size.height * 0.075 * (1 - motionLock);
    final minSurfaceY = waterLevel >= 0.999 ? -size.height * 0.08 : 0.0;
    final maxSurfaceY = size.height * 0.90;
    final overscan = size.width * 0.26;
    final surfacePath = Path();
    final fillPath = Path()
      ..moveTo(-overscan, size.height + overscan)
      ..lineTo(-overscan, liquidTopBase);
    var isFirstPoint = true;
    for (double x = -overscan; x <= size.width + overscan; x += 4.0) {
      final progress = (x / size.width).clamp(0.0, 1.0);
      final edgeFalloff = math.sin(progress * math.pi);
      final slope = ((progress - 0.5) * 2) * tiltHeight;
      final wave =
          math.sin((progress * 2.4 + sloshing * 0.35) * math.pi * 2) *
              sloshHeight *
              edgeFalloff +
          math.sin((progress * 4.5 - sloshing * 0.22) * math.pi * 2) *
              sloshHeight *
              0.42 *
              edgeFalloff;
      final y = (liquidTopBase + slope + wave).clamp(minSurfaceY, maxSurfaceY);
      if (isFirstPoint) {
        surfacePath.moveTo(x, y);
        isFirstPoint = false;
      } else {
        surfacePath.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }
    fillPath
      ..lineTo(size.width + overscan, size.height + overscan)
      ..close();
    final clippedFill = Path.combine(
      PathOperation.intersect,
      clipPath,
      fillPath,
    );
    canvas.drawPath(
      clippedFill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x9A8ED1FF), Color(0xCC5CA8FF)],
        ).createShader(rect),
    );
    canvas.drawPath(
      surfacePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.34),
    );
  }

  @override
  bool shouldRepaint(covariant _CalendarWaterPainter oldDelegate) {
    return oldDelegate.waterLevel != waterLevel ||
        oldDelegate.liquidTilt != liquidTilt ||
        oldDelegate.sloshing != sloshing;
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
    required this.shadowTilt,
    required this.sloshing,
    required this.color,
    required this.orbMl,
    required this.uploadProgress,
    required this.uploadReveal,
  });

  final double t;
  final double safeTop;
  final int activeStretchIndex;
  final int previousStretchIndex;
  final double orbFill;
  final double liquidTilt;
  final double shadowTilt;
  final double sloshing;
  final Color color;
  final double orbMl;
  final double uploadProgress;
  final double uploadReveal;

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
    final shadowOffset = _orbShadowOffset(radius);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx + shadowOffset.dx * 1.10,
          center.dy + radius + 18 + shadowOffset.dy,
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
          center.dx + shadowOffset.dx * 0.94,
          center.dy + radius + 12 + shadowOffset.dy * 0.90,
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
        ..shader = RadialGradient(
          center: const Alignment(-0.18, -0.22),
          colors: <Color>[
            Colors.white.withValues(alpha: 0.72),
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.14),
          ],
          stops: <double>[0.0, 0.62, 1.0],
        ).createShader(orbRect)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.08),
          ],
        ).createShader(orbRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7,
    );
    canvas.drawCircle(
      center,
      radius - 0.2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.14
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.08)
        ..isAntiAlias = true,
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(center.dx - radius, center.dy, radius * 2, radius),
    );
    canvas.drawCircle(
      center,
      radius - 0.4,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.30),
          ],
          stops: const <double>[0.0, 0.44, 1.0],
        ).createShader(orbRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.09)
        ..isAntiAlias = true,
    );
    canvas.restore();
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(center.dx - radius, center.dy, radius * 2, radius),
    );
    canvas.drawCircle(
      center,
      radius - 2.2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.03),
            const Color(0x249AC7FF),
          ],
        ).createShader(orbRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.52,
    );
    canvas.restore();

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
    final fillLockProgress = _normalize(orbFill, 0.92, 1.0);
    final motionMultiplier = 1 - _easeOutCubic(fillLockProgress);
    final fillTop = center.dy - radius;
    final lockedLiquidTop = _lerp(
      liquidTop,
      fillTop,
      _easeOutCubic(fillLockProgress),
    );
    final waveA =
        (4.5 + math.sin(t * math.pi * 2).abs() * 2.6) * motionMultiplier;
    final waveB =
        (1.8 + math.cos(t * math.pi * 2.6).abs() * 1.4) * motionMultiplier;
    final tiltHeight = liquidTilt * radius * 0.22 * motionMultiplier;
    final sloshHeight = sloshing * radius * 0.10 * motionMultiplier;
    final minSurfaceY = _lerp(
      center.dy - radius * 0.92,
      fillTop,
      _easeOutCubic(fillLockProgress),
    );
    final maxSurfaceY = center.dy + radius * 0.90;

    final liquidPath = Path()
      ..moveTo(left, center.dy + radius)
      ..lineTo(left, lockedLiquidTop);

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
      final surfaceY = (lockedLiquidTop + slope + wave + sloshWave).clamp(
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
            _orbBlueTop.withValues(alpha: 0.84),
            _orbBlueBottom.withValues(alpha: 0.92),
            _orbBlueBottom.withValues(alpha: 0.96),
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
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.76),
            const Color(0xB7E1F0FF),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    canvas.drawCircle(
      center,
      radius - 1.2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.44),
            const Color(0x6EA9CCFF),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.72,
    );

    _drawUploadOverlay(canvas, center: center, radius: radius);
    _drawOrbLabel(canvas, center: center, radius: radius);
  }

  void _drawOrbLabel(
    Canvas canvas, {
    required Offset center,
    required double radius,
  }) {
    final mlText = '${orbMl.toStringAsFixed(0)}ml';
    final labelProbeY = center.dy + radius * 0.06;
    final surfaceY = _orbSurfaceY(center: center, radius: radius);
    final isSubmerged = labelProbeY >= surfaceY;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: mlText,
        style: TextStyle(
          fontSize: radius * 0.22,
          fontWeight: FontWeight.w800,
          color: isSubmerged
              ? Colors.white.withValues(alpha: 0.92)
              : Color.lerp(_orbBlueTop, _orbBlueBottom, 0.62)!,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: radius * 1.3);
    titlePainter.paint(
      canvas,
      Offset(center.dx - titlePainter.width / 2, center.dy - radius * 0.04),
    );
  }

  void _drawUploadOverlay(
    Canvas canvas, {
    required Offset center,
    required double radius,
  }) {
    if (uploadReveal <= 0.001) {
      return;
    }
    final reveal = _easeOutCubic(uploadReveal.clamp(0.0, 1.0));
    final progress = uploadProgress.clamp(0.0, 1.0);
    final orbRect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    canvas.clipPath(Path()..addOval(orbRect));
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i * 0.18) % 1.0;
      final opacity = (1 - phase) * reveal;
      if (opacity <= 0.02) {
        continue;
      }
      _drawUploadRippleStroke(
        canvas,
        center: center,
        radius: radius,
        phase: phase,
        opacity: opacity,
      );
    }
    canvas.restore();

    final percentText = '已汇入云海${(progress * 100).round()}%';
    _drawArcText(
      canvas,
      text: percentText,
      center: center,
      radius: radius * 1.04,
      startAngle: -math.pi * 0.88,
      endAngle: -math.pi * 0.12,
      opacity: reveal,
    );
  }

  void _drawUploadRippleStroke(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double phase,
    required double opacity,
  }) {
    final baseRadius = radius * (0.11 + phase * 1.02);
    final strokeWidth = _lerp(radius * 0.026, radius * 0.008, phase);
    final rippleRect = Rect.fromCircle(center: center, radius: baseRadius);
    final shadowCenter = center.translate(0, strokeWidth * 0.22);

    canvas.drawCircle(
      shadowCenter,
      baseRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.12
        ..color = const Color(0xFF4D8BE0).withValues(alpha: 0.18 * opacity)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          radius * 0.018 * opacity,
        ),
    );

    canvas.drawCircle(
      center,
      baseRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.36 * opacity),
            const Color(0xFFAED5FF).withValues(alpha: 0.28 * opacity),
            const Color(0xFF6FA7F5).withValues(alpha: 0.12 * opacity),
          ],
          stops: const <double>[0.0, 0.42, 1.0],
        ).createShader(rippleRect)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          radius * 0.010 * opacity,
        ),
    );

    canvas.drawArc(
      rippleRect.shift(Offset(0, -strokeWidth * 0.10)),
      math.pi * 1.04,
      math.pi * 0.92,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth * 0.52
        ..color = Colors.white.withValues(alpha: 0.34 * opacity)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          radius * 0.008 * opacity,
        ),
    );

    canvas.drawArc(
      rippleRect.shift(Offset(0, strokeWidth * 0.08)),
      -math.pi * 0.18,
      math.pi * 0.36,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth * 0.46
        ..color = const Color(0xFF7FB8FF).withValues(alpha: 0.16 * opacity)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          radius * 0.008 * opacity,
        ),
    );
  }

  void _drawArcText(
    Canvas canvas, {
    required String text,
    required Offset center,
    required double radius,
    required double startAngle,
    required double endAngle,
    required double opacity,
  }) {
    if (text.isEmpty || opacity <= 0.0) {
      return;
    }
    final spanStyle = TextStyle(
      fontSize: radius * 0.115,
      fontWeight: FontWeight.w700,
      color: Colors.black.withValues(alpha: 0.78 * opacity),
      letterSpacing: 0.2,
    );
    final charPainters = <TextPainter>[];
    var totalWidth = 0.0;
    for (final rune in text.runes) {
      final painter = TextPainter(
        text: TextSpan(text: String.fromCharCode(rune), style: spanStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      charPainters.add(painter);
      totalWidth += painter.width;
    }
    if (charPainters.isEmpty || totalWidth <= 0) {
      return;
    }
    final arcLength = radius * (endAngle - startAngle).abs();
    final scale = math.min(1.0, arcLength / (totalWidth + 8));
    var consumed = (arcLength - totalWidth * scale) / 2;
    for (final painter in charPainters) {
      final charWidth = painter.width * scale;
      final theta = startAngle + (consumed + charWidth / 2) / radius;
      final charCenter = Offset(
        center.dx + math.cos(theta) * radius,
        center.dy + math.sin(theta) * radius,
      );
      canvas.save();
      canvas.translate(charCenter.dx, charCenter.dy);
      canvas.rotate(theta + math.pi / 2);
      canvas.scale(scale, scale);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
      consumed += charWidth;
    }
  }

  double _orbSurfaceY({
    required Offset center,
    required double radius,
  }) {
    final liquidTop = center.dy + radius * (1 - 2 * orbFill);
    final fillLockProgress = _normalize(orbFill, 0.92, 1.0);
    final motionMultiplier = 1 - _easeOutCubic(fillLockProgress);
    final lockedLiquidTop = _lerp(
      liquidTop,
      center.dy - radius,
      _easeOutCubic(fillLockProgress),
    );
    final waveA =
        (4.5 + math.sin(t * math.pi * 2).abs() * 2.6) * motionMultiplier;
    final waveB =
        (1.8 + math.cos(t * math.pi * 2.6).abs() * 1.4) * motionMultiplier;
    final tiltHeight = liquidTilt * radius * 0.22 * motionMultiplier;
    final sloshHeight = sloshing * radius * 0.10 * motionMultiplier;
    const progress = 0.5;
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
        math.sin((progress * 1.45 - t * 1.15 + sloshing * 0.35) * math.pi * 2) *
            sloshHeight *
            edgeFalloff +
        math.sin((progress * 2.8 + t * 0.82) * math.pi * 2) *
            sloshHeight *
            0.32 *
            edgeFalloff;
    return lockedLiquidTop + slope + wave + sloshWave;
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

  Offset _orbShadowOffset(double radius) {
    final stableTilt = ((shadowTilt * 10).round() / 10).toDouble();
    final horizontal = stableTilt * radius * 0.082;
    final vertical = stableTilt.abs() * radius * 0.008;
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
        oldDelegate.shadowTilt != shadowTilt ||
        oldDelegate.sloshing != sloshing ||
        oldDelegate.color != color ||
        oldDelegate.orbMl != orbMl ||
        oldDelegate.uploadProgress != uploadProgress ||
        oldDelegate.uploadReveal != uploadReveal;
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
