import 'models.dart';

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String reminderPointId(String taskId, DateTime plannedTime) =>
    '$taskId@${plannedTime.toIso8601String()}';

class PlannedPoint {
  PlannedPoint({required this.task, required this.time, required this.pointId});

  final HabitTask task;
  final DateTime time;
  final String pointId;
}

class DayPlanEntry {
  DayPlanEntry({
    required this.task,
    required this.time,
    required this.pointId,
    required this.record,
  });

  final HabitTask task;
  final DateTime time;
  final String pointId;
  final CheckInRecord? record;
}

List<DateTime> plannedTimesForTaskInRange(
  HabitTask task,
  DateTime rangeStart,
  DateTime rangeEnd, {
  int? maxCount,
}) {
  if (!task.enabled || rangeEnd.isBefore(rangeStart)) {
    return <DateTime>[];
  }

  final result = <DateTime>[];
  if (task.type == TaskType.single) {
    final single = task.singleDateTime;
    if (single != null &&
        !single.isBefore(rangeStart) &&
        !single.isAfter(rangeEnd)) {
      result.add(single);
    }
    return result;
  }

  final interval = task.intervalMinutes ?? 0;
  final startMinute = task.startMinuteOfDay ?? 0;
  final endMinute = task.endMinuteOfDay ?? 0;
  final startDate = task.startDate == null
      ? dateOnly(rangeStart)
      : dateOnly(task.startDate!);
  final endDate = task.endDate == null
      ? dateOnly(rangeEnd)
      : dateOnly(task.endDate!);
  if (interval <= 0 || endMinute < startMinute || endDate.isBefore(startDate)) {
    return <DateTime>[];
  }

  var day = dateOnly(rangeStart);
  if (day.isBefore(startDate)) {
    day = startDate;
  }
  final endBoundaryDay = dateOnly(rangeEnd);
  while (!day.isAfter(endBoundaryDay) && !day.isAfter(endDate)) {
    if (!day.isBefore(startDate)) {
      for (var minute = startMinute; minute <= endMinute; minute += interval) {
        final planned = day.add(Duration(minutes: minute));
        if (planned.isBefore(rangeStart) || planned.isAfter(rangeEnd)) {
          continue;
        }
        result.add(planned);
        if (maxCount != null && result.length >= maxCount) {
          return result;
        }
      }
    }
    day = day.add(const Duration(days: 1));
  }
  return result;
}

List<PlannedPoint> plannedPointsForTasksInRange(
  List<HabitTask> tasks,
  DateTime rangeStart,
  DateTime rangeEnd, {
  int? maxCount,
}) {
  final items = <PlannedPoint>[];
  for (final task in tasks) {
    final times = plannedTimesForTaskInRange(task, rangeStart, rangeEnd);
    for (final time in times) {
      items.add(
        PlannedPoint(
          task: task,
          time: time,
          pointId: reminderPointId(task.id, time),
        ),
      );
    }
  }
  items.sort((a, b) => a.time.compareTo(b.time));
  if (maxCount != null && items.length > maxCount) {
    return items.take(maxCount).toList();
  }
  return items;
}

DateTime? earliestPendingPoint(
  HabitTask task,
  Map<String, CheckInRecord> checkIns,
  DateTime now,
) {
  if (!task.enabled || task.type != TaskType.recurring) {
    return null;
  }
  final todayStart = dateOnly(now);
  final plannedToday = plannedTimesForTaskInRange(task, todayStart, now);
  for (final pointTime in plannedToday) {
    final record = checkIns[reminderPointId(task.id, pointTime)];
    final hasYourCheckIn = record?.yourState != null;
    if (!hasYourCheckIn) {
      return pointTime;
    }
  }
  return null;
}

DateTime? nextPointAfterNow(HabitTask task, DateTime now) {
  if (!task.enabled) {
    return null;
  }
  final searchEnd = now.add(const Duration(days: 30));
  final upcoming = plannedTimesForTaskInRange(
    task,
    now.add(const Duration(seconds: 1)),
    searchEnd,
    maxCount: 1,
  );
  return upcoming.isEmpty ? null : upcoming.first;
}

