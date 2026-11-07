import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/landing.dart' show nextFixed;
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin, focusBlock;

/// MAINTENANT, la bonne chose (maquette validée 2026-11-07) : UNE chose en grand, choisie dans un ordre fixe, avec
/// la règle qui a gagné (« parce que »). Ordre : un rendez-vous daté dans [kNowFixedLeadMin] min · le chrono qui
/// tourne · le bloc en cours · ce qui se perd ce soir · la parole · les actions visées · le prochain bloc · sinon le
/// mode du moment.
enum NowPickKind { fixedSoon, running, block, morning, evening, losing, parole, focused, next, mode, none }

/// Un rendez-vous daté s'annonce 15 min avant, même par-dessus un chrono.
const kNowFixedLeadMin = 15;

/// Un enjeu ne passe devant le prochain bloc que s'il reste au moins ce temps avant lui.
const kNowStakeRoomMin = 15;

/// Lot 3 : un bloc fini il y a moins de ce temps fait dire « bloc fini · on enchaîne ».
const kNowJustEndedMin = 15;

/// Lot 3 : le soir commence à 19 h (journée vécue).
const kNowEveningMin = 19 * 60;

class NowPick {
  final NowPickKind kind;
  final ScheduleBlock? block;
  final bool current;
  final Stake? stake;
  /// « parce que : … » (sans le préfixe).
  final String why;
  /// Matin / soir : les routines qui restent (titres des gestes).
  final List<String> items;
  const NowPick(this.kind, {this.block, this.current = false, this.stake, this.why = '', this.items = const []});

  bool get isStake => stake != null;
}

