import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/notifications.dart';

/// Alarme de fin de coup (Guérilla / Offensive, 2026-10-30) : même sonnerie que
/// le minuteur d'une routine (réglage « Son de l'alarme »), qui sonne téléphone
/// en veille ou app en arrière-plan, sans boucler ; filet de secours =
/// notification programmée si l'app est tuée. Deux ids qui alternent : la fin
/// d'un coup ne coupe pas la sonnerie du précédent quand le suivant démarre.
class CoupAlarm {
  static const _ids = [43, 44];
  static var _slot = 0;

  static Future<void> schedule(AppLogic logic, {required DateTime endsAt, required String title, required String body}) async {
    if (kIsWeb) return;
    _slot = 1 - _slot;
    final id = _ids[_slot];
    final ringtone = ringtoneByKey(logic.state.alarmSound);
    try {
      await Alarm.stop(id);
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: endsAt,
          assetAudioPath: 'assets/audio/${ringtone.asset}',
          loopAudio: false,
          vibrate: true,
          warningNotificationOnKill: false,
          androidFullScreenIntent: false,
          volumeSettings: VolumeSettings.fade(volume: 0.9, fadeDuration: const Duration(seconds: 1), volumeEnforced: false),
          notificationSettings: NotificationSettings(title: title, body: body, stopButton: 'OK'),
        ),
      );
    } catch (_) {}
    await NotificationService.scheduleCoupEnd(title: title, body: body, at: endsAt, ringtone: ringtone);
  }

  /// Annule les alarmes des coups (fait, passé, arrêté) ; `all: false` =
  /// seulement celle du coup en cours (on rajoute du temps).
  static Future<void> cancel({bool all = true}) async {
    if (kIsWeb) return;
    try {
      if (all) {
        for (final id in _ids) {
          await Alarm.stop(id);
        }
      } else {
        await Alarm.stop(_ids[_slot]);
      }
    } catch (_) {}
    await NotificationService.cancelCoupEnd();
  }
}
