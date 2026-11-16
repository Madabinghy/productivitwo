import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/meal_day.dart' show isBalancedMealRoutine;
import 'package:productivitwo_v1/utils/modules.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName;
import 'package:productivitwo_v1/utils/sport_stats.dart' show isSportDomainName;

/// Le parcours (lot 3 des modules, 2026-11-16) : l'app propose UN module quand un signal montre que la
/// personne est prête. Stockage dans `data/meta.modules` à côté de `on` : `since` (début du parcours),
/// `pending` (module proposé, en attente de réponse), `lastProposed` (jour de la dernière proposition),
/// `declined {clé: 'never' | 'later:YYYY-MM-DD'}`.
const kProposalGapDays = 7;
const kLaterDays = 30;

class ModuleJourney {
  final String? since;
  final AppModule? pending;
  final String? lastProposed;
  final Map<AppModule, String> declined;
  /// « Repartir comme un débutant » (lot 4) : les modules allumés avant le redémarrage, null = pas de redémarrage.
  final List<AppModule>? before;
  const ModuleJourney({this.since, this.pending, this.lastProposed, this.declined = const {}, this.before});

  static ModuleJourney from(dynamic raw) {
    if (raw is! Map) return const ModuleJourney();
    final declined = <AppModule, String>{};
    final d = raw['declined'];
    if (d is Map) {
      d.forEach((k, v) {
        final m = moduleOfKey('$k');
        if (m != null && v is String) declined[m] = v;
      });
    }
    final p = raw['pending'];
    final b = raw['before'];
    return ModuleJourney(
      before: b is List ? [for (final k in b) if (moduleOfKey('$k') case final m?) m] : null,
      since: raw['since'] is String ? raw['since'] as String : null,
      pending: p is String ? moduleOfKey(p) : null,
      lastProposed: raw['lastProposed'] is String ? raw['lastProposed'] as String : null,
      declined: declined,
    );
  }

  bool sameAs(ModuleJourney o) =>
      since == o.since &&
      pending == o.pending &&
      lastProposed == o.lastProposed &&
      declined.length == o.declined.length &&
      (before?.join(',') ?? '-') == (o.before?.join(',') ?? '-') &&
      declined.entries.every((e) => o.declined[e.key] == e.value);
}

/// Ce que l'app a observé, compté depuis le début du parcours (`since`).
class JourneyFacts {
  /// Jours avec au moins un chrono ou une coche.
  final int usageDays;
  /// Sur les 7 derniers jours, ceux avec au moins un chrono.
  final int activeDaysLast7;
  /// Sur les 7 derniers jours, ceux qui ont commencé en Flemme.
  final int lowDaysLast7;
  /// Sur les 14 derniers jours, ceux où au moins 70 % des routines quotidiennes ont été tenues.
  final int routineHeldDays14;
  /// Un objectif actif avec un engagement, créé il y a au moins 14 jours.
  final bool settledObjective;
  final int sleepChronos;
  final int sportSessions;
  /// Une routine Repas / Cuisiner tenue 7 jours sur les 7 derniers.
  final bool mealRoutineHeld;
  /// Un domaine ou un objectif d'argent.
  final bool moneyGoal;
  const JourneyFacts({
    this.usageDays = 0,
    this.activeDaysLast7 = 0,
    this.lowDaysLast7 = 0,
    this.routineHeldDays14 = 0,
    this.settledObjective = false,
    this.sleepChronos = 0,
    this.sportSessions = 0,
    this.mealRoutineHeld = false,
    this.moneyGoal = false,
  });
}

