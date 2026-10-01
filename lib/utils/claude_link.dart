import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

/// « Réorganiser avec Claude » : on ouvre LE Claude de l'utilisateur
/// (claude.ai/new?q=…) avec la demande déjà écrite ; il envoie, Claude
/// replanifie via son connecteur Productivitwo. Rien ne passe par nos
/// Cloud Functions ni par une clé API. Logique pure, testable.

Uri claudeNewUri(String prompt) =>
    Uri.https('claude.ai', '/new', {'q': prompt});

String _hm(int min) =>
    '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

/// Contexte commun : rendez-vous agenda (miroirs) à ne pas toucher, fin de
/// journée = fin du dernier bloc (20:45 par défaut).
String _dayContext(List<ScheduleBlock> blocks) {
  final live = blocks.where((b) => b.status != 'deleted').toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final gcal = live
      .where((b) => b.gcalEventId != null && b.status == 'pending')
      .map((b) => '${b.title} ${b.startTime} → ${_hm(blockEndMin(b))}')
      .toList();
  final end = live.isEmpty ? 20 * 60 + 45 : live.map(blockEndMin).reduce((a, b) => a > b ? a : b);
  final agenda = gcal.isEmpty
      ? 'Il n\'y a pas de rendez-vous Google Agenda à protéger.'
      : 'Ne touche pas aux rendez-vous Google Agenda (${gcal.join(' ; ')}).';
  return '$agenda Garde ce qui est fait et recase les blocs restants jusqu\'à ${_hm(end)}. '
      'Propose d\'abord, puis applique avec schedule_day si je valide.';
}

/// Depuis la feuille « chrono hors bloc » : on vient de lancer [activityName]
/// pendant [block] (déjà décalé à [shiftedTo] ou non).
String reorganizeAfterAsidePrompt({
  required String date,
  required DateTime now,
  required ScheduleBlock block,
  required String activityName,
  required List<ScheduleBlock> todayBlocks,
  String? shiftedTo,
}) {
  final nowHm = _hm(now.hour * 60 + now.minute);
  final dur = block.durationMin;
  final what = shiftedTo != null
      ? 'Je viens de décaler « ${block.title} » ($dur min) à $shiftedTo pour une parenthèse « $activityName » en cours.'
      : 'Le bloc « ${block.title} » ($dur min, prévu ${block.startTime}) est en pause : je suis sur « $activityName ».';
  return 'Réorganise la suite de ma journée du $date avec Productivitwo. '
      'Il est $nowHm. $what ${_dayContext(todayBlocks)}';
}

/// Depuis la carte « À traiter » : tâches en retard à replanifier.
String replanOverduePrompt({
  required String date,
  required DateTime now,
  required List<({String task, String project, DateTime due})> overdue,
  required List<ScheduleBlock> todayBlocks,
}) {
  final nowHm = _hm(now.hour * 60 + now.minute);
  final items = overdue
      .map((o) =>
          '« ${o.task} » (${o.project}, échéance ${o.due.day.toString().padLeft(2, '0')}/${o.due.month.toString().padLeft(2, '0')})')
      .join(', ');
  return 'Aide-moi à replanifier mes tâches en retard avec Productivitwo. '
      'Nous sommes le $date, il est $nowHm. En retard : $items. '
      'Pour chacune, propose un créneau réaliste (aujourd\'hui s\'il reste de la place, sinon les prochains jours) '
      'et, si tu la cases, mets à jour son échéance. ${_dayContext(todayBlocks)}';
}
