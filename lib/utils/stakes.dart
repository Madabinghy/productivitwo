import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show focusLabel, isFocusedOn, isStaleFocus, shortDateFr;
import 'package:productivitwo_v1/utils/badge_hunt.dart' show BadgeHunt;
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/interventions.dart' show nextInterventionOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show kDefaultDayStartMin, livedNowMin;
import 'package:productivitwo_v1/utils/reprise.dart' show kRepriseHold;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;

/// « Aujourd'hui en enjeux » (maquette validée 2026-10-30) : tout ce que la
/// journée peut faire gagner ou perdre, ramené à des GESTES (+1 d'une routine,
/// un chrono, un bloc, une action). Une ligne = un geste, avec tout ce qu'il
/// rapporte (série de badge, chasse, objectif, séance, jour visé) ; un même
/// geste n'apparaît qu'une fois. Tri : ce qui se perd ce soir, puis ce qui
/// rapporte le plus pour le moins de temps ; cinq lignes au plus, deux par
/// famille pour les gestes qui ne servent qu'une chose ; le reste se replie.
/// Logique pure : l'UI vit dans Aujourd'hui.

enum StakeGestureKind { routine, activity, block, action }

/// Le geste à faire.
class StakeGesture {
  final String key;
  final StakeGestureKind kind;
  final String title;
  /// Coût estimé en minutes (routine : son minuteur, sinon 5).
  final int costMin;
  final Activity? activity; // routine ou activité-temps
  final ScheduleBlock? block;
  final Project? project;
  final ProjectTask? task;
  final TaskAction? action;
  /// Porteur d'une action PROPRE (sans projet).
  final Activity? owner;
  /// Avancement court du geste lui-même : « 0 / 8 », « reste 1 h 20 ».
  final String? progress;
  const StakeGesture({
    required this.key,
    required this.kind,
    required this.title,
    required this.costMin,
    this.activity,
    this.block,
    this.project,
    this.task,
    this.action,
    this.owner,
    this.progress,
  });
}

enum StakeGainKind {
  /// Une série en cours se perd si rien n'est fait ce soir.
  seriesTonight,
  /// Un palier tombe ce soir.
  tierTonight,
  /// Une série qui démarre ou continue sans risque immédiat (chassée).
  series,
  /// Un badge chassé (journées, temps…) avance.
  hunt,
  /// Un engagement d'objectif en retard sur son rythme.
  objective,
  /// La prépa d'une séance à 7 jours n'est pas finie.
  session,
  /// Une action visée aujourd'hui (ou passée, à re-viser).
  focus,
  /// Une routine du jour pas encore atteinte (rien d'autre en jeu).
  routine,
  /// Une reprise après une coupure de 2 jours ou plus (`reprise.dart`).
  reprise,
  /// Le dimanche, la semaine (contrat à 80 %) se joue ce soir (`held_weeks.dart`).
  week,
}

/// Ce qu'un geste rapporte.
class StakeGain {
  final StakeGainKind kind;
  /// Étiquette courte, affichée sous le geste.
  final String label;
  /// Phrase plus longue pour le geste ouvert.
  final String? detail;
  final bool losesTonight;
  final int weight;
  /// Badge, objectif ou projet porteur (ouvre sa fiche).
  final String? sourceId;
  /// Jauge du gain (fait, après ce geste, total), null sans jauge.
  final ({int done, int after, int total})? gauge;
  const StakeGain({
    required this.kind,
    required this.label,
    this.detail,
    this.losesTonight = false,
    required this.weight,
    this.sourceId,
    this.gauge,
  });
}

/// Un geste et ce qu'il rapporte, noté.
class Stake {
  final StakeGesture gesture;
  final List<StakeGain> gains;
  const Stake(this.gesture, this.gains);

  bool get losesTonight => gains.any((g) => g.losesTonight);

