import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logic.dart';
import 'models.dart';
import 'notifications.dart';
import 'storage.dart';

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final appControllerProvider = StateNotifierProvider<AppController, AppState>((
  ref,
) {
  return AppController(
    store: ref.read(localStoreProvider),
    notifications: ref.read(notificationServiceProvider),
  );
});

class AppState {
  const AppState({
    required this.initialized,
    required this.tasks,
    required this.checkIns,
    required this.isVip,
    required this.featureFlagDualOpen,
    required this.now,
  });

  factory AppState.initial() {
    return AppState(
      initialized: false,
      tasks: const <HabitTask>[],
      checkIns: const <String, CheckInRecord>{},
      isVip: false,
      featureFlagDualOpen: true,
      now: DateTime.now(),
    );
  }

  final bool initialized;
  final List<HabitTask> tasks;
  final Map<String, CheckInRecord> checkIns;
  final bool isVip;
  final bool featureFlagDualOpen;
  final DateTime now;

  bool get canChooseDualWhenCreate => featureFlagDualOpen || isVip;

  List<HabitTask> get recurringTasks => tasks
      .where((task) => task.type == TaskType.recurring && task.enabled)
      .toList();

  AppState copyWith({
    bool? initialized,
    List<HabitTask>? tasks,
    Map<String, CheckInRecord>? checkIns,
    bool? isVip,
    bool? featureFlagDualOpen,
    DateTime? now,
  }) {
    return AppState(
      initialized: initialized ?? this.initialized,
      tasks: tasks ?? this.tasks,
      checkIns: checkIns ?? this.checkIns,
      isVip: isVip ?? this.isVip,
      featureFlagDualOpen: featureFlagDualOpen ?? this.featureFlagDualOpen,
      now: now ?? this.now,
    );
  }
}

class AppController extends StateNotifier<AppState> {
  AppController({
    required LocalStore store,
    required NotificationService notifications,
  }) : _store = store,
       _notifications = notifications,
       super(AppState.initial());

  final LocalStore _store;
  final NotificationService _notifications;
  Timer? _ticker;

  Future<void> initialize() async {
    if (state.initialized) {
      return;
    }

    final snapshot = await _store.load();
    final taskList = List<HabitTask>.from(snapshot.tasks)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final checkInMap = <String, CheckInRecord>{
      for (final item in snapshot.checkIns) item.pointId: item,
    };

    state = state.copyWith(
      initialized: true,
      tasks: taskList,
      checkIns: checkInMap,
      isVip: snapshot.isVip,
      featureFlagDualOpen: snapshot.featureFlagDualOpen,
      now: DateTime.now(),
    );

    await _notifications.initialize();
    _startTicker();
    await _refreshNotifications();
  }

  Future<void> upsertTask(HabitTask task) async {
    final tasks = List<HabitTask>.from(state.tasks);
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.add(task);
    }
    tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    state = state.copyWith(tasks: tasks);
    await _persist();
    await _refreshNotifications();
  }

  Future<void> setTaskEnabled(String taskId, bool enabled) async {
    final tasks = state.tasks
        .map(
          (task) => task.id == taskId ? task.copyWith(enabled: enabled) : task,
        )
        .toList();
    state = state.copyWith(tasks: tasks);
    await _persist();
    await _refreshNotifications();
  }

  Future<void> deleteTask(String taskId) async {
    final tasks = state.tasks.where((task) => task.id != taskId).toList();
    final checkIns = Map<String, CheckInRecord>.from(state.checkIns)
      ..removeWhere((_, value) => value.taskId == taskId);
    state = state.copyWith(tasks: tasks, checkIns: checkIns);
    await _persist();
    await _refreshNotifications();
  }

  Future<void> setVip(bool value) async {
    state = state.copyWith(isVip: value);
    await _persist();
  }

  Future<void> setFeatureFlagDualOpen(bool value) async {
    state = state.copyWith(featureFlagDualOpen: value);
    await _persist();
  }

  String createInviteLink(String taskId) {
    return 'jinshi://invite?task=$taskId&ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> convertTaskToDual(String taskId) async {
    final tasks = state.tasks.map((task) {
      if (task.id != taskId) {
        return task;
      }
      return task.copyWith(isDual: true);
    }).toList();
    state = state.copyWith(tasks: tasks);
    await _persist();
  }

  Future<void> checkInYourself({
    required String taskId,
    required DateTime plannedTime,
    required CheckInState result,
  }) async {
    await _applyCheckIn(
      taskId: taskId,
      plannedTime: plannedTime,
      yourState: result,
      partnerState: null,
    );
  }

  Future<void> checkInPartner({
    required String taskId,
    required DateTime plannedTime,
    required CheckInState result,
  }) async {
    await _applyCheckIn(
      taskId: taskId,
      plannedTime: plannedTime,
      yourState: null,
      partnerState: result,
    );
  }

  Future<void> _applyCheckIn({
    required String taskId,
    required DateTime plannedTime,
    CheckInState? yourState,
    CheckInState? partnerState,
  }) async {
    final task = state.tasks.where((item) => item.id == taskId).firstOrNull;
    if (task == null) {
      return;
    }

    final pointId = reminderPointId(taskId, plannedTime);
    final current = state.checkIns[pointId];
    final currentFinal = current?.isFinalDone(task.isDual) ?? false;
    final updated = CheckInRecord(
      pointId: pointId,
      taskId: taskId,
      plannedTime: plannedTime,
      updatedAt: DateTime.now(),
      yourState: yourState ?? current?.yourState,
      partnerState: partnerState ?? current?.partnerState,
    );
    final updatedFinal = updated.isFinalDone(task.isDual);

    final checkIns = Map<String, CheckInRecord>.from(state.checkIns)
      ..[pointId] = updated;
    var tasks = state.tasks;
    if (!currentFinal && updatedFinal) {
      tasks = state.tasks
          .map(
            (item) => item.id == taskId
                ? item.copyWith(progress: item.progress + 1)
                : item,
          )
          .toList();
    }

    state = state.copyWith(tasks: tasks, checkIns: checkIns);
    await _persist();
    await _refreshNotifications();
  }

  Future<void> _persist() {
    final snapshot = PersistedSnapshot(
      tasks: state.tasks,
      checkIns: state.checkIns.values.toList(),
      isVip: state.isVip,
      featureFlagDualOpen: state.featureFlagDualOpen,
    );
    return _store.save(snapshot);
  }

  Future<void> _refreshNotifications() async {
    final now = DateTime.now();
    final allUpcoming = plannedPointsForTasksInRange(
      state.tasks.where((task) => task.enabled).toList(),
      now,
      now.add(const Duration(days: 14)),
      maxCount: 128,
    );

    final items = <NotificationItem>[];
    for (final point in allUpcoming) {
      if (!point.time.isAfter(now)) {
        continue;
      }
      final record = state.checkIns[point.pointId];
      if (record?.yourState != null) {
        continue;
      }
      items.add(
        NotificationItem(
          id: point.pointId.hashCode & 0x7fffffff,
          title: '提醒：${point.task.name}',
          body: point.task.isDual ? '请完成打卡（双人任务）' : '请完成打卡',
          time: point.time,
        ),
      );
      if (items.length >= 48) {
        break;
      }
    }
    await _notifications.scheduleUpcoming(items);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      state = state.copyWith(now: DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
