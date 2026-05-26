import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Appelé quand l'utilisateur tape sur une notification.
  /// L'int est l'ID de la notification (ex: 2 = résumé du jour).
  static void Function(int notificationId)? onNotificationTap;

  // Bufferise l'ID si le callback n'est pas encore assigné (race condition background).
  static int? _pendingId;

  static const _channelId = 'routines_daily';
  static const _notifId = 1;
  static const _reviewChannelId = 'review_daily';
  static const _reviewNotifId = 2;
  static const _streakChannelId = 'streak_danger';
  static const _streakNotifId = 3;
  static const _challengeChannelId = 'challenge_daily';
  static const _challengeNotifId = 4;
  static const _midDayChannelId = 'midday_score';
  static const _midDayNotifId = 5;
  // IDs 10–29 réservés aux rappels de blocs
  static const _timerEndChannelId = 'timer_end';
  static const _timerEndNotifId = 30;

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> init() async {
    if (_initialized || !_supported) return;

    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      // flutter_timezone v5+ retourne TimezoneInfo
      final tzName = tzInfo.identifier;
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Fallback UTC si la timezone locale n'est pas trouvée
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();

    await _plugin.initialize(
      InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.id ?? 0;
        if (onNotificationTap != null) {
          onNotificationTap!.call(id);
        } else {
          _pendingId = id;
        }
      },
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

  /// Streak en danger — routines avec streak ≥ 3 non encore faites.
  static Future<void> scheduleStreakReminder({
    int hour = 20,
    int minute = 0,
    required List<String> routineNames,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();
    await _plugin.cancel(_streakNotifId);
    if (routineNames.isEmpty) return;

    final body = routineNames.length == 1
        ? 'Protège ton streak : ${routineNames.first} !'
        : '${routineNames.length} routines à streak à faire ce soir';

    await _plugin.zonedSchedule(
      _streakNotifId,
      'Productivitwo — Streak en danger 🔥',
      body,
      _nextOccurrence(hour, minute),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _streakChannelId, 'Streak en danger',
          channelDescription: 'Rappel pour protéger tes streaks',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: routineNames.length > 1
              ? BigTextStyleInformation(routineNames.map((n) => '• $n').join('\n'))
              : null,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Défi du jour — si non encore fait.
  static Future<void> scheduleChallengeReminder({
    int hour = 16,
    int minute = 0,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();
    await _plugin.cancel(_challengeNotifId);

    await _plugin.zonedSchedule(
      _challengeNotifId,
      'Productivitwo — Défi du jour ⚡',
      'Tu n\'as pas encore relevé ton défi du jour !',
      _nextOccurrence(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _challengeChannelId, 'Défi du jour',
          channelDescription: 'Rappel pour le défi quotidien',
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

  /// Score à mi-journée.
  static Future<void> scheduleMidDayScore({
    int hour = 13,
    int minute = 0,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();
    await _plugin.cancel(_midDayNotifId);

    await _plugin.zonedSchedule(
      _midDayNotifId,
      'Productivitwo — Mi-journée 📊',
      'Jette un œil à ton score du jour',
      _nextOccurrence(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _midDayChannelId, 'Score mi-journée',
          channelDescription: 'Rappel de mi-journée',
          importance: Importance.low,
          priority: Priority.low,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Rappels de blocs — un par bloc avec startHour défini.
  static Future<void> scheduleBlockReminders({
    required List<({String id, String label, int hour, int minute})> blocks,
    int reminderMinutesBefore = 10,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();

    // Annule les anciens rappels de blocs (IDs 10–29)
    for (int i = 10; i < 30; i++) {
      await _plugin.cancel(i);
    }

    for (int i = 0; i < blocks.length && i < 20; i++) {
      final b = blocks[i];
      final totalMinutes = b.hour * 60 + b.minute - reminderMinutesBefore;
      if (totalMinutes < 0) continue;
      final notifHour = totalMinutes ~/ 60;
      final notifMinute = totalMinutes % 60;

      await _plugin.zonedSchedule(
        10 + i,
        'Productivitwo — ${b.label}',
        'Dans $reminderMinutesBefore min',
        _nextOccurrence(notifHour, notifMinute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'block_reminder', 'Rappels de blocs',
            channelDescription: 'Rappel avant le début d\'un bloc',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  /// À appeler juste après avoir assigné [onNotificationTap] pour traiter
  /// un éventuel tap bufferisé (race condition app en background).
  static void drainPending() {
    final id = _pendingId;
    _pendingId = null;
    if (id != null) onNotificationTap?.call(id);
  }

  /// À appeler après le premier frame pour gérer le cas "app terminée lancée
  /// depuis une notification" (getNotificationAppLaunchDetails).
  static Future<void> handleLaunchNotification() async {
    if (!_supported || !_initialized) return;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final id = details!.notificationResponse?.id ?? 0;
      onNotificationTap?.call(id);
    }
  }

  static Future<void> cancelById(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
  }

  /// Minuteur de démarrage — planifie une notification de fin dans [minutes] min.
  static Future<void> scheduleTimerEnd({
    required String activityName,
    required int minutes,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();
    await _plugin.cancel(_timerEndNotifId);

    final fireAt = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    await _plugin.zonedSchedule(
      _timerEndNotifId,
      'Productivitwo ⏱',
      '$activityName — $minutes min écoulées !',
      fireAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _timerEndChannelId, 'Minuteur',
          channelDescription: 'Fin d\'un minuteur de démarrage',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Annule la notification de fin de minuteur en cours.
  static Future<void> cancelTimerEnd() async {
    if (!_supported) return;
    await _plugin.cancel(_timerEndNotifId);
  }
}
