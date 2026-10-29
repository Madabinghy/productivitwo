import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn, isFolderProject, shortDateFr;
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show nextInterventionOf;
import 'package:productivitwo_v1/utils/project_moment.dart' show projectPlan;
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;

/// « Aujourd'hui en enjeux », lot 3 : les tuiles du tableau de bord. Chaque
/// tuile donne son état en une ligne et ouvre sa vue complète.

/// État d'une case de la mini-jauge d'une tuile.
enum TileMark { on, off, warn, current }

class DashTile {
  final String label;
  final String? badge;
  final String value;
  final String sub;
  final List<TileMark> mini;
  const DashTile({required this.label, this.badge, required this.value, required this.sub, this.mini = const []});
}

/// Un morceau de la bande du programme : largeur = durée.
class StripPiece {
  final int durationMin;
  final TileMark mark;
  const StripPiece(this.durationMin, this.mark);
}

class ProgramTile extends DashTile {
  final List<StripPiece> strip;
  const ProgramTile({required super.value, required super.sub, required this.strip}) : super(label: 'PROGRAMME');
}

String _hm(int min) {
  final m = min % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// PROGRAMME : n blocs · k faits, bande de la journée, en cours / ensuite.
ProgramTile? programTile(List<ScheduleBlock> blocks, int nowMin) {
  final live = blocks.where((b) => b.status != 'deleted' && b.status != 'skipped').toList()
    ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
  if (live.isEmpty) return null;
  final done = live.where((b) => b.status == 'done').length;
  ScheduleBlock? current, next;
  for (final b in live) {
    final s = blockStartMin(b);
    if (current == null && s <= nowMin && nowMin < s + b.durationMin) current = b;
    if (next == null && s > nowMin) next = b;
  }
  final strip = [
    for (final b in live)
      StripPiece(b.durationMin, b.status == 'done' ? TileMark.on : (identical(b, current) ? TileMark.current : TileMark.off)),
  ];
  final parts = <String>[
    if (current != null) 'en cours : ${current.title} jusqu’à ${_hm(blockStartMin(current) + current.durationMin)}',
    if (next != null) '${current == null ? 'prochain' : 'ensuite'} : ${next.title} ${next.startTime}',
  ];
  return ProgramTile(
    value: '${live.length} bloc${live.length > 1 ? 's' : ''} · $done fait${done > 1 ? 's' : ''}',
    sub: parts.isEmpty ? 'plus rien de prévu aujourd’hui' : parts.join(' · '),
    strip: strip,
  );
}

/// ROUTINES : fait / total, une case par routine, ce qui reste ce moment-ci.
DashTile? routinesTile({required int done, required int total, required List<String> toDoNow, required String momentLabel, int seriesRunning = 0}) {
  if (total == 0) return null;
  final cells = total > 12 ? 12 : total;
  final on = total == 0 ? 0 : (done * cells / total).round();
  return DashTile(
    label: 'ROUTINES',
    badge: seriesRunning > 0 ? '🔥 $seriesRunning' : null,
    value: '$done / $total',
    mini: [for (var i = 0; i < cells; i++) i < on ? TileMark.on : TileMark.off],
    sub: toDoNow.isEmpty
        ? (done >= total ? 'tout est fait' : 'rien à faire $momentLabel')
        : '${toDoNow.length} à faire $momentLabel · ${toDoNow.take(2).join(', ')}${toDoNow.length > 2 ? '…' : ''}',
  );
}

/// OBJECTIFS : combien sont au rythme cette semaine (≥ 85 %).
DashTile? objectivesTile(List<(String title, double? weekPercent)> objectives, {int readingsDue = 0}) {
  if (objectives.isEmpty) return null;
  bool ok((String, double?) o) => o.$2 == null || o.$2! >= .85;
  final atPace = objectives.where(ok).length;
  final behind = objectives.where((o) => !ok(o)).toList()..sort((a, b) => a.$2!.compareTo(b.$2!));
  return DashTile(
    label: 'OBJECTIFS',
    badge: 'sem.',
    value: '$atPace / ${objectives.length}',
    mini: [for (final o in objectives.take(12)) ok(o) ? TileMark.on : TileMark.warn],
    sub: [
      if (readingsDue > 0) '$readingsDue relevé${readingsDue > 1 ? 's' : ''} à noter',
      behind.isEmpty ? 'tous au rythme' : behind.take(2).map((o) => '${o.$1} à ${(o.$2! * 100).round()} %').join(', '),
    ].join(' · '),
  );
}

/// BADGES : obtenus / total, ce qui tombe ce soir (palier, sinon série à
/// sauver), puis le badge le plus proche de son palier.
DashTile? badgesTile(BadgeDeck? deck, StakeBoard board) {
  if (deck == null) return null;
  final tonight = <String>[];
  for (final s in [...board.top, ...board.rest]) {
    for (final g in s.gains) {
      if (g.kind == StakeGainKind.tierTonight) tonight.add('${s.gesture.title} ${g.label.replaceFirst(' ce soir', '').replaceFirst('palier ', '')}');
    }
  }
  final losing = [
    for (final s in [...board.top, ...board.rest])
      if (s.gains.any((g) => g.kind == StakeGainKind.seriesTonight)) s.gesture.title,
  ];
  final near = nearBadges(deck).take(2).toList();
  final String value;
  final String sub;
  if (tonight.isNotEmpty) {
    value = tonight.first;
    sub = 'palier ce soir${losing.isEmpty ? '' : ' · ${losing.length} série${losing.length > 1 ? 's' : ''} à sauver'}';
  } else if (losing.isNotEmpty) {
    value = '${losing.length} série${losing.length > 1 ? 's' : ''} ce soir';
    sub = 'à sauver : ${losing.take(2).join(', ')}${losing.length > 2 ? '…' : ''}';
  } else if (near.isNotEmpty) {
    value = near.first.def.name;
    sub = 'le plus proche · ${near.first.value.toInt()} / ${near.first.nextTarget}';
  } else {
    value = '${deck.acquired} paliers';
    sub = 'rien ne se joue ce soir';
  }
  return DashTile(
    label: 'BADGES',
    badge: '${deck.acquired} / ${deck.total}',
    value: value,
    mini: [for (var i = 0; i < (tonight.length + losing.length).clamp(0, 8); i++) i < tonight.length ? TileMark.on : TileMark.warn],
    sub: sub,
  );
}

/// Badges non complets, du plus proche de son palier au plus loin (hors
/// séries à 0).
List<BadgeState> nearBadges(BadgeDeck deck) {
  final l = [
    for (final b in deck.badges)
      if (!b.complete && b.nextTarget != null && b.nextTarget! > 0 && b.value > 0) b,
  ]..sort((a, b) => (b.value / b.nextTarget!).compareTo(a.value / a.nextTarget!));
  return l;
}

/// ACTIONS : visées aujourd'hui, faites, la première ouverte en tête.
DashTile? actionsTile({required List<Project> projects, required List<Activity> activities, required DateTime today}) {
  final focused = <TaskAction>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in p.tasks) {
      if (t.status == 'skipped') continue;
      focused.addAll(t.actions.where((a) => isFocusedOn(a, today) || (a.done && _sameDay(a.focusDate, today))));
    }
  }
  for (final a in activities) {
    focused.addAll(a.ownActions.where((x) => isFocusedOn(x, today) || (x.done && _sameDay(x.focusDate, today))));
  }
  if (focused.isEmpty) return null;
  final done = focused.where((a) => a.done).length;
  final open = focused.where((a) => !a.done).toList();
  return DashTile(
    label: 'ACTIONS',
    badge: '☀ ${focused.length}',
    value: '${focused.length} visée${focused.length > 1 ? 's' : ''}',
    mini: [for (final a in focused.take(12)) a.done ? TileMark.on : TileMark.off],
    sub: open.isEmpty ? 'toutes faites' : '$done faite${done > 1 ? 's' : ''} · ${open.first.title} en tête',
  );
}

