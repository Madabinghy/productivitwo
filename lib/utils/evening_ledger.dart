import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/interventions.dart' show nextInterventionOf;
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/embers.dart' show kEmberCap;
import 'package:productivitwo_v1/utils/badge_today.dart' show TodayFacts;

/// « Aujourd'hui en enjeux », lot 4 : le bilan du soir. À partir de 19 h (sur
/// la journée vécue), le tableau du jour se retourne — ce que la journée a fait
/// avancer, ce qu'elle a laissé filer, ce qui reste possible ce soir et ce qui
/// sera en jeu demain.
const kEveningFromMin = 19 * 60;

bool isEvening(int livedNowMin) => livedNowMin >= kEveningFromMin;

class LedgerLine {
  /// Chiffre de tête : « 🏅 », « +2 », « 1 h 52 », « 0 / 2 ».
  final String figure;
  final String title;
  final String sub;
  const LedgerLine(this.figure, this.title, this.sub);
}

class EveningLedger {
  final List<LedgerLine> advanced;
  final List<LedgerLine> slipped;
  /// Encore possible ce soir (gestes encore en jeu, se perd ce soir d'abord).
  final List<String> stillPossible;
  final List<String> tomorrow;
  final int won;
  final int lost;
  const EveningLedger({this.advanced = const [], this.slipped = const [], this.stillPossible = const [], this.tomorrow = const [], this.won = 0, this.lost = 0});

  int get total => won + lost + stillPossible.length;
  bool get isEmpty => advanced.isEmpty && slipped.isEmpty && stillPossible.isEmpty && tomorrow.isEmpty;
}