String _hm(int min) {
  final m = ((min % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

StakeGain? _gainWhere(Stake s, bool Function(StakeGain g) test) {
  for (final g in s.gains) {
    if (test(g)) return g;
  }
  return null;
}

bool _losing(StakeGain g) =>
    g.losesTonight || g.kind == StakeGainKind.seriesTonight || g.kind == StakeGainKind.tierTonight;

bool _parole(StakeGain g) => g.label.startsWith('Parole tenue');

/// Choisit ce que MAINTENANT montre. [runningName] = nom de l'activité du chrono en cours (null = rien ne tourne).
NowPick pickNow({
  required List<ScheduleBlock> blocks,
  required DateTime now,
  required int nowMin,
  required int dayStartMin,
  Set<String> sessionTaskIds = const {},
  String? runningName,
  StakeBoard? board,
  bool modeAvailable = true,
  bool chainAvailable = false,
  Set<String> skip = const {},
}) {
  final focus = focusBlock(blocks, nowMin);
  final fixed = nextFixed(blocks, now, dayStartMin, sessionTaskIds: sessionTaskIds);
  if (fixed != null && fixed.inMin <= kNowFixedLeadMin && !(focus?.current == true && focus!.block.id == fixed.block.id)) {
    return NowPick(NowPickKind.fixedSoon, block: fixed.block, why: 'un rendez-vous ne bouge pas');
  }
  if (runningName != null) {
    return NowPick(NowPickKind.running, block: focus?.block, current: focus?.current ?? false, why: 'ton chrono tourne sur $runningName');
  }
  if (focus != null && focus.current) {
    return NowPick(NowPickKind.block, block: focus.block, current: true, why: 'bloc en cours jusqu’à ${_hm(blockEndMin(focus.block))}');
  }
  final next = focus?.block;
  final room = next == null ? null : blockStartMin(next) - nowMin;
  // Lot 3, selon le moment.
  final justEnded = blocks.where((b) {
    if (b.status == 'deleted' || b.status == 'skipped') return false;
    final end = blockEndMin(b);
    return end <= nowMin && end > nowMin - kNowJustEndedMin;
  }).isNotEmpty;
  if (justEnded && next != null && room != null && room <= 30) {
    return NowPick(NowPickKind.next, block: next, why: 'bloc fini · on enchaîne, ${_hm(blockStartMin(next))}');
  }
  final routines = board == null
      ? const <String>[]
      : [for (final s in [...board.top, ...board.rest]) if (s.gesture.kind == StakeGestureKind.routine) s.gesture.title];
  if (chainAvailable && routines.isNotEmpty) {
    final started = blocks.any((b) => b.status == 'done');
    if (!started && next != null && nowMin < 12 * 60 && room != null && room >= kNowStakeRoomMin) {
      return NowPick(NowPickKind.morning,
          block: next, items: routines, why: 'premier geste de la journée · ensuite ${next.title} à ${_hm(blockStartMin(next))}');
    }
    if (nowMin >= kNowEveningMin && (room == null || room >= kNowStakeRoomMin)) {
      final until = next == null ? '' : ' avant ${next.title} à ${_hm(blockStartMin(next))}';
      return NowPick(NowPickKind.evening,
          block: next, items: routines, why: '${routines.length} chose${routines.length > 1 ? 's' : ''}$until');
    }
  }
  if (board != null && (room == null || room >= kNowStakeRoomMin)) {
    final stakes = [...board.top, ...board.rest].where((s) => s.gesture.kind != StakeGestureKind.block && !skip.contains(s.gesture.key)).toList();
    for (final (kind, test) in <(NowPickKind, bool Function(StakeGain))>[
      (NowPickKind.losing, _losing),
      (NowPickKind.parole, _parole),
      (NowPickKind.focused, (g) => g.kind == StakeGainKind.focus),
    ]) {
      for (final s in stakes) {
        final g = _gainWhere(s, test);
        if (g == null) continue;
        final until = next == null ? '' : ' · libre jusqu’à ${_hm(blockStartMin(next))}';
        return NowPick(kind, stake: s, block: next, why: '${g.label}$until');
      }
    }
  }
  if (next != null) {
    return NowPick(NowPickKind.next, block: next, why: 'prochain bloc à ${_hm(blockStartMin(next))}');
  }
  if (modeAvailable) return const NowPick(NowPickKind.mode, why: 'rien n’est posé');
  return const NowPick(NowPickKind.none);
}

/// Le gros bouton d'un enjeu : un mot ou deux selon le geste.
String stakeButtonLabel(Stake s) => switch (s.gesture.kind) {
      StakeGestureKind.routine => '+1',
      StakeGestureKind.activity => 'Lancer',
      StakeGestureKind.action => 'Focus',
      StakeGestureKind.reading => 'Noter le relevé',
      StakeGestureKind.block => 'Lancer',
    };

/// « Autre chose › » (lot 2) : les trois suivantes dans le même ordre, chacune avec sa raison — le bloc en cours,
/// ce qui se perd ce soir, la parole, les visées, le prochain bloc —, sans la chose déjà montrée. Les modes
/// viennent à part, en dernier recours.
List<NowPick> nowAlternatives(
  NowPick shown, {
  required List<ScheduleBlock> blocks,
  required int nowMin,
  StakeBoard? board,
  int limit = 3,
  Set<String> skip = const {},
}) {
  final out = <NowPick>[];
  final focus = focusBlock(blocks, nowMin);
  bool sameBlock(ScheduleBlock b) => shown.block?.id == b.id && shown.stake == null;
  if (focus != null && focus.current && !sameBlock(focus.block)) {
    out.add(NowPick(NowPickKind.block, block: focus.block, current: true, why: 'bloc en cours jusqu’à ${_hm(blockEndMin(focus.block))}'));
  }
  if (board != null) {
    final seen = <String>{if (shown.stake != null) shown.stake!.gesture.key, ...skip};
    final stakes = [...board.top, ...board.rest].where((s) => s.gesture.kind != StakeGestureKind.block).toList();
    for (final (kind, test) in <(NowPickKind, bool Function(StakeGain))>[
      (NowPickKind.losing, _losing),
      (NowPickKind.parole, _parole),
      (NowPickKind.focused, (g) => g.kind == StakeGainKind.focus),
    ]) {
      for (final s in stakes) {
        if (seen.contains(s.gesture.key)) continue;
        final g = _gainWhere(s, test);
        if (g == null) continue;
        seen.add(s.gesture.key);
        out.add(NowPick(kind, stake: s, why: g.label));
      }
    }
  }
  final next = focus == null || focus.current
      ? blocks
          .where((b) => b.status == 'pending' && blockStartMin(b) > nowMin)
          .fold<ScheduleBlock?>(null, (best, b) => best == null || blockStartMin(b) < blockStartMin(best) ? b : best)
      : focus.block;
  if (next != null && !sameBlock(next)) {
    out.add(NowPick(NowPickKind.next, block: next, why: 'prochain bloc à ${_hm(blockStartMin(next))}'));
  }
  return out.take(limit).toList();
}

/// « Pas maintenant » (2026-11-07) : un enjeu repoussé « plus tard » revient au bout de ce temps.
const kNowSnoozeMin = 120;

/// Repoussé au moins ce nombre de fois : la feuille propose d'abord d'en faire 5 minutes.
const kNowPostponeWarn = 2;