bool _sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// PROJETS : la séance la plus proche (prépa), le nombre de projets et ceux
/// en retard sur leur plan.
DashTile? projectsTile(List<Project> projects, DateTime today) {
  final live = projects.where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, projects)).toList();
  if (live.isEmpty) return null;
  final behind = live.where((p) => projectPlan(p, today).delta < 0).length;
  ({Project p, DateTime date, int done, int total})? best;
  final d0 = DateTime(today.year, today.month, today.day);
  for (final p in live) {
    final i = nextInterventionOf(p, today);
    if (i == null || i.date.isBefore(d0)) continue;
    if (best != null && !i.date.isBefore(best.date)) continue;
    final prep = i.prep;
    best = (p: p, date: i.date, done: prep?.actions.where((a) => a.done).length ?? 0, total: prep?.actions.length ?? 0);
  }
  final count = '${live.length} projet${live.length > 1 ? 's' : ''}${behind > 0 ? ', $behind en retard sur le plan' : ''}';
  if (best == null) {
    return DashTile(label: 'PROJETS', value: count, sub: 'aucune séance à venir');
  }
  return DashTile(
    label: 'PROJETS',
    badge: 'séance la plus proche',
    value: '${best.p.title} · ${shortDateFr(best.date, today: today)}',
    mini: [for (var i = 0; i < best.total.clamp(0, 12); i++) i < best.done ? TileMark.on : TileMark.off],
    sub: '${best.total > 0 ? 'prépa ${best.done} / ${best.total} · ' : ''}$count',
  );
}

/// Les sections de l'écran « Badges en jeu » (aujourd'hui) : ce qui se perd
/// ce soir, les paliers de ce soir, les chasses, puis les plus proches.
class BadgesInPlay {
  final List<(Stake, StakeGain)> losing;
  final List<(Stake, StakeGain)> tiers;
  final List<(Stake, StakeGain)> hunts;
  final List<BadgeState> near;
  const BadgesInPlay(this.losing, this.tiers, this.hunts, this.near);
  int get today => losing.length + tiers.length + hunts.length;
}

BadgesInPlay badgesInPlay(StakeBoard board, BadgeDeck? deck) {
  final losing = <(Stake, StakeGain)>[], tiers = <(Stake, StakeGain)>[], hunts = <(Stake, StakeGain)>[];
  final seen = <String>{};
  for (final s in [...board.top, ...board.rest]) {
    for (final g in s.gains) {
      final key = '${g.kind.name}:${g.sourceId ?? s.gesture.key}';
      if (!seen.add(key)) continue;
      switch (g.kind) {
        case StakeGainKind.tierTonight:
          tiers.add((s, g));
        case StakeGainKind.seriesTonight:
          losing.add((s, g));
        case StakeGainKind.hunt:
        case StakeGainKind.series:
          hunts.add((s, g));
        default:
      }
    }
  }
  final inPlay = {for (final (_, g) in [...losing, ...tiers, ...hunts]) g.sourceId};
  final near = deck == null ? const <BadgeState>[] : nearBadges(deck).where((b) => !inPlay.contains(b.def.id)).take(8).toList();
  return BadgesInPlay(losing, tiers, hunts, near);
}
