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
  // Défis programmés retirés des notifications (2026-10-30) : un bloc-défi
  // déplacé ne réarme plus d'alarme, il annule ce qui restait.
  if (!block.challenge) return;
  await NotificationService.cancelChallengeAll(block.id);
}
