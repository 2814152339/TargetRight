import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'logic.dart';
import 'models.dart';
import 'storage.dart';

const _dailyReminderId = 10001;
const _actionDone = 'checkin_done';
const _actionMissed = 'checkin_missed';
const _iosCategory = 'daily_checkin_category';

enum ReminderAction { done, missed, open }

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  CheckInStatus? status;
  if (response.actionId == _actionDone) {
    status = CheckInStatus.done;
  }
  if (response.actionId == _actionMissed) {
    status = CheckInStatus.missed;
  }
  if (status == null) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final snapshot = AppSnapshot.fromJsonString(
    prefs.getString(appSnapshotStorageKey),
  );
  final updated = applyDailyCheckIn(
    snapshot,
    now: DateTime.now(),
    status: status,
  );
  await prefs.setString(appSnapshotStorageKey, updated.toJsonString());
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize(
    Future<void> Function(ReminderAction action) onAction,
  ) async {
    if (_initialized) {
      return;
    }

    final iosCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        _iosCategory,
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(_actionDone, '已完成'),
          DarwinNotificationAction.plain(_actionMissed, '未完成'),
        ],
      ),
    ];

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final ios = DarwinInitializationSettings(
      notificationCategories: iosCategories,
    );
    final settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId == _actionDone) {
          await onAction(ReminderAction.done);
          return;
        }
        if (response.actionId == _actionMissed) {
          await onAction(ReminderAction.missed);
          return;
        }
        await onAction(ReminderAction.open);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    tzdata.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {}

    _initialized = true;
  }

  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    if (!_initialized) {
      return;
    }

    await _plugin.cancel(_dailyReminderId);
    final scheduleTime = _nextScheduleTime(hour: hour, minute: minute);
    await _plugin.zonedSchedule(
      _dailyReminderId,
      '打卡提醒',
      '今天的任务完成了吗？',
      scheduleTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_checkin_channel',
          '每日打卡提醒',
          channelDescription: '点击已完成或未完成直接记录结果',
          importance: Importance.max,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(_actionDone, '已完成'),
            const AndroidNotificationAction(_actionMissed, '未完成'),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: _iosCategory),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextScheduleTime({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
