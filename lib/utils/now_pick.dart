import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/landing.dart' show nextFixed;
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin, focusBlock;

/// MAINTENANT, la bonne chose (maquette validée 2026-11-07) : UNE chose en grand, choisie dans un ordre fixe, avec
/// la règle qui a gagné (« parce que »). Ordre : un rendez-vous daté dans [kNowFixedLeadMin] min · le chrono qui
/// tourne · le bloc en cours · ce qui se perd ce soir · la parole · les actions visées · le prochain bloc · sinon le
/// mode du moment.
enum NowPickKind { fixedSoon, running, block, losing, parole, focused, next, mode, none }

/// Un rendez-vous daté s'annonce 15 min avant, même par-dessus un chrono.
const kNowFixedLeadMin = 15;

/// Un enjeu ne passe devant le prochain bloc que s'il reste au moins ce temps avant lui.
const kNowStakeRoomMin = 15;

class NowPick {
  final NowPickKind kind;
  final ScheduleBlock? block;
  final bool current;
  final Stake? stake;
  /// « parce que : … » (sans le préfixe).
  final String why;
  const NowPick(this.kind, {this.block, this.current = false, this.stake, this.why = ''});

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
  if (board != null && (room == null || room >= kNowStakeRoomMin)) {
    final stakes = [...board.top, ...board.rest].where((s) => s.gesture.kind != StakeGestureKind.block).toList();
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