bool _sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// [dayStart] = début de la journée vécue ; [now] = maintenant.
EveningLedger buildEveningLedger({
  required StakeBoard board,
  required BadgeDeck? deck,
  required List<Project> projects,
  required List<Activity> activities,
  required List<Session> sessions,
  required List<ObjectiveDay> objectiveDays,
  required DateTime dayStart,
  required DateTime now,
  /// Journée en cours parfaite (toutes les routines, tous les blocs) : une braise à la bascule.
  bool perfectToday = false,
  /// Braises libres maintenant (pour « n sur 3 »).
  int emberStock = 0,
}) {
  final advanced = <LedgerLine>[];
  final slipped = <LedgerLine>[];
  final tomorrow = <String>[];
  final calToday = DateTime(dayStart.year, dayStart.month, dayStart.day);

  // ── Braise : la journée parfaite en forge une à la bascule ────────────────
  if (perfectToday) {
    advanced.add(LedgerLine(
      '+1',
      'Journée parfaite · une braise',
      emberStock >= kEmberCap ? 'réserve pleine ($kEmberCap sur $kEmberCap) : rien de plus' : 'acquise à la bascule · ${emberStock + 1} sur $kEmberCap en réserve',
    ));
  }
  // ── Braise : le dimanche, une semaine tenue en forge une aussi ────────────
  final week = deck?.weeks.thisWeek;
  if (week != null && week.pct != null && calToday.weekday == DateTime.sunday && deck!.weeks.missing == 0) {
    final stock = emberStock + (perfectToday ? 1 : 0);
    advanced.add(LedgerLine(
      '+1',
      'Semaine tenue · ${deck.weeks.current + 1} d’affilée · une braise',
      stock >= kEmberCap ? 'réserve pleine ($kEmberCap sur $kEmberCap) : rien de plus' : 'acquise à la bascule · ${stock + 1} sur $kEmberCap en réserve',
    ));
  }

  // ── Badges : paliers obtenus aujourd'hui, puis séries / chasses tenues ─────
  final tiered = <String>{};
  if (deck != null) {
    for (final b in deck.badges) {
      for (var i = 0; i < b.tierDates.length && i < b.def.tiers.length; i++) {
        final d = b.tierDates[i];
        if (d == null || d.isBefore(dayStart) || d.isAfter(now)) continue;
        tiered.add(b.def.id);
        final next = i + 1 < b.def.tiers.length ? b.def.tiers[i + 1] : null;
        advanced.add(LedgerLine('🏅', '${b.def.name} · palier ${b.def.tiers[i]}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}',
            next == null ? 'nouveau badge · dernier palier' : 'nouveau badge · prochain : $next${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}'));
      }
    }
  }
  for (final w in board.won) {
    advanced.add(LedgerLine('✓', w, 'tenu aujourd’hui'));
  }

  // ── Projets : actions faites aujourd'hui, par projet ──────────────────────
  final byProject = <Project, List<String>>{};
  for (final p in projects) {
    for (final t in p.tasks) {
      for (final a in t.actions) {
        if (a.done && a.doneAt != null && !a.doneAt!.isBefore(dayStart) && !a.doneAt!.isAfter(now)) {
          byProject.putIfAbsent(p, () => []).add(a.title);
        }
      }
    }
  }
  final projectLines = byProject.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in projectLines) {
    final names = e.value.take(2).join(', ');
    advanced.add(LedgerLine('+${e.value.length}', e.key.title, '$names${e.value.length > 2 ? '…' : ''}'));
  }

  // ── Temps : minutes par activité aujourd'hui, l'objectif servi en appui ────
  final minutes = <String, int>{};
  for (final s in sessions) {
    if (s.deleted) continue;
    final start = s.startAt.isBefore(dayStart) ? dayStart : s.startAt;
    final end = (s.endAt ?? now).isAfter(now) ? now : (s.endAt ?? now);
    if (!end.isAfter(start)) continue;
    minutes[s.activityId] = (minutes[s.activityId] ?? 0) + end.difference(start).inMinutes;
  }
  final objectiveOf = <String, (String, ObjectiveTimeToday)>{};
  for (final d in objectiveDays) {
    for (final t in d.times) {
      objectiveOf.putIfAbsent(t.activityId, () => (d.objective.title, t));
    }
  }
  final weekday = now.weekday;
  final timeLines = minutes.entries.where((e) => e.value >= 10).toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in timeLines.take(4)) {
    final a = activities.where((x) => x.id == e.key).firstOrNull;
    if (a == null || a.isHabit) continue;
    final obj = objectiveOf[e.key];
    String sub = 'chrono du jour';
    if (obj != null) {
      final expected = obj.$2.weeklyMin * weekday ~/ 7;
      final done = obj.$2.doneWeekMin;
      sub = '${obj.$1} · ${fmtMin(done)} / ${fmtMin(expected)}${done >= expected ? ' · au rythme' : ''}';
    }
    advanced.add(LedgerLine(fmtMin(e.value), a.name, sub));
  }

  // ── Laissé filer : perdus, puis engagements de temps en retard sans rien ──
  for (final l in board.lost) {
    slipped.add(LedgerLine('✕', l, 'plus rien ne peut sauver la journée pour lui'));
  }
  for (final d in objectiveDays) {
    for (final t in d.times) {
      final expected = t.weeklyMin * weekday ~/ 7;
      final behind = expected - t.doneWeekMin;
      if (behind <= 0 || t.doneTodayMin > 0) continue;
      slipped.add(LedgerLine('−${fmtMin(behind)}', '${t.activity?.name ?? 'Temps'} · ${d.objective.title}', '${fmtMin(t.doneWeekMin)} / ${fmtMin(expected)} attendues à ce jour'));
    }
  }

  // ── Encore possible ce soir ───────────────────────────────────────────────
  final still = [for (final s in [...board.top, ...board.rest]) s.gesture.title];

  // ── Demain en jeu : séries tenues aujourd'hui, chasses, prépas à finir ────
  if (deck != null) {
    for (final s in [...board.top, ...board.rest]) {
      for (final g in s.gains) {
        if ((g.kind == StakeGainKind.seriesTonight || g.kind == StakeGainKind.tierTonight) && g.gauge != null) {
          tomorrow.add('${s.gesture.title} ${g.gauge!.after} / ${g.gauge!.total} j si fait ce soir');
        }
      }
    }
    for (final b in deck.series) {
      if (b.value <= 0 || tiered.contains(b.def.id)) continue;
      if (!board.won.contains('Série ${b.def.name}')) continue;
      final next = b.nextTarget;
      if (next != null) tomorrow.add('${b.def.name} ${b.value.toInt() + 1} / $next j');
    }
  }
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    final i = nextInterventionOf(p, calToday);
    if (i == null) continue;
    final days = i.date.difference(calToday).inDays;
    final prep = i.prep;
    if (days < 0 || days > 7 || prep == null || prep.status == 'done') continue;
    final open = prep.actions.where((a) => !a.done).length;
    if (open > 0 && !_sameDay(i.date, calToday)) tomorrow.add('prépa ${p.title} à finir ($open)');
  }

  return EveningLedger(
    advanced: advanced,
    slipped: slipped,
    stillPossible: still,
    tomorrow: tomorrow.take(5).toList(),
    won: board.won.length + tiered.length,
    lost: board.lost.length,
  );
}

/// Journée en cours parfaite, d'après les faits du jour (même règle que
/// `DayScore.perfect` : rien de neutre, tout atteint, tout fait).
bool isPerfectSoFar(TodayFacts f) {
  final blocks = f.countedBlocks;
  if (f.routines.isEmpty && blocks.isEmpty) return false;
  return f.routines.every((r) => r.reached) && f.blocksDone == blocks.length;
}
