import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
  });

  final int id;
  final String title;
  final String body;
  final DateTime time;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

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
    } catch (_) {
      // Keep package default location when timezone lookup fails.
    }

    _initialized = true;
  }

  Future<void> scheduleUpcoming(List<NotificationItem> items) async {
    if (!_initialized) {
      return;
    }
    await _plugin.cancelAll();
    for (final item in items) {
      if (!item.time.isAfter(DateTime.now())) {
        continue;
      }
      final tzTime = tz.TZDateTime.from(item.time, tz.local);
      await _plugin.zonedSchedule(
        item.id,
        item.title,
        item.body,
        tzTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jinshi_checkin_channel',
            '打卡提醒',
            channelDescription: '互动激励打卡提醒',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }
}