List<DayPlanEntry> dayEntries(
  List<HabitTask> tasks,
  Map<String, CheckInRecord> checkIns,
  DateTime day,
) {
  final dayStart = dateOnly(day);
  final dayEnd = dayStart
      .add(const Duration(days: 1))
      .subtract(const Duration(milliseconds: 1));
  final items = <DayPlanEntry>[];
  for (final task in tasks) {
    final times = plannedTimesForTaskInRange(task, dayStart, dayEnd);
    for (final time in times) {
      final pointId = reminderPointId(task.id, time);
      items.add(
        DayPlanEntry(
          task: task,
          time: time,
          pointId: pointId,
          record: checkIns[pointId],
        ),
      );
    }
  }
  items.sort((a, b) => a.time.compareTo(b.time));
  return items;
}

enum FinalStatus { done, missed, unrecorded }

FinalStatus finalStatusForPoint(HabitTask task, CheckInRecord? record) {
  if (record == null) {
    return FinalStatus.unrecorded;
  }

  if (!task.isDual) {
    if (record.yourState == CheckInState.done) {
      return FinalStatus.done;
    }
    if (record.yourState == CheckInState.missed) {
      return FinalStatus.missed;
    }
    return FinalStatus.unrecorded;
  }

  if (record.yourState == CheckInState.missed ||
      record.partnerState == CheckInState.missed) {
    return FinalStatus.missed;
  }
  if (record.yourState == CheckInState.done &&
      record.partnerState == CheckInState.done) {
    return FinalStatus.done;
  }
  return FinalStatus.unrecorded;
}

String finalStatusLabel(FinalStatus status) {
  switch (status) {
    case FinalStatus.done:
      return '已完成';
    case FinalStatus.missed:
      return '未完成';
    case FinalStatus.unrecorded:
      return '未记录';
  }
}

String stateLabel(CheckInState? state) {
  switch (state) {
    case CheckInState.done:
      return '已完成';
    case CheckInState.missed:
      return '未完成';
    case null:
      return '未记录';
  }
}

class InteractionView {
  InteractionView({
    required this.emoji,
    required this.stageName,
    required this.current,
    required this.target,
  });

  final String emoji;
  final String stageName;
  final int current;
  final int target;

  double get ratio {
    if (target <= 0) {
      return 0;
    }
    final value = current / target;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }
}

InteractionView interactionForTask(HabitTask task) {
  final progress = task.progress < 0 ? 0 : task.progress;
  final stageSize = 10;

  late final List<String> names;
  late final List<String> emoji;
  switch (task.interaction) {
    case InteractionTemplate.tree:
      names = <String>['种子', '幼苗', '小树', '果树'];
      emoji = <String>['🌱', '🪴', '🌳', '🍎'];
    case InteractionTemplate.egg:
      names = <String>['鸡蛋', '裂纹', '小鸡', '大鸡'];
      emoji = <String>['🥚', '🫧', '🐣', '🐔'];
    case InteractionTemplate.tower:
      names = <String>['地基', '一层', '高楼', '摩天楼'];
      emoji = <String>['🧱', '🏠', '🏢', '🏙️'];
    case InteractionTemplate.muscle:
      names = <String>['瘦子', '起势', '健体', '肌肉男'];
      emoji = <String>['🧍', '🏃', '💪', '🏋️'];
  }

  final rawIndex = progress ~/ stageSize;
  final stageIndex = rawIndex >= names.length ? names.length - 1 : rawIndex;
  var current = progress % stageSize;
  if (stageIndex == names.length - 1 && rawIndex >= names.length - 1) {
    current = stageSize;
  }
  return InteractionView(
    emoji: emoji[stageIndex],
    stageName: names[stageIndex],
    current: current,
    target: stageSize,
  );
}
