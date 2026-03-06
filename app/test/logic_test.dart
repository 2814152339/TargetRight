import 'package:flutter_test/flutter_test.dart';
import 'package:jinshi_checkin/src/logic.dart';
import 'package:jinshi_checkin/src/models.dart';

void main() {
  test('循环任务在时间窗口内按间隔生成提醒点', () {
    final task = HabitTask(
      id: 't1',
      name: '喝水',
      type: TaskType.recurring,
      createdAt: DateTime(2026, 3, 1),
      enabled: true,
      isDual: false,
      progress: 0,
      interaction: InteractionTemplate.tree,
      intervalMinutes: 120,
      startMinuteOfDay: 9 * 60,
      endMinuteOfDay: 21 * 60,
      startDate: DateTime(2026, 3, 6),
    );

    final points = plannedTimesForTaskInRange(
      task,
      DateTime(2026, 3, 6, 0),
      DateTime(2026, 3, 6, 23, 59),
    );

    expect(points.first, DateTime(2026, 3, 6, 9));
    expect(points.last, DateTime(2026, 3, 6, 21));
    expect(points.length, 7);
  });

  test('待确认提醒点返回最早且你未记录的时间点', () {
    final task = HabitTask(
      id: 't1',
      name: '喝水',
      type: TaskType.recurring,
      createdAt: DateTime(2026, 3, 1),
      enabled: true,
      isDual: false,
      progress: 0,
      interaction: InteractionTemplate.tree,
      intervalMinutes: 120,
      startMinuteOfDay: 9 * 60,
      endMinuteOfDay: 21 * 60,
      startDate: DateTime(2026, 3, 6),
    );

    final nine = DateTime(2026, 3, 6, 9);
    final eleven = DateTime(2026, 3, 6, 11);
    final checkIns = <String, CheckInRecord>{
      reminderPointId(task.id, nine): CheckInRecord(
        pointId: reminderPointId(task.id, nine),
        taskId: task.id,
        plannedTime: nine,
        updatedAt: DateTime(2026, 3, 6, 9, 1),
        yourState: CheckInState.done,
      ),
    };

    final pending = earliestPendingPoint(
      task,
      checkIns,
      DateTime(2026, 3, 6, 12),
    );

    expect(pending, eleven);
  });

  test('双人任务只有双方都完成才算最终完成', () {
    final task = HabitTask(
      id: 't2',
      name: '运动',
      type: TaskType.recurring,
      createdAt: DateTime(2026, 3, 1),
      enabled: true,
      isDual: true,
      progress: 0,
      interaction: InteractionTemplate.muscle,
      intervalMinutes: 240,
      startMinuteOfDay: 8 * 60,
      endMinuteOfDay: 20 * 60,
      startDate: DateTime(2026, 3, 6),
    );

    final pointTime = DateTime(2026, 3, 6, 12);
    final pointId = reminderPointId(task.id, pointTime);

    final recordOnlyMe = CheckInRecord(
      pointId: pointId,
      taskId: task.id,
      plannedTime: pointTime,
      updatedAt: DateTime(2026, 3, 6, 12, 1),
      yourState: CheckInState.done,
      partnerState: null,
    );
    final recordBothDone = CheckInRecord(
      pointId: pointId,
      taskId: task.id,
      plannedTime: pointTime,
      updatedAt: DateTime(2026, 3, 6, 12, 2),
      yourState: CheckInState.done,
      partnerState: CheckInState.done,
    );

    expect(finalStatusForPoint(task, recordOnlyMe), FinalStatus.unrecorded);
    expect(finalStatusForPoint(task, recordBothDone), FinalStatus.done);
  });
}
