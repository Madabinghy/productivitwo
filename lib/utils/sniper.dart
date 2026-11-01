import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;

/// Mode Sniper (maquette validée 2026-11-01) : entre la Guérilla et
/// l'Offensive. L'app prend les enjeux du jour (`buildStakeBoard`), calcule le
/// temps EXACT qui fait tomber chacun (37 min de Lecture = pile ce qui couvre
/// la Montre suisse), les range — ce qui se perd ce soir, puis les paliers de
/// ce soir, puis le plus de gain par minute — et garde ce qui tient dans le
/// temps libre jusqu'au prochain rendez-vous. Puis on enchaîne les tirs, sans
/// décision entre deux. Une session est une [ChainRun] `kind:"sniper"`
/// (`doneCount` = cibles touchées, `total` = cibles visées) ; elle compte pour
/// le badge Sniper quand toutes les cibles visées sont touchées, au moins
/// [kSniperCountedMin]. Logique pure.
const kSniperKind = 'sniper';
const kSniperPauseMin = 2;
const kSniperMaxMin = 60;
const kSniperMaxTargets = 8;
const kSniperCountedMin = 3;
const kSniperTiers = [1, 5, 15];

enum SniperKind { routine, timed, action, reading }

class SniperTarget {
  final Stake stake;
  final SniperKind kind;
  /// Durée du minuteur (0 = un geste immédiat : +1, relevé).
  final int minutes;
  /// Routine : nombre de +1 pour l'atteindre.
  final int delta;
  const SniperTarget(this.stake, this.kind, {required this.minutes, this.delta = 1});

  String get key => stake.gesture.key;
  String get title => stake.gesture.title;
  List<StakeGain> get gains => stake.gains;
  bool get losesTonight => stake.losesTonight;
  bool get tierTonight => gains.any((g) => g.kind == StakeGainKind.tierTonight || g.label.contains('palier'));
  int get weight => gains.fold(0, (s, g) => s + g.weight);

  /// « 37 min », « +1 », « +3 », « 1 min ».
  String get durLabel {
    if (kind == SniperKind.routine && minutes == 0) return '+$delta';
    if (minutes == 0) return '1 min';
    return '$minutes min';
  }

  /// Minutes comptées dans le budget (un geste immédiat compte 1 min).
  int get cost => minutes == 0 ? 1 : minutes;
}

class SniperMiss {
  final SniperTarget target;
  final String reason;
  const SniperMiss(this.target, this.reason);
}

class SniperPlan {
  final List<SniperTarget> aimed;
  final List<SniperMiss> outOfReach;
  final int budgetMin;
  final int pauseMin;
  const SniperPlan({this.aimed = const [], this.outOfReach = const [], required this.budgetMin, this.pauseMin = kSniperPauseMin});

  /// Temps des tirs + pauses entre eux.
  int get totalMin => totalOf(aimed, pauseMin);
  static int totalOf(List<SniperTarget> t, int pauseMin) => t.isEmpty ? 0 : t.fold<int>(0, (s, x) => s + x.cost) + pauseMin * (t.length - 1);
}

int _round5(num m) => ((m / 5).ceil() * 5).toInt();

/// La cible d'un enjeu, ou null quand le Sniper ne s'en charge pas (bloc à
/// heure fixe, enjeu sans badge ni objectif). [routineLeft] = coches restantes
/// des routines du jour ; [factor] = réel / estimé des actions.
SniperTarget? sniperTargetOf(Stake s, {Map<String, int> routineLeft = const {}, double factor = 1}) {
  if (s.gains.every((g) => g.kind == StakeGainKind.routine)) return null;
  final g = s.gesture;
  switch (g.kind) {
    case StakeGestureKind.block:
      return null;
    case StakeGestureKind.routine:
      final left = routineLeft[g.activity?.id] ?? 1;
      final timer = g.activity?.timerMin ?? 0;
      return SniperTarget(s, SniperKind.routine, minutes: timer > 0 ? timer : 0, delta: left < 1 ? 1 : left);
    case StakeGestureKind.activity:
      return SniperTarget(s, SniperKind.timed, minutes: g.costMin < 1 ? 1 : g.costMin);
    case StakeGestureKind.action:
      final est = g.action?.estimatedMin ?? 45;
      final m = _round5(est * (factor <= 0 ? 1 : factor));
      return SniperTarget(s, SniperKind.action, minutes: m < 5 ? 5 : m);
    case StakeGestureKind.reading:
      return SniperTarget(s, SniperKind.reading, minutes: 0);
  }
}

