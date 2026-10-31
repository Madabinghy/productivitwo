import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin;
import 'package:productivitwo_v1/utils/week_capacity.dart' show DayWindow;

/// Mode Planification (maquette validée 2026-10-31) : poser demain en dix
/// minutes, à partir de ce qui se joue. Logique pure : enjeux → temps libre →
/// blocs d'activité proposés ; et la règle du badge Cap tenu.

/// Ce qui se joue un jour donné.
enum PlanStakeKind {
  /// Daté, ne bouge pas (agenda, séance) : déjà dans le programme ou fixé.
  dated,
  /// Se perd si rien ce jour-là (série, Montre suisse, relevé).
  losing,
  /// En retard sur son rythme (objectif, plan d'un projet, prépa de séance).
  behind,
}

class PlanStake {
  final String id;
  final PlanStakeKind kind;
  final String title;
  final String detail;
  /// Activité à poser en bloc pour tenir l'enjeu (null = rien à poser : un rendez-vous, une routine).
  final String? activityId;
  /// Minutes suggérées pour le bloc.
  final int minutes;
  /// Coché par défaut.
  final bool keep;
  const PlanStake({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    this.activityId,
    this.minutes = 0,
    this.keep = true,
  });
}

/// Un créneau libre, en minutes depuis minuit.
class PlanGap {
  final int startMin;
  final int endMin;
  const PlanGap(this.startMin, this.endMin);
  int get minutes => endMin - startMin;
}

