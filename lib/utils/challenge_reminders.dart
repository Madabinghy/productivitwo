import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/notifications.dart';

/// Recalage des notifications locales d'un bloc-défi 🔥.
///
/// Un défi programmé porte une alarme « à l'heure » + jusqu'à 2 rappels en
/// amont (block.reminders, ISO). Ces notifications sont posées à la création
/// (main._programChallenge) mais un DÉPLACEMENT (sheet, timeline, renégociation)
/// ne les recalait pas : l'alarme partait à l'ancienne heure. Tous les chemins
/// de déplacement passent désormais ici. 0 LLM.

/// Annule alarme + rappels si le bloc est un défi (no-op sinon).
/// À appeler quand le défi quitte l'état pending : fait, sauté/reporté, supprimé.
Future<void> cancelChallengeNotifications(ScheduleBlock block) async {
  if (!block.challenge) return;
  await NotificationService.cancelChallengeAll(block.id);
}

/// Recale alarme + rappels sur la nouvelle heure du bloc (no-op si pas un défi).
///
/// À appeler APRÈS que [block.startTime] a été mis à jour, avec l'ancienne
/// heure en [oldStartTime]. Chaque rappel conserve son DÉCALAGE d'origine par
/// rapport au début (« 15 min avant » reste 15 min avant) ; un rappel dont la
/// nouvelle heure est déjà passée est simplement abandonné (scheduleChallengeAt
/// ignore le passé). La liste block.reminders est réécrite en Firestore pour
/// rester la vérité de ce qui est armé.
Future<void> rescheduleChallengeNotifications({
  required ScheduleBlock block,
  required String date, // YYYY-MM-DD du bloc
  required String oldStartTime, // HH:mm avant déplacement
  String? alarmSoundKey,
}) async {
  if (!block.challenge) return;
  if (block.status != 'pending') {
    // Fait/sauté/supprimé → plus rien à armer.
    await NotificationService.cancelChallengeAll(block.id);
    return;
  }

  DateTime? at(String hm) {
    final d = date.split('-');
    final p = hm.split(':');
    final y = int.tryParse(d.isNotEmpty ? d[0] : '');
    final mo = int.tryParse(d.length > 1 ? d[1] : '');
    final da = int.tryParse(d.length > 2 ? d[2] : '');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '');
    final mi = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    if (y == null || mo == null || da == null || h == null) return null;
    return DateTime(y, mo, da, h, mi);
  }

  final newAt = at(block.startTime);
  if (newAt == null) return;

  await NotificationService.cancelChallengeAll(block.id);

  final ids = NotificationService.challengeNotifIds(block.id);
  await NotificationService.scheduleChallengeAt(
    id: ids.atTime,
    when: newAt,
    title: block.title,
    body: '${block.durationMin} min — c\'est le moment 💪',
    alarm: true,
    ringtone: ringtoneByKey(alarmSoundKey),
  );

  final oldAt = at(oldStartTime);
  if (block.reminders.isEmpty || oldAt == null) return;

  final reminderIds = NotificationService.challengeReminderIds(block.id);
  final name = block.title.replaceFirst('🔥 Défi : ', '');
  final updated = <String>[];
  for (var i = 0; i < block.reminders.length && i < reminderIds.length; i++) {
    final oldRem = DateTime.tryParse(block.reminders[i]);
    if (oldRem == null) continue;
    final rem = newAt.subtract(oldAt.difference(oldRem));
    updated.add(rem.toIso8601String());
    await NotificationService.scheduleChallengeAt(
      id: reminderIds[i],
      when: rem,
      title: 'Défi prévu : $name',
      body: 'À ${block.startTime} • ${block.durationMin} min',
      alarm: false,
    );
  }
  if (updated.join('|') != block.reminders.join('|')) {
    block.reminders = updated;
    await FirestoreSync().updateBlockReminders(date, block.id, updated);
  }
}
