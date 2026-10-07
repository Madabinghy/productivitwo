import 'package:productivitwo_v1/models.dart';

// Port Dart de `functions/src/interventions.ts` (lot 2 web, 2026-10) : l'app
// web crée une séance sans passer par le MCP. Même grammaire que le serveur :
// 📝 Préparer (J-7 → J-1) · 🎯 jalon le jour J (« Dérouler la séance ») ·
// ✅ Clôturer (J → J+2), modèles dans `data/meta.interventionTemplates`.

class InterventionTemplateAction {
  final String title;
  final List<String> contexts;
  final int? estimatedMin;
  const InterventionTemplateAction(this.title, {this.contexts = const [], this.estimatedMin});

  static InterventionTemplateAction from(dynamic j) {
    if (j is String) return InterventionTemplateAction(j);
    final m = (j as Map?) ?? const {};
    final ctx = (m['contexts'] as List?)?.whereType<String>().toList() ??
        (m['context'] is String ? [m['context'] as String] : const <String>[]);
    return InterventionTemplateAction(
      (m['title'] ?? '').toString(),
      contexts: ctx,
      estimatedMin: (m['estimatedMin'] as num?)?.toInt(),
    );
  }

  TaskAction toAction() => TaskAction(
        title: title,
        contexts: contexts.isEmpty ? null : List.of(contexts),
        estimatedMin: estimatedMin,
      );
}

class InterventionTemplate {
  final String id;
  final String name;
  final String? startTime;
  final String? endTime;
  final String? place;
  final String? sessionContext;
  final int prepDaysBefore;
  final int prepEndDaysBefore;
  final List<InterventionTemplateAction> prepActions;
  final int closureDaysAfter;
  final List<InterventionTemplateAction> closureActions;

  const InterventionTemplate({
    required this.id,
    required this.name,
    this.startTime,
    this.endTime,
    this.place,
    this.sessionContext,
    this.prepDaysBefore = 7,
    this.prepEndDaysBefore = 1,
    required this.prepActions,
    this.closureDaysAfter = 2,
    required this.closureActions,
  });

  static InterventionTemplate from(Map j) {
    final prep = (j['prep'] as Map?) ?? const {};
    final closure = (j['closure'] as Map?) ?? const {};
    int toInt(dynamic v, int d) => v is num && v >= 0 ? v.round() : d;
    return InterventionTemplate(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? 'Modèle').toString(),
      startTime: j['startTime'] as String?,
      endTime: j['endTime'] as String?,
      place: j['place'] as String?,
      sessionContext: j['sessionContext'] as String?,
      prepDaysBefore: toInt(prep['daysBefore'], 7),
      prepEndDaysBefore: toInt(prep['endDaysBefore'], 1),
      prepActions: (prep['actions'] as List?)?.map(InterventionTemplateAction.from).toList() ??
          kDefaultInterventionTemplate.prepActions,
      closureDaysAfter: toInt(closure['daysAfter'], 2),
      closureActions:
          (closure['actions'] as List?)?.map(InterventionTemplateAction.from).toList() ??
              kDefaultInterventionTemplate.closureActions,
    );
  }
}

const kDefaultInterventionTemplate = InterventionTemplate(
  id: 'default',
  name: 'Séance (défaut)',
  prepActions: [
    InterventionTemplateAction('Adapter au bilan précédent', contexts: ['@ordinateur'], estimatedMin: 15),
    InterventionTemplateAction('Produire les supports', contexts: ['@ordinateur'], estimatedMin: 45),
    InterventionTemplateAction('Fiche de séquence', contexts: ['@ordinateur'], estimatedMin: 15),
    InterventionTemplateAction('Imprimer', contexts: ['@impression'], estimatedMin: 10),
  ],
  closureActions: [
    InterventionTemplateAction('Remplir la fiche de séquence (réalisé + bilan)',
        contexts: ['@ordinateur'], estimatedMin: 15),
    InterventionTemplateAction('Noter le report (ce qui n\'a pas été fait)',
        contexts: ['@ordinateur'], estimatedMin: 5),
    InterventionTemplateAction('Déposer les documents', contexts: ['@ordinateur'], estimatedMin: 10),
  ],
);

/// Modèles lus dans `data/meta.interventionTemplates` (+ le défaut en tête).
List<InterventionTemplate> parseInterventionTemplates(dynamic raw) => [
      kDefaultInterventionTemplate,
      ...((raw as List?) ?? const []).whereType<Map>().map(InterventionTemplate.from),
    ];

const _kDays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _kMonths = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String interventionDayLabel(DateTime d) => '${_kDays[d.weekday - 1]} ${d.day} ${_kMonths[d.month - 1]}';

/// « 13:15 » → « 13h15 ».
String hmFr(String hm) {
  final p = hm.split(':');
  return p.length == 2 ? '${int.tryParse(p[0]) ?? p[0]}h${p[1]}' : hm;
}