  /// Note : poids des gains + 5 par gain de plus − coût (1 point / 6 min).
  int get score {
    final w = gains.fold<int>(0, (s, g) => s + g.weight);
    return w + 5 * (gains.length - 1) - gesture.costMin ~/ 6;
  }

  /// Famille pour le plafond : « multi » dès qu'un geste sert plusieurs
  /// choses (jamais plafonné), sinon la nature de son seul gain.
  String get family {
    if (gains.length >= 2) return 'multi';
    return switch (gains.first.kind) {
      StakeGainKind.seriesTonight || StakeGainKind.tierTonight || StakeGainKind.series || StakeGainKind.reprise || StakeGainKind.week => 'series',
      StakeGainKind.hunt => 'hunt',
      StakeGainKind.objective => 'objective',
      StakeGainKind.session => 'session',
      StakeGainKind.focus => 'focus',
      StakeGainKind.routine => 'routine',
    };
  }
}

/// Le tableau du jour.
class StakeBoard {
  /// Les lignes EN JEU (cinq au plus).
  final List<Stake> top;
  /// Le reste, derrière « + n autres en jeu ».
  final List<Stake> rest;
  /// Gagné aujourd'hui : séries tenues, chasses tenues, rythmes tenus.
  final List<String> won;
  /// Perdu aujourd'hui : plus rien ne peut sauver la journée pour eux.
  final List<String> lost;
  const StakeBoard({this.top = const [], this.rest = const [], this.won = const [], this.lost = const []});

  int get inPlay => top.length + rest.length;
  bool get isEmpty => inPlay == 0 && won.isEmpty && lost.isEmpty;
  static const empty = StakeBoard();
}

const kStakesTop = 5;
const kStakesFamilyCap = 2;

