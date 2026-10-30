import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Une sonnerie d'alarme sélectionnable. Chaque son existe sous 3 formes :
/// - [asset] : fichier dans assets/audio/ (joué par le package `alarm`, app vivante),
/// - [androidRaw] : nom (sans extension) dans android/.../res/raw/ (notif de secours Android),
/// - [iosCaf] : fichier .caf du bundle Runner (notif de secours iOS).
/// Le son d'un canal Android étant figé à sa création, chaque sonnerie a son
/// propre [androidChannel].
class AlarmRingtone {
  final String key;
  final String label;
  final String asset;
  final String androidRaw;
  final String iosCaf;
  final String androidChannel;
  const AlarmRingtone(this.key, this.label, this.asset, this.androidRaw,
      this.iosCaf, this.androidChannel);
}

/// Sonneries disponibles. Toutes livrées avec leurs fichiers son
/// (assets/audio + res/raw Android + .caf bundle iOS) — bell/chime/digital
/// sont des tons placeholder synthétisés, remplaçables par de vrais sons.
const kAlarmRingtones = <AlarmRingtone>[
  AlarmRingtone('default', 'Alarme classique', 'alarm.wav', 'timer_alarm',
      'timer_alarm.caf', 'timer_end_alarm'),
  AlarmRingtone('bell', 'Cloche', 'bell.wav', 'bell', 'bell.caf', 'alarm_bell'),
  AlarmRingtone(
      'chime', 'Carillon', 'chime.wav', 'chime', 'chime.caf', 'alarm_chime'),
  AlarmRingtone('digital', 'Digital', 'digital.wav', 'digital', 'digital.caf',
      'alarm_digital'),
];