int hmToMin(String hm) {
  final p = hm.split(':');
  if (p.length != 2) return -1;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  return h == null || m == null ? -1 : h * 60 + m;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Phase dont la plage couvre la date (la plus courte si plusieurs).
ProjectPhase? phaseForDate(List<ProjectPhase> phases, DateTime date) {
  final d = _day(date);
  final hits = phases
      .where((p) => !_day(p.startDate).isAfter(d) && !_day(p.endDate).isBefore(d))
      .toList()
    ..sort((a, b) => a.endDate.difference(a.startDate).compareTo(b.endDate.difference(b.startDate)));
  return hits.firstOrNull;
}

String prepTitle(String title) => '📝 Préparer — $title';
String sessionTitle(String title, DateTime date) => '🎯 ${interventionDayLabel(date)} — $title';
String closureTitle(String title) => '✅ Clôturer — $title';

/// Les trois tâches d'une séance, taguées, prêtes à être ajoutées au projet.
({ProjectTask prep, ProjectTask session, ProjectTask closure}) buildInterventionTasks(
  ProjectIntervention i,
  InterventionTemplate tpl, {
  List<ProjectPhase> phases = const [],
  List<String> steps = const [],
}) {
  final date = _day(i.date);
  final phase = phaseForDate(phases, date);
  int sum(List<InterventionTemplateAction> as) =>
      as.fold(0, (n, a) => n + (a.estimatedMin ?? 0));
  ProjectTask base(String title, DateTime start, DateTime end, String role) => ProjectTask(
        title: title,
        startDate: start,
        endDate: end,
        phaseId: phase?.id,
        groupLabel: i.title,
        interventionId: i.id,
        interventionRole: role,
      );
  final prep = base(prepTitle(i.title), date.subtract(Duration(days: tpl.prepDaysBefore < 1 ? 1 : tpl.prepDaysBefore)),
      date.subtract(Duration(days: tpl.prepEndDaysBefore < 0 ? 0 : tpl.prepEndDaysBefore)), 'prep')
    ..actions = tpl.prepActions.map((a) => a.toAction()).toList()
    ..estimatedMin = sum(tpl.prepActions) == 0 ? null : sum(tpl.prepActions);
  final session = base(sessionTitle(i.title, date), date, date, 'session')
    ..isMilestone = true
    ..barLabel = 'SÉANCE'
    ..actions = [
      TaskAction(
        title: 'Dérouler la séance (${hmFr(i.startTime)}–${hmFr(i.endTime)})',
        contexts: tpl.sessionContext == null ? null : [tpl.sessionContext!],
        estimatedMin: i.slotMin == 0 ? null : i.slotMin,
        checklist: [for (final s in steps) if (s.trim().isNotEmpty) ChecklistItem(title: s.trim())],
      ),
    ];
  final closure = base(closureTitle(i.title), date,
      date.add(Duration(days: tpl.closureDaysAfter < 0 ? 0 : tpl.closureDaysAfter)), 'closure')
    ..actions = tpl.closureActions.map((a) => a.toAction()).toList()
    ..estimatedMin = sum(tpl.closureActions) == 0 ? null : sum(tpl.closureActions);
  return (prep: prep, session: session, closure: closure);
}

final _carryOverAction = RegExp(r'adapter au bilan', caseSensitive: false);

/// Séance suivante (planifiée, datée après [from]) dans le projet.
ProjectIntervention? nextInterventionAfter(Project p, ProjectIntervention from) {
  final later = p.interventions
      .where((i) => i.id != from.id && i.status != 'cancelled' && _day(i.date).isAfter(_day(from.date)))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return later.firstOrNull;
}

/// Bilan N → prépa N+1 : les points à reprendre deviennent la checklist de
/// l'action « Adapter au bilan précédent » de la séance suivante (créée si
/// absente ; fusion sans doublon de titre). Retourne la séance alimentée.
ProjectIntervention? applyCarryOver(Project p, ProjectIntervention from, List<String> items) {
  final clean = items.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (clean.isEmpty) return null;
  final next = nextInterventionAfter(p, from);
  if (next == null) return null;
  final prep = p.tasks
      .where((t) => t.interventionId == next.id && t.interventionRole == 'prep')
      .firstOrNull;
  if (prep == null) return null;
  var action = prep.actions.where((a) => _carryOverAction.hasMatch(a.title)).firstOrNull;
  if (action == null) {
    action = TaskAction(title: 'Adapter au bilan précédent', contexts: ['@ordinateur'], estimatedMin: 15);
    prep.actions.insert(0, action);
  }
  final have = action.checklist.map((c) => c.title.trim().toLowerCase()).toSet();
  for (final s in clean) {
    if (have.add(s.toLowerCase())) action.checklist.add(ChecklistItem(title: s));
  }
  if (action.done && action.checklist.any((c) => !c.done)) {
    action.done = false;
    action.doneAt = null;
  }
  return next;
}