/// Ordre des tirs : se perd ce soir → palier ce soir → gain par minute.
int compareSniper(SniperTarget a, SniperTarget b) {
  if (a.losesTonight != b.losesTonight) return a.losesTonight ? -1 : 1;
  if (a.tierTonight != b.tierTonight) return a.tierTonight ? -1 : 1;
  final ra = a.weight / (a.cost + 3), rb = b.weight / (b.cost + 3);
  final c = rb.compareTo(ra);
  if (c != 0) return c;
  return a.cost.compareTo(b.cost);
}

String _hm(int min) {
  final m = min % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Le plan : les cibles qui tiennent dans [budgetMin] (pauses comprises), le
/// reste « hors de portée » avec sa raison. [untilMin] = heure du rendez-vous
/// qui borne le temps (pour la raison « ne tient plus avant HH:MM »).
SniperPlan planSniper({
  required List<Stake> stakes,
  required int budgetMin,
  int? untilMin,
  Map<String, int> routineLeft = const {},
  double factor = 1,
  int pauseMin = kSniperPauseMin,
  int maxTargets = kSniperMaxTargets,
  int maxMin = kSniperMaxMin,
  Set<String> excluded = const {},
}) {
  final targets = [
    for (final s in stakes)
      if (!excluded.contains(s.gesture.key)) sniperTargetOf(s, routineLeft: routineLeft, factor: factor),
  ].whereType<SniperTarget>().toList()
    ..sort(compareSniper);
  final aimed = <SniperTarget>[];
  final out = <SniperMiss>[];
  var used = 0;
  for (final t in targets) {
    if (t.minutes > maxMin) {
      out.add(SniperMiss(t, 'plus d’une heure · pour l’Offensive'));
      continue;
    }
    if (aimed.length >= maxTargets) {
      out.add(SniperMiss(t, 'au-delà de $maxTargets cibles'));
      continue;
    }
    final add = t.cost + (aimed.isEmpty ? 0 : pauseMin);
    if (used + add > budgetMin) {
      out.add(SniperMiss(t, untilMin == null ? 'ne tient plus dans ton temps libre' : 'ne tient plus avant ${_hm(untilMin)}'));
      continue;
    }
    used += add;
    aimed.add(t);
  }
  return SniperPlan(aimed: aimed, outOfReach: out, budgetMin: budgetMin, pauseMin: pauseMin);
}

/// Le temps libre à partir de [nowMin] (minute de la journée vécue) : jusqu'au
/// prochain bloc À FAIRE qui commence plus tard (hors blocs de temps, qu'un
/// Sniper peut occuper), sinon jusqu'à [endMin]. [until] = ce bloc.
({int minutes, int untilMin, ScheduleBlock? until}) sniperBudget({required List<ScheduleBlock> blocks, required int nowMin, required int endMin}) {
  ScheduleBlock? next;
  for (final b in blocks) {
    if (b.status != 'pending' || b.isTimeBlock) continue;
    final s = blockStartMin(b);
    if (s <= nowMin) continue;
    if (next == null || s < blockStartMin(next)) next = b;
  }
  final until = next == null ? endMin : (blockStartMin(next) < endMin ? blockStartMin(next) : endMin);
  final m = until - nowMin;
  return (minutes: m < 0 ? 0 : m, untilMin: until, until: next != null && blockStartMin(next) <= endMin ? next : null);
}

/// Précision d'un tir ou d'une session : 100 % quand le temps tiré égale le
/// temps visé, moins l'écart relatif.
int sniperPrecision(int aimedMin, int firedMin) {
  if (aimedMin <= 0) return 100;
  final p = 100 - ((firedMin - aimedMin).abs() * 100 / aimedMin).round();
  return p < 0 ? 0 : p;
}

bool isSniperRun(ChainRun r) => r.kind == kSniperKind;

/// Une session compte : toutes les cibles visées touchées, au moins 3.
bool sniperCounts(ChainRun r) => isSniperRun(r) && r.doneCount >= kSniperCountedMin && r.doneCount >= r.total;

String sniperCountLine(int hit, int aimed) {
  if (hit >= kSniperCountedMin && hit >= aimed) return 'session comptée';
  if (hit < kSniperCountedMin) return 'une session compte dès $kSniperCountedMin cibles, toutes touchées';
  return 'une session compte quand toutes les cibles visées tombent';
}
