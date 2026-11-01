import 'package:productivitwo_v1/utils/parole.dart' show ParoleDay, kParoleMin;
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn, shortDateFr;
import 'package:productivitwo_v1/utils/badge_today.dart' show TodayFacts;
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/embers.dart' show EmberLedger, kEmberCap;
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, isLetGoBlock;

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
  /// Objet que la tuile met en avant (projet du moment), ouvert au tap.
  final String? targetId;
  /// Tuile Badges : les plus belles cartes, en éventail (badges en cartes, lot 3).
  final List<BadgeState> fan;
  const DashTile({required this.label, this.badge, required this.value, required this.sub, this.mini = const [], this.targetId, this.fan = const []});
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
  CardRarity? tonightCard;
  for (final s in [...board.top, ...board.rest]) {
    for (final g in s.gains) {
      if (g.kind != StakeGainKind.tierTonight) continue;
      tonight.add('${s.gesture.title} ${g.label.replaceFirst(' ce soir', '').replaceFirst('palier ', '')}');
      tonightCard ??= g.sourceId == null ? null : tonightRarity(deck.byId(g.sourceId!));
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
    sub = '${tonightCard == null ? 'palier' : 'carte ${rarityLabel(tonightCard).toLowerCase()}'} ce soir${losing.isEmpty ? '' : ' · ${losing.length} série${losing.length > 1 ? 's' : ''} à sauver'}';
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
  final album = cardAlbum(deck);
  return DashTile(
    label: 'BADGES',
    badge: '${album.won} / ${album.total} cartes',
    fan: bestCards(deck),
    value: value,
    mini: [for (var i = 0; i < (tonight.length + losing.length).clamp(0, 8); i++) i < tonight.length ? TileMark.on : TileMark.warn],
    sub: sub,
  );
}

/// La carte que donnerait le palier de ce soir (null sans badge).
CardRarity? tonightRarity(BadgeState? b) {
  if (b == null || b.complete) return null;
  return rarityOf(BadgeState(def: b.def, level: b.level + 1, value: b.nextTarget ?? b.value));
}

/// Les plus belles cartes gagnées : la plus rare d'abord, puis la plus récente.
List<BadgeState> bestCards(BadgeDeck deck, {int n = 3}) {
  final won = [for (final b in deck.badges) if (b.acquired) b]..sort((a, b) {
      final r = rarityOf(b).index.compareTo(rarityOf(a).index);
      if (r != 0) return r;
      return (b.obtained ?? DateTime(0)).compareTo(a.obtained ?? DateTime(0));
    });
  return won.take(n).toList();
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
DashTile? actionsTile({required List<Project> projects, required List<Activity> activities, required DateTime today, ParoleDay? parole}) {
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
  // Parole tenue : la tuile parle de la parole du jour quand elle existe (≥ 3).
  if (parole != null && parole.ids.length >= kParoleMin) {
    final byId = <String, TaskAction>{};
    for (final p in projects) {
      for (final t in p.tasks) {
        for (final a in t.actions) {
          byId[a.id] = a;
        }
      }
    }
    for (final act in activities) {
      for (final a in act.ownActions) {
        byId[a.id] = a;
      }
    }
    final items = [for (final id in parole.ids) byId[id]];
    final kept = items.where((a) => a != null && a.done).length;
    final left = items.where((a) => a != null && !a.done).toList();
    final extra = focused.where((a) => !parole.ids.contains(a.id)).length;
    return DashTile(
      label: 'PAROLE',
      badge: '☀ ${focused.length}',
      value: '$kept / ${items.length} tenue',
      mini: [for (final a in items) a?.done == true ? TileMark.on : TileMark.off],
      sub: left.isEmpty
          ? 'parole tenue${extra > 0 ? ' · +$extra hors parole' : ''}'
          : '${left.length == 1 ? 'la dernière' : 'encore ${left.length}'} · ${left.first!.title}',
    );
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

/// PROJETS : le projet du moment (même classement que l'onglet Projets,
/// `rankProjectMoments`), hors projets passés aujourd'hui ([skipped]) ; sa
/// raison d'être en tête (séance et prépa, retard sur le plan, prochaine
/// action), le nombre de projets et ceux en retard.
DashTile? projectsTile(List<Project> projects, DateTime today, {List<Session> sessions = const [], Set<String> skipped = const {}}) {
  final ranked = rankProjectMoments(projects, sessions, today);
  if (ranked.isEmpty) return null;
  final live = ranked.where((m) => !m.upcoming).toList();
  final behind = live.where((m) => m.behind).length;
  final count = '${ranked.length} projet${ranked.length > 1 ? 's' : ''}${behind > 0 ? ', $behind en retard sur le plan' : ''}';
  final m = live.where((m) => !skipped.contains(m.project.id)).firstOrNull;
  if (m == null) {
    return DashTile(
      label: 'PROJETS',
      value: count,
      sub: skipped.isNotEmpty && live.isNotEmpty ? 'tous passés pour aujourd’hui' : 'rien d’urgent',
    );
  }
  final s = m.session;
  final String badge;
  final String reason;
  var mini = <TileMark>[];
  if (m.sessionSoon && s != null) {
    badge = 'séance ${shortDateFr(s.date, today: today)}';
    final total = s.prepTotal, done = s.prepTotal - s.prepOpen;
    reason = total > 0 ? 'prépa $done / $total' : 'séance à venir';
    mini = [for (var i = 0; i < total.clamp(0, 12); i++) i < done ? TileMark.on : TileMark.off];
  } else if (m.behind) {
    badge = 'en retard';
    reason = '${m.deltaLabel} sur le plan';
    mini = [for (var i = 0; i < m.plan.total.clamp(0, 12); i++) i < m.plan.done ? TileMark.on : (i < m.plan.expected ? TileMark.warn : TileMark.off)];
  } else {
    badge = m.stateLabel;
    reason = m.next == null ? 'définir la prochaine action' : 'ensuite : ${m.next!.action.title}';
  }
  return DashTile(
    label: 'PROJETS',
    badge: badge,
    value: m.project.title,
    mini: mini,
    sub: '$reason · $count',
    targetId: m.project.id,
  );
}

/// Les sections de l'écran « Badges en jeu » (aujourd'hui) : ce qui se perd
/// ce soir, les paliers de ce soir, les chasses, puis les plus proches.
class BadgesInPlay {
  /// Carte que donnerait chaque palier de ce soir (par badge).
  final Map<String, BadgeState> tierCards;
  final List<(Stake, StakeGain)> losing;
  final List<(Stake, StakeGain)> tiers;
  final List<(Stake, StakeGain)> hunts;
  final List<BadgeState> near;
  const BadgesInPlay(this.losing, this.tiers, this.hunts, this.near, {this.tierCards = const {}});
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
  final tierCards = <String, BadgeState>{};
  for (final (_, g) in tiers) {
    final b = g.sourceId == null ? null : deck?.byId(g.sourceId!);
    if (b == null || b.complete) continue;
    tierCards[b.def.id] = BadgeState(def: b.def, level: b.level + 1, value: b.nextTarget ?? b.value);
  }
  return BadgesInPlay(losing, tiers, hunts, near, tierCards: tierCards);
}

/// JOURNÉE PARFAITE (2026-10-30) : ce qui manque pour la journée parfaite
/// (routines non atteintes + blocs à faire) et les braises en réserve. La
/// mini-jauge = une case par chose à tenir, pleine si tenue (16 au plus).
DashTile? perfectDayTile(TodayFacts? facts, EmberLedger ledger) {
  if (facts == null) return null;
  final missingRoutines = [for (final r in facts.routines) if (!r.reached) r.activity.name];
  final blocks = facts.countedBlocks;
  final pending = facts.pendingBlocks.length;
  final total = facts.routines.length + blocks.length;
  final done = facts.routinesReached + facts.blocksDone;
  final embers = '🔥 ${ledger.available} / $kEmberCap';
  if (total == 0) {
    return DashTile(label: 'JOURNÉE PARFAITE', badge: embers, value: 'Rien à tenir', sub: 'aucune routine ni bloc aujourd\'hui');
  }
  const cap = 16;
  final cells = total <= cap ? total : cap;
  final filled = (done * cells / total).floor();
  final mini = [for (var i = 0; i < cells; i++) i < filled ? TileMark.on : TileMark.off];
  final missing = missingRoutines.length + pending;
  // Un bloc lâché : la journée parfaite est perdue, sans le cacher (2026-11-01).
  final letGo = blocks.where(isLetGoBlock).toList();
  if (letGo.isNotEmpty) {
    return DashTile(
      label: 'JOURNÉE PARFAITE',
      badge: embers,
      value: 'Pas aujourd\'hui',
      sub: '${letGo.first.title} lâché · le reste compte toujours',
      mini: mini,
    );
  }
  if (missing == 0) {
    return DashTile(
      label: 'JOURNÉE PARFAITE',
      badge: embers,
      value: 'Parfaite ✓',
      sub: ledger.stock >= kEmberCap ? 'réserve pleine : pas de braise de plus' : 'une braise à la bascule',
      mini: mini,
    );
  }
  final parts = <String>[
    if (missingRoutines.isNotEmpty)
      missingRoutines.length <= 2 ? missingRoutines.join(', ') : '${missingRoutines.length} routines',
    if (pending > 0) '$pending bloc${pending > 1 ? 's' : ''}',
  ];
  return DashTile(
    label: 'JOURNÉE PARFAITE',
    badge: embers,
    value: 'Il manque $missing',
    sub: parts.join(' · '),
    mini: mini,
  );
}
