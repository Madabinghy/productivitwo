import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'routines_daily';
  static const _notifId = 1;
  static const _reviewChannelId = 'review_daily';
  static const _reviewNotifId = 2;

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> init() async {
    if (_initialized || !_supported) return;

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Fallback UTC si la timezone locale n'est pas trouvée
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );
    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    if (!_supported) return;
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
    if (!_supported) return;
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

  static Future<void> scheduleDailyReview({
    int hour = 21,
    int minute = 0,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();

    await _plugin.cancel(_reviewNotifId);

    await _plugin.zonedSchedule(
      _reviewNotifId,
      'Productivitwo — Résumé du jour',
      'Regarde ce que tu as accompli aujourd\'hui 📊',
      _nextOccurrence(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _reviewChannelId,
          'Résumé quotidien',
          channelDescription: 'Rappel de fin de journée pour le résumé',
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

  static Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
  }
}
