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

/// Depuis Cette semaine : « Planifier la semaine avec Claude ». Remplace le
/// bouton ORION (qui relançait le dernier besoin saisi, sans intention de
/// semaine). Claude propose, l'utilisateur valide dans la conversation.
String planWeekPrompt({
  required DateTime start,
  required int days,
  required List<({String task, String project, DateTime due})> overdue,
  required Map<String, int> capacityMin,
}) {
  String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String dm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  const names = {
    'mon': 'lundi', 'tue': 'mardi', 'wed': 'mercredi', 'thu': 'jeudi',
    'fri': 'vendredi', 'sat': 'samedi', 'sun': 'dimanche',
  };
  final cap = names.keys
      .where((k) => (capacityMin[k] ?? 0) > 0)
      .map((k) => '${names[k]} ${((capacityMin[k] ?? 0) / 60).toStringAsFixed((capacityMin[k] ?? 0) % 60 == 0 ? 0 : 1)} h')
      .join(', ');
  final late = overdue.isEmpty
      ? ''
      : ' Tâches en retard à caser en priorité : ${overdue.map((o) => '« ${o.task} » (${o.project}, échéance ${dm(o.due)})').join(', ')}.'
          ' Si tu en cases une, mets à jour son échéance.';
  return 'Planifie ma semaine avec Productivitwo : appelle plan_week(startDate: "${ymd(start)}") '
      'et propose une répartition des tâches de mes projets sur $days jours, tâche la plus proche de l\'échéance '
      'd\'abord, en respectant ma capacité par jour (${cap.isEmpty ? 'aucune capacité définie' : cap}) '
      'et mes rendez-vous Google Agenda, déjà présents dans les programmes.$late '
      'N\'écris pas toi-même dans Google Agenda : Productivitwo synchronise déjà mon agenda. '
      'Propose d\'abord, puis applique jour par jour avec schedule_day si je valide.';
}

// ─── AUTOMATISER AVEC CLAUDE ─────────────────────────────────────────────────
//
// L'app n'exécute rien : elle ouvre Claude avec la demande « crée une tâche
// planifiée qui… ». Le récurrent vit chez l'utilisateur (son abonnement
// Claude, son connecteur Productivitwo) ; ORION reste l'automatique serveur.

class ClaudeAutomation {
  final String id;
  final String title;
  final String subtitle;
  final String prompt;
  const ClaudeAutomation(
      {required this.id, required this.title, required this.subtitle, required this.prompt});
}

/// Les deux automatisations proposées dans Paramètres. `gcalNative` = l'agenda
/// Google est déjà synchronisé par l'app : on demande à Claude de ne pas
/// écrire lui-même dans l'agenda (sinon doublons).
List<ClaudeAutomation> claudeAutomations({required bool gcalNative}) {
  final noGcal = gcalNative
      ? ' N\'écris pas toi-même dans Google Agenda (syncToCalendar: false) : Productivitwo synchronise déjà mon agenda.'
      : '';
  return [
    ClaudeAutomation(
      id: 'tomorrow',
      title: 'Préparer demain chaque soir',
      subtitle:
          'Une tâche planifiée dans ton Claude appelle Productivitwo tous les soirs à 21 h et pose le programme du lendemain. Tourne sur ton abonnement Claude.',
      prompt: 'Crée une tâche planifiée qui tourne tous les soirs à 21h : prépare mon programme de demain '
          'avec Productivitwo (plan_day pour demain, puis schedule_day). Respecte mes rendez-vous '
          'Google Agenda et mes routines du soir, et ne recrée pas les blocs marqués supprimés.$noGcal',
    ),
    ClaudeAutomation(
      id: 'sunday',
      title: 'Bilan du dimanche',
      subtitle:
          'Chaque dimanche 18 h : lecture de la semaine (generate_weekly_report) et plan de la suivante (plan_week).',
      prompt: 'Crée une tâche planifiée qui tourne chaque dimanche à 18h : fais le bilan de ma semaine '
          'avec Productivitwo (generate_weekly_report), puis prépare la semaine suivante (plan_week) '
          'et envoie-moi le bilan avec le plan proposé.$noGcal',
    ),
  ];
}