/// Les créneaux libres de la fenêtre [w], hors blocs posés (à faire ou faits)
/// — `durationMin` pris tel quel, une nuit qui déborde coupe la fin de fenêtre.
List<PlanGap> freeGaps(List<ScheduleBlock> blocks, DayWindow w, {int minGap = 15}) {
  final busy = <(int, int)>[
    for (final b in blocks)
      if (b.status == 'pending' || b.status == 'done') (blockStartMin(b), blockEndMin(b)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <PlanGap>[];
  var cur = w.startMin;
  for (final (s, e) in busy) {
    if (e <= cur) continue;
    if (s >= w.endMin) break;
    if (s - cur >= minGap) out.add(PlanGap(cur, s));
    if (e > cur) cur = e;
  }
  if (w.endMin - cur >= minGap) out.add(PlanGap(cur, w.endMin));
  return out;
}

int freeMinutes(List<PlanGap> gaps) => gaps.fold(0, (s, g) => s + g.minutes);

/// Part du temps libre qu'on remplit selon l'état annoncé pour demain.
enum PlanLoad { light, normal, full }

double fillRatio(PlanLoad l) => switch (l) { PlanLoad.light => .5, PlanLoad.normal => .8, PlanLoad.full => .95 };

const kPlanLoadLabels = {PlanLoad.light: 'Léger', PlanLoad.normal: 'Normal', PlanLoad.full: 'À fond'};

/// Un bloc d'activité à poser.
class PlanWant {
  final String activityId;
  final String title;
  final int minutes;
  final String reason;
  const PlanWant({required this.activityId, required this.title, required this.minutes, required this.reason});
}

class PlannedBlock {
  final PlanWant want;
  final int startMin;
  final int minutes;
  const PlannedBlock(this.want, this.startMin, this.minutes);
  int get endMin => startMin + minutes;
}

/// Pose les envies dans les créneaux, dans l'ordre donné (le plus important
/// d'abord), sans dépasser [budget] minutes : premier créneau où le bloc
/// tient, 10 min d'air après chaque bloc, heures arrondies au quart d'heure.
/// Un bloc qui ne tient nulle part en entier est raccourci jusqu'à 30 min,
/// sinon laissé de côté.
List<PlannedBlock> proposeDay(List<PlanGap> gaps, List<PlanWant> wants, int budget) {
  final free = [for (final g in gaps) [_ceil15(g.startMin), g.endMin]];
  final out = <PlannedBlock>[];
  var left = budget;
  for (final w in wants) {
    if (left < 30) break;
    var want = w.minutes > left ? left : w.minutes;
    want = (want ~/ 15) * 15;
    if (want < 30) continue;
    PlannedBlock? placed;
    for (final len in [want, if (want > 45) 45, 30]) {
      for (final f in free) {
        if (f[1] - f[0] >= len) {
          placed = PlannedBlock(w, f[0], len);
          f[0] = _ceil15(f[0] + len + 10);
          break;
        }
      }
      if (placed != null) break;
    }
    if (placed == null) continue;
    out.add(placed);
    left -= placed.minutes;
  }
  out.sort((a, b) => a.startMin.compareTo(b.startMin));
  return out;
}

int _ceil15(int m) => ((m + 14) ~/ 15) * 15;

String hmOf(int min) => '${(min ~/ 60) % 24}'.padLeft(2, '0') + ':' + '${min % 60}'.padLeft(2, '0');

/// Bloc du programme pour un bloc proposé.
ScheduleBlock planBlockOf(PlannedBlock p) => ScheduleBlock(
      startTime: hmOf(p.startMin),
      durationMin: p.minutes,
      title: p.want.title,
      category: 'project',
      activityId: p.want.activityId,
    );

// ── Badge Cap tenu ────────────────────────────────────────────────────────────

const kCapHeldRatio = .7;
const kCapTiers = [5, 20, 50];

/// Une journée compte pour « Cap tenu » quand son programme a été posé la
/// VEILLE par le mode Planification (`generatedBy:"plan"`, `plannedAt` avant
/// le jour) et qu'au moins 70 % de ses blocs (hors miroirs d'agenda) sont
/// faits.
bool capHeld(DailySchedule s) {
  if (s.generatedBy != 'plan' || s.plannedSameDay) return false;
  final at = s.plannedAt;
  final p = s.date.split('-');
  if (at == null || p.length != 3) return false;
  final day = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  if (!at.isBefore(day)) return false;
  final counted = s.blocks.where((b) => b.gcalEventId == null && (b.status == 'pending' || b.status == 'done')).toList();
  if (counted.isEmpty) return false;
  return counted.where((b) => b.status == 'done').length / counted.length >= kCapHeldRatio;
}

/// Journées « Cap tenu » parmi des programmes clos (avant [today]).
int capHeldCount(List<DailySchedule> schedules, String todayYmd) =>
    schedules.where((s) => s.date.compareTo(todayYmd) < 0 && capHeld(s)).length;

// ── Semaine ───────────────────────────────────────────────────────────────────

/// Une activité à répartir sur la semaine (minimum vital × jours, objectif, plan).
class WeekWant {
  final String activityId;
  final String title;
  final int weeklyMin;
  final String reason;
  const WeekWant({required this.activityId, required this.title, required this.weeklyMin, required this.reason});
}

/// Répartit chaque activité en morceaux ([chunk] min) sur les jours ([free] =
/// minutes libres par jour, déjà multipliées par la part qu'on remplit) : le
/// jour le moins chargé d'abord, jamais deux morceaux de la même activité le
/// même jour tant qu'un autre jour peut la prendre. Renvoie, par jour, les
/// minutes par activité.
List<Map<String, int>> spreadWeek(List<WeekWant> wants, List<int> free, {int chunk = 45}) {
  final left = [...free];
  final out = [for (final _ in free) <String, int>{}];
  for (final w in wants) {
    var rest = w.weeklyMin;
    while (rest >= 30) {
      final piece = rest >= chunk ? chunk : ((rest + 14) ~/ 15) * 15;
      var best = -1;
      for (var d = 0; d < left.length; d++) {
        if (left[d] < piece) continue;
        if (best < 0) {
          best = d;
          continue;
        }
        final hasD = out[d].containsKey(w.activityId), hasB = out[best].containsKey(w.activityId);
        if (hasD != hasB) {
          if (!hasD) best = d;
          continue;
        }
        if (left[d] > left[best]) best = d;
      }
      if (best < 0) break;
      out[best][w.activityId] = (out[best][w.activityId] ?? 0) + piece;
      left[best] -= piece;
      rest -= piece;
    }
  }
  return out;
}