String _short(String s, [int max = 28]) => s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Construit le tableau du jour. [deck] / [facts] viennent de `BadgeCenter`
/// (null tant que le deck n'est pas calculé : les badges ne comptent pas).
StakeBoard buildStakeBoard({
  required BadgeDeck? deck,
  required TodayFacts facts,
  List<BadgeHunt> hunts = const [],
  List<Project> projects = const [],
  List<Activity> activities = const [],
  int dayStartMin = kDefaultDayStartMin,
  int top = kStakesTop,
  int familyCap = kStakesFamilyCap,
}) {
  final now = facts.now;
  final today = _day(now);
  final gestures = <String, StakeGesture>{};
  final gains = <String, List<StakeGain>>{};
  final won = <String>[];
  final lost = <String>[];
  final routineById = {for (final r in facts.routines) r.activity.id: r};

  void add(StakeGesture g, StakeGain gain) {
    gestures.putIfAbsent(g.key, () => g);
    final list = gains.putIfAbsent(g.key, () => []);
    // Un même porteur ne compte qu'une fois par geste.
    if (gain.sourceId != null && list.any((x) => x.sourceId == gain.sourceId && x.kind == gain.kind)) return;
    list.add(gain);
  }

  StakeGesture routineGesture(RoutineToday r) => StakeGesture(
        key: 'routine:${r.activity.id}',
        kind: StakeGestureKind.routine,
        title: r.activity.name,
        costMin: (r.activity.timerMin ?? 0) > 0 ? r.activity.timerMin! : 5,
        activity: r.activity,
        progress: '${r.done} / ${r.target}',
      );

  StakeGesture blockGesture(ScheduleBlock b) {
    final start = blockStartMin(b);
    final nowMin = livedNowMin(now, dayStartMin);
    final left = nowMin <= start ? b.durationMin : (start + b.durationMin - nowMin).clamp(0, b.durationMin);
    return StakeGesture(
      key: 'block:${b.id}',
      kind: StakeGestureKind.block,
      title: b.title.isEmpty ? 'Bloc ${b.startTime}' : b.title,
      costMin: left == 0 ? b.durationMin : left,
      block: b,
      progress: nowMin < start ? 'à ${b.startTime}' : 'reste ${fmtMin(left)}',
    );
  }

  StakeGesture activityGesture(Activity a, int costMin) => StakeGesture(
        key: 'activity:${a.id}',
        kind: StakeGestureKind.activity,
        title: a.name,
        costMin: costMin,
        activity: a,
        progress: fmtMin(costMin),
      );

  // ── 1. Badges : séries en cours, paliers de ce soir, chasses ────────────────
  if (deck != null) {
    for (final b in deck.badges) {
      final hunted = hunts.any((h) => h.badgeId == b.def.id);
      final series = b.def.family == BadgeFamily.routines;
      final t = badgeToday(b, facts);
      if (t.stake == TodayStake.saved) {
        if ((series && b.value > 0) || hunted) won.add(series ? 'Série ${b.def.name}' : b.def.name);
        continue;
      }
      if (t.stake == TodayStake.lostToday) {
        if (hunted || b.value > 0) lost.add(b.def.name);
        continue;
      }
      if (t.stake != TodayStake.atRisk && t.stake != TodayStake.reachable) continue;
      if (!(series && b.value > 0) && !hunted) continue;
      final next = b.nextTarget;
      final tierTonight = series && next != null && b.value + 1 >= next;
      final v = b.value.toInt();
      for (final item in t.items) {
        StakeGesture? g;
        if (item.kind == GapKind.routine && item.activityId != null) {
          final r = routineById[item.activityId];
          if (r != null) g = routineGesture(r);
        } else if (item.kind == GapKind.block && item.block != null && !series) {
          g = blockGesture(item.block!);
        } else if (item.kind == GapKind.time && item.activityId != null) {
          final a = activities.where((x) => x.id == item.activityId).firstOrNull;
          if (a != null) g = activityGesture(a, item.minutes ?? 30);
        }
        if (g == null) continue;
        if (series) {
          final losing = t.stake == TodayStake.atRisk && v > 0;
          add(
            g,
            StakeGain(
              kind: tierTonight ? StakeGainKind.tierTonight : (losing ? StakeGainKind.seriesTonight : StakeGainKind.series),
              label: tierTonight ? 'palier $next j ce soir' : (losing ? 'série $v j → se perd ce soir' : 'série $v j'),
              detail: losing ? 'Sans coche avant la bascule de journée, la série repart à 0.' : null,
              losesTonight: losing,
              weight: (losing ? 30 + (v > 30 ? 30 : v) : 10) + (tierTonight ? 25 : 0) + (hunted ? 15 : 0),
              sourceId: b.def.id,
              gauge: next == null ? null : (done: v, after: v + 1, total: next),
            ),
          );
        } else {
          add(
            g,
            StakeGain(
              kind: StakeGainKind.hunt,
              label: _short(b.def.name, 22),
              detail: t.chip,
              losesTonight: t.stake == TodayStake.atRisk,
              weight: 20 + (t.stake == TodayStake.atRisk ? 10 : 0),
              sourceId: b.def.id,
            ),
          );
        }
      }
    }
  }

  // ── 1 bis. Reprises : routine coupée 2 jours ou plus, à tenir 3 jours ───────
  if (deck != null) {
    final reprise = deck.byId('reprise');
    final nextTier = reprise?.nextTarget;
    for (final e in deck.reprises.entries) {
      final r = routineById[e.key];
      if (r == null) continue;
      final rp = e.value;
      if (rp.completedToday) {
        won.add('Reprise ${r.activity.name}');
        continue;
      }
      if (r.reached) continue;
      final count = (reprise?.value ?? 0).toInt();
      add(
        routineGesture(r),
        StakeGain(
          kind: StakeGainKind.reprise,
          label: rp.tonight ? 'reprise ce soir' : 'reprise · ${rp.held} / $kRepriseHold',
          detail: rp.tonight
              ? 'Troisième jour tenu après ${rp.gap} jours sans : la reprise compte ce soir${nextTier != null && count + 1 >= nextTier ? ' · palier $nextTier du badge Reprise' : ''}.'
              : 'Après ${rp.gap} jours sans, ${kRepriseHold - rp.held} jour${kRepriseHold - rp.held > 1 ? 's' : ''} d’affilée pour la reprise.',
          weight: rp.tonight ? 22 : 12,
          sourceId: 'reprise',
          gauge: (done: rp.held, after: rp.afterToday, total: kRepriseHold),
        ),
      );
    }
  }

  // ── 1 ter. Le dimanche : la semaine tenue se joue ce soir ───────────────────
  final week = deck?.weeks.thisWeek;
  if (deck != null && week != null && week.pct != null && DateTime.parse(facts.ymd).weekday == DateTime.sunday) {
    final missing = deck.weeks.missing;
    final open = [for (final r in facts.routines) if (!r.reached && deck.weeks.engagedNow.contains(r.activity.id)) r];
    final room = open.fold<int>(0, (s, r) => s + (r.target - r.done));
    if (missing == 0) {
      won.add('Semaine tenue');
    } else if (missing <= room) {
      final streak = deck.weeks.current + 1;
      for (final r in open) {
        add(
          routineGesture(r),
          StakeGain(
            kind: StakeGainKind.week,
            label: 'semaine tenue ce soir',
            detail: 'Encore $missing coche${missing > 1 ? 's' : ''} : la semaine est tenue ($streak d’affilée) et forge une braise.',
            weight: 18,
            sourceId: 'semaines-tenues',
          ),
        );
      }
    }
  }

  // ── 2. Objectifs : engagements en retard sur le rythme, routines engagées ──
  final weekday = now.weekday; // 1 = lundi
  for (final d in facts.objectiveDays) {
    final o = d.objective;
    final name = _short(o.title, 20);
    for (final t in d.times) {
      if (t.weeklyMin <= 0) continue;
      final expected = (t.weeklyMin * weekday / 7).round();
      final behind = expected - t.doneWeekMin;
      if (behind <= 0) {
        if (t.doneTodayMin > 0) won.add('${t.name} · $name');
        continue;
      }
      final a = t.activity;
      if (a == null) continue;
      final cost = behind < 10 ? 10 : (behind > 60 ? 60 : behind);
      add(
        activityGesture(a, cost),
        StakeGain(
          kind: StakeGainKind.objective,
          label: '$name · −${fmtMin(behind)} sur le rythme',
          detail: '${fmtMin(t.doneWeekMin)} / ${fmtMin(expected)} attendues à ce jour · ${fmtMin(t.weeklyMin)} par semaine',
          weight: 15 + (behind ~/ 4 > 15 ? 15 : behind ~/ 4),
          sourceId: o.id,
          gauge: (done: t.doneWeekMin, after: t.doneWeekMin + cost, total: expected),
        ),
      );
    }
    for (final a in d.routines) {
      final r = routineById[a.id];
      if (r == null || r.reached) continue;
      add(routineGesture(r), StakeGain(kind: StakeGainKind.objective, label: name, detail: 'Routine engagée dans « ${o.title} »', weight: 10, sourceId: o.id));
    }
  }

  // ── 3. Séances à 7 jours dont la prépa n'est pas finie ──────────────────────
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    final i = nextInterventionOf(p, today);
    if (i == null) continue;
    final days = i.date.difference(today).inDays;
    if (days < 0 || days > 7) continue;
    final prep = i.prep;
    if (prep == null || prep.status == 'done' || prep.status == 'skipped') continue;
    final open = prep.actions.where((a) => !a.done).toList();
    if (open.isEmpty) continue;
    final a = open.first;
    final doneN = prep.actions.length - open.length;
    add(
      StakeGesture(
        key: 'action:${a.id}',
        kind: StakeGestureKind.action,
        title: a.title,
        costMin: a.estimatedMin ?? 45,
        project: p,
        task: prep,
        action: a,
        progress: a.estimatedMin == null ? null : '≈ ${fmtMin(a.estimatedMin!)}',
      ),
      StakeGain(
        kind: StakeGainKind.session,
        label: '${_short(p.title, 18)} · prépa $doneN / ${prep.actions.length}',
        detail: 'Séance ${days == 0 ? 'aujourd’hui' : days == 1 ? 'demain' : shortDateFr(i.date, today: today)} · « ${i.title} »',
        weight: (25 - 2 * days) < 8 ? 8 : 25 - 2 * days,
        sourceId: p.id,
        gauge: (done: doneN, after: doneN + 1, total: prep.actions.length),
      ),
    );
  }

  // ── 4. Actions visées aujourd'hui (ou à re-viser) ───────────────────────────
  void focusGain(TaskAction a, {Project? p, ProjectTask? t, Activity? owner}) {
    final focused = isFocusedOn(a, today);
    if (!focused && !isStaleFocus(a, today)) return;
    add(
      StakeGesture(
        key: 'action:${a.id}',
        kind: StakeGestureKind.action,
        title: a.title,
        costMin: a.estimatedMin ?? 45,
        project: p,
        task: t,
        action: a,
        owner: owner,
        progress: a.estimatedMin == null ? null : '≈ ${fmtMin(a.estimatedMin!)}',
      ),
      StakeGain(
        kind: StakeGainKind.focus,
        label: focused ? 'visée aujourd’hui' : focusLabel(a.focusDate!, today),
        detail: p == null ? owner?.name : '${p.title}${t == null ? '' : ' › ${t.title}'}',
        weight: focused ? 20 : 8,
        sourceId: 'focus:${a.id}',
      ),
    );
  }

  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in p.tasks) {
      if (t.status == 'done' || t.status == 'skipped') continue;
      for (final a in t.actions) {
        focusGain(a, p: p, t: t);
      }
    }
  }
  for (final act in activities) {
    if (act.deleted) continue;
    for (final a in act.ownActions) {
      focusGain(a, owner: act);
    }
  }

  // ── 5. Routines du jour sans autre enjeu (le bas de la liste) ───────────────
  for (final r in facts.routines) {
    if (r.reached || gestures.containsKey('routine:${r.activity.id}')) continue;
    add(routineGesture(r), StakeGain(kind: StakeGainKind.routine, label: '${r.done} / ${r.target} aujourd’hui', weight: 4));
  }

  // ── Tri, coupe, plafond par famille ─────────────────────────────────────────
  final all = [
    for (final e in gestures.entries)
      if ((gains[e.key] ?? const []).isNotEmpty) Stake(e.value, gains[e.key]!),
  ]..sort((a, b) {
      if (a.losesTonight != b.losesTonight) return a.losesTonight ? -1 : 1;
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final c = a.gesture.costMin.compareTo(b.gesture.costMin);
      return c != 0 ? c : a.gesture.title.compareTo(b.gesture.title);
    });
  final head = <Stake>[];
  final tail = <Stake>[];
  final perFamily = <String, int>{};
  for (final s in all) {
    final f = s.family;
    final capped = f != 'multi' && (perFamily[f] ?? 0) >= familyCap;
    if (head.length < top && !capped) {
      head.add(s);
      perFamily[f] = (perFamily[f] ?? 0) + 1;
    } else {
      tail.add(s);
    }
  }
  return StakeBoard(top: head, rest: tail, won: won, lost: lost);
}

/// Familles de la ligne dépliée, dans l'ordre d'affichage.
const kStakeRestFamilies = [
  ('series', 'SÉRIES'),
  ('hunt', 'CHASSES'),
  ('objective', 'OBJECTIFS'),
  ('session', 'SÉANCES'),
  ('focus', 'ACTIONS VISÉES'),
  ('multi', 'PLUSIEURS GAINS'),
  ('routine', 'ROUTINES DU JOUR'),
];