/// Le signal d'un module (null = jamais proposé par l'app) et la phrase de la proposition.
({bool ready, String why, String pitch})? moduleSignal(AppModule m, JourneyFacts f) {
  switch (m) {
    case AppModule.planning:
      return (
        ready: f.usageDays >= 7 && f.activeDaysLast7 >= 5,
        why: '${f.activeDaysLast7} jours sur 7 avec un chrono',
        pitch: 'Tu avances chaque jour. Envie de poser ta journée la veille ?',
      );
    case AppModule.modes:
      return (
        ready: f.lowDaysLast7 >= 3,
        why: '${f.lowDaysLast7} journées en Flemme cette semaine',
        pitch: "Les jours sans élan, la Guérilla te remet debout en 5 minutes.",
      );
    case AppModule.game:
      return (
        ready: f.routineHeldDays14 >= 14,
        why: '14 jours de routines tenues',
        pitch: 'Tes séries tiennent. Envie de les voir compter ?',
      );
    case AppModule.seasons:
      return (
        ready: f.settledObjective,
        why: 'un objectif engagé depuis 2 semaines',
        pitch: 'Donne une période à tes objectifs, et fais le bilan à la fin.',
      );
    case AppModule.sleep:
      return (ready: f.sleepChronos >= 3, why: '${f.sleepChronos} nuits chronométrées', pitch: 'Tu suis tes nuits : vois ta dette et ton coucher.');
    case AppModule.sport:
      return (ready: f.sportSessions >= 3, why: '${f.sportSessions} séances chronométrées', pitch: 'Tes séances, ta semaine, tes progrès.');
    case AppModule.kitchen:
      return (ready: f.mealRoutineHeld, why: 'ta routine Repas tenue 7 jours', pitch: 'Planifie tes repas et ta liste de courses.');
    case AppModule.finances:
      return (ready: f.moneyGoal, why: "un domaine ou un objectif d'argent", pitch: 'Note tes dépenses en cinq secondes.');
    case AppModule.analysis:
      return (ready: f.usageDays >= 30, why: '30 jours de données', pitch: 'Un mois de données : vois où passe ton temps.');
    case AppModule.freedom:
    case AppModule.trainer:
    case AppModule.assistant:
      return null;
  }
}

int _daysBetween(String a, String b) => DateTime.parse(b).difference(DateTime.parse(a)).inDays;

/// Le module à proposer aujourd'hui, ou null. Une proposition en attente reste jusqu'à sa réponse ;
/// sinon une au plus tous les [kProposalGapDays] jours, jamais quand [blocked] (Le minimum, une remontée,
/// le lendemain d'une journée difficile), jamais un module allumé ou refusé.
AppModule? nextProposal({
  required ModuleSettings settings,
  required ModuleJourney journey,
  required JourneyFacts facts,
  required String today,
  bool blocked = false,
}) {
  final p = journey.pending;
  if (p != null && !settings.isOn(p)) return p;
  if (blocked) return null;
  final last = journey.lastProposed;
  if (last != null && _daysBetween(last, today) < kProposalGapDays) return null;
  for (final i in kModules) {
    if (settings.isOn(i.module)) continue;
    final d = journey.declined[i.module];
    if (d == 'never') continue;
    if (d != null && d.startsWith('later:') && _daysBetween(d.substring(6), today) < 0) continue;
    final s = moduleSignal(i.module, facts);
    if (s != null && s.ready) return i.module;
  }
  return null;
}

String laterUntil(String today) => DateTime.parse(today).add(const Duration(days: kLaterDays)).toIso8601String().substring(0, 10);

