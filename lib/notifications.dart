import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'routines_daily';
  static const _notifId = 1;

  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Fallback UTC si la timezone locale n'est pas trouvée
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Planifie (ou replanifie) le rappel quotidien.
  /// [routineCount] : nombre de routines daily de l'utilisateur.
  static Future<void> scheduleDailyReminder({
    int hour = 9,
    int minute = 0,
    required int routineCount,
  }) async {
    if (!_initialized) await init();

    await _plugin.cancel(_notifId);

    final body = routineCount > 0
        ? 'Tu as $routineCount routine${routineCount > 1 ? 's' : ''} à faire aujourd\'hui 🎯'
        : 'N\'oublie pas tes routines du jour !';

    await _plugin.zonedSchedule(
      _notifId,
      'Productivitwo',
      body,
      _nextOccurrence(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Rappel routines',
          channelDescription: 'Rappel quotidien pour tes routines',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  static Future<void> cancelAll() => _plugin.cancelAll();
}