AlarmRingtone ringtoneByKey(String? key) => kAlarmRingtones
    .firstWhere((r) => r.key == key, orElse: () => kAlarmRingtones.first);

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Appelé quand l'utilisateur tape sur une notification : son id et sa
  /// charge utile (`kPayload*`, `block:<ymd>|<id>`, URL…). Seul point d'entrée
  /// des taps : le plugin est partagé (FCM compris), un second `initialize`
  /// écraserait ce routage.
  static void Function(int notificationId, String? payload)? onNotificationTap;

  // Bufferise le tap si le callback n'est pas encore assigné (race condition background).
  static ({int id, String? payload})? _pending;

  static const kPayloadProgram = 'program';
  static const kPayloadPerfect = 'perfect';
  static const kPayloadReview = 'review';
  static const kPayloadToday = 'today';
  static const kPayloadOrion = 'orion';

  /// Le plugin, initialisé une seule fois (FCM l'utilise pour ses affichages).
  static Future<FlutterLocalNotificationsPlugin> plugin() async {
    if (!_initialized) await init();
    return _plugin;
  }

  static const _channelId = 'routines_daily';
  static const _notifId = 1;
  static const _reviewChannelId = 'review_daily';
  static const _reviewNotifId = 2;
  static const _streakChannelId = 'streak_danger';
  static const _streakNotifId = 3;
  // 4 (Défi du jour) et 5 (Score mi-journée) : retirés le 2026-10-30,
  // annulés au démarrage. 10–29 : anciens rappels de blocs (annulés).
  // Canal d'alarme : un par sonnerie (le son d'un canal Android est figé à sa
  // création) — voir AlarmRingtone.androidChannel + _alarmDetails.
  static const _timerEndNotifId = 30;
  static const _coupEndNotifId = 31;
  // Défis programmés (ids 40000 / 50000 / 60000 dérivés du block.id) : plus
  // armés depuis le 2026-10-30, seulement annulés (`cancelChallengeAll`).

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
          onNotificationTap!.call(id, response.payload);
        } else {
          _pending = (id: id, payload: response.payload);
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
  /// Matin, « Ta journée » (2026-10-30) : [body] = `morningDigest` du jour
  /// de la prochaine occurrence, recalculé à chaque ouverture / changement.
  static Future<void> scheduleDailyReminder({
    int hour = 9,
    int minute = 0,
    required String body,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();

    await _plugin.cancel(_notifId);

    await _plugin.zonedSchedule(
      _notifId,
      'Ta journée',
      body,
      _nextOccurrence(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Ta journée (matin)',
          channelDescription: 'Ce que la journée porte : blocs, routines, actions visées',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: kPayloadProgram,
    );
  }

  /// Jour (local) de la prochaine occurrence de [hour]:[minute].
  static DateTime nextOccurrenceDay(int hour, int minute) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(now.year, now.month, now.day, hour, minute).isAfter(now) ? today : today.add(const Duration(days: 1));
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
      payload: kPayloadReview,
    );
  }

  /// Soir, « Journée parfaite : il manque n » (2026-10-30, remplace « Streak en
  /// danger », même id 3) : PONCTUELLE, seulement aujourd'hui et seulement
  /// s'il reste quelque chose — jamais un texte daté. Null = annulée.
  static Future<void> scheduleEveningPerfect({
    int hour = 20,
    int minute = 0,
    required ({String title, String body})? digest,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();
    await _plugin.cancel(_streakNotifId);
    if (digest == null) return;
    final now = tz.TZDateTime.now(tz.local);
    final at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) return;
    await _plugin.zonedSchedule(
      _streakNotifId,
      digest.title,
      digest.body,
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _streakChannelId, 'Ce soir · journée parfaite',
          channelDescription: 'Ce qu\'il manque pour une journée parfaite, séries en jeu',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: kPayloadPerfect,
    );
  }

  /// IDs des rappels des blocs du programme (aujourd'hui et demain).
  static const _blockAlertBase = 200;
  static const _blockAlertMax = 60;

  /// Rappels des blocs du programme (2026-10-30), [minutesBefore] avant leur
  /// début : notifications ponctuelles, replanifiées à chaque ouverture /
  /// changement. Tap = la source du bloc (charge utile `block:<ymd>|<id>`).
  /// Annule aussi les anciens rappels de l'ancien modèle de blocs (10–29).
  static Future<void> scheduleBlockAlerts(
    List<({String ymd, String id, String title, DateTime start, int durationMin})> blocks, {
    int minutesBefore = 5,
  }) async {
    if (!_supported) return;
    if (!_initialized) await init();
    for (var i = 10; i < 30; i++) {
      await _plugin.cancel(i);
    }
    for (var i = 0; i < _blockAlertMax; i++) {
      await _plugin.cancel(_blockAlertBase + i);
    }
    final now = DateTime.now();
    final upcoming = [for (final b in blocks) if (b.start.subtract(Duration(minutes: minutesBefore)).isAfter(now)) b]
      ..sort((a, b) => a.start.compareTo(b.start));
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    for (var i = 0; i < upcoming.length && i < _blockAlertMax; i++) {
      final b = upcoming[i];
      final end = b.start.add(Duration(minutes: b.durationMin));
      await _plugin.zonedSchedule(
        _blockAlertBase + i,
        b.title,
        'Dans $minutesBefore min · ${hm(b.start)} → ${hm(end)}',
        tz.TZDateTime.from(b.start.subtract(Duration(minutes: minutesBefore)), tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'block_reminder', 'Rappels de blocs',
            channelDescription: 'Rappel juste avant le début d\'un bloc du programme',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'block:${b.ymd}|${b.id}',
      );
    }
  }

  /// À appeler juste après avoir assigné [onNotificationTap] pour traiter
  /// un éventuel tap bufferisé (race condition app en background).
  static void drainPending() {
    final p = _pending;
    _pending = null;
    if (p != null) onNotificationTap?.call(p.id, p.payload);
  }

  /// À appeler après le premier frame pour gérer le cas "app terminée lancée
  /// depuis une notification" (getNotificationAppLaunchDetails).
  static Future<void> handleLaunchNotification() async {
    if (!_supported || !_initialized) return;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final r = details!.notificationResponse;
      onNotificationTap?.call(r?.id ?? 0, r?.payload);
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

  /// Détails de notification « alarme » (son fort ~30s, plein écran, joue même
  /// app tuée) pour une [AlarmRingtone] donnée. Chaque sonnerie a son propre
  /// canal Android (le son d'un canal est figé à sa création).
  static NotificationDetails _alarmDetails(AlarmRingtone r, String desc) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        r.androidChannel, 'Alarme — ${r.label}',
        channelDescription: desc,
        importance: Importance.max,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound(r.androidRaw),
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(sound: r.iosCaf),
    );
  }

  /// Minuteur de démarrage — planifie une notification de fin dans [minutes] min.
  static Future<void> scheduleTimerEnd({
    required String activityName,
    required int minutes,
    AlarmRingtone? ringtone,
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
      _alarmDetails(ringtone ?? kAlarmRingtones.first,
          'Fin d\'un minuteur de démarrage'),
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

  /// Fin d'un coup de Guérilla / Offensive : filet de secours si l'app est tuée.
  static Future<void> scheduleCoupEnd({required String title, required String body, required DateTime at, AlarmRingtone? ringtone}) async {
    if (!_supported) return;
    if (!_initialized) await init();
    await _plugin.cancel(_coupEndNotifId);
    if (!at.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      _coupEndNotifId,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      _alarmDetails(ringtone ?? kAlarmRingtones.first, 'Fin d\'un coup de guérilla ou d\'offensive'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelCoupEnd() async {
    if (!_supported) return;
    await _plugin.cancel(_coupEndNotifId);
  }

  // ── Challenge programmé ─────────────────────────────────────────────────────

  /// IDs de notification déterministes pour un bloc-défi donné (pour pouvoir
  /// annuler quand le bloc est supprimé). atTime = alarme à l'heure, reminder
  /// = rappel en amont.
  static ({int atTime, int reminder, int reminder2}) challengeNotifIds(
      String blockId) {
    final h = blockId.hashCode & 0x7fff;
    return (atTime: 40000 + h, reminder: 50000 + h, reminder2: 60000 + h);
  }

  /// Annule toutes les notifications (alarme + rappels) d'un défi programmé.
  static Future<void> cancelChallengeAll(String blockId) async {
    if (!_supported) return;
    final ids = challengeNotifIds(blockId);
    await _plugin.cancel(ids.atTime);
    await _plugin.cancel(ids.reminder);
    await _plugin.cancel(ids.reminder2);
  }
}