final _money = RegExp(r'financ|budget|argent|compta|épargne|epargne', caseSensitive: false);

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Les faits du parcours, comptés depuis [since] (début du parcours ; null = tout l'historique).
JourneyFacts journeyFactsOf({
  required List<Session> sessions,
  required List<HabitHit> hits,
  required List<Activity> activities,
  required List<Domain> domains,
  required List<MoodMark> moods,
  List<StrategicObjective> objectives = const [],
  required DateTime now,
  required int dayStartMin,
  String? since,
}) {
  final today = livedDate(now, dayStartMin);
  String dayOf(DateTime t) => _ymd(livedDate(t, dayStartMin));
  bool inJourney(String ymd) => since == null || ymd.compareTo(since) >= 0;
  final last7 = {for (var i = 0; i < 7; i++) _ymd(today.subtract(Duration(days: i)))};
  final last14 = [for (var i = 0; i < 14; i++) _ymd(today.subtract(Duration(days: i)))];
  final live = sessions.where((s) => !s.deleted).toList();
  final byId = {for (final a in activities) a.id: a};
  final domainName = {for (final d in domains) d.id: d.name};

  final usage = <String>{};
  final active7 = <String>{};
  for (final s in live) {
    final d = dayOf(s.startAt);
    if (!inJourney(d)) continue;
    usage.add(d);
    if (last7.contains(d)) active7.add(d);
  }
  final hitsByDay = <String, Map<String, int>>{};
  for (final h in hits) {
    final d = dayOf(h.ts);
    if (inJourney(d)) usage.add(d);
    final m = hitsByDay[d] ??= {};
    m[h.habitId] = (m[h.habitId] ?? 0) + 1;
  }
  final low7 = {for (final m in moods) if (m.lowElan && last7.contains(m.ymd) && inJourney(m.ymd)) m.ymd};

  final daily = activities.where((a) => !a.deleted && a.isHabit && a.habitFreq == HabitFreq.daily).toList();
  var held14 = 0;
  for (final d in last14) {
    if (!inJourney(d)) continue;
    final due = daily.where((a) => _ymd(a.createdAt).compareTo(d) <= 0).toList();
    if (due.isEmpty) continue;
    final got = hitsByDay[d] ?? const {};
    final ok = due.where((a) => (got[a.id] ?? 0) >= ((a.habitTarget ?? 1) < 1 ? 1 : (a.habitTarget ?? 1))).length;
    if (ok / due.length >= .7) held14++;
  }

  var sleep = 0, sport = 0;
  for (final s in live) {
    if (!inJourney(dayOf(s.startAt))) continue;
    final a = byId[s.activityId];
    if (a == null) continue;
    if (isSleepName(a.name)) {
      sleep++;
    } else if (isSportDomainName(domainName[a.domainId] ?? '') && (s.endAt ?? now).difference(s.startAt).inMinutes >= 10) {
      sport++;
    }
  }
  final meal = daily.where(isBalancedMealRoutine).any((a) => last7.every((d) => (hitsByDay[d]?[a.id] ?? 0) > 0));
  final settled = objectives.any((o) =>
      o.status == 'active' &&
      (o.timeCommitments.isNotEmpty || o.routineCommitments.isNotEmpty) &&
      now.difference(o.createdAt).inDays >= 14);
  final money = domains.any((d) => !d.deleted && _money.hasMatch(d.name)) ||
      objectives.any((o) => o.status == 'active' && _money.hasMatch(o.title));
  return JourneyFacts(
    usageDays: usage.length,
    activeDaysLast7: active7.length,
    lowDaysLast7: low7.length,
    routineHeldDays14: held14,
    settledObjective: settled,
    sleepChronos: sleep,
    sportSessions: sport,
    mealRoutineHeld: meal,
    moneyGoal: money,
  );
}

/// Le réglage écrit par « Repartir comme un débutant » : le cœur seul, le parcours à zéro à partir de
/// [today], les modules d'avant gardés en photo dans `before` (pour « Retrouver mon app complète »).
Map<String, dynamic> beginnerModules(ModuleSettings current, String today) => {
      'v': 1,
      'on': <String>[],
      'since': today,
      'before': [for (final i in kModules) if (current.isOn(i.module)) i.key],
    };

/// Le réglage qui rend l'app d'avant le redémarrage ; le parcours repart de rien.
Map<String, dynamic> restoredModules(ModuleJourney j) => {
      'v': 1,
      'on': [for (final m in j.before ?? const <AppModule>[]) moduleInfo(m).key],
    };
