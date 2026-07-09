import 'package:productivitwo_v1/models.dart';

// ─── RENÉGOCIATION TACTIQUE (maquette 12a) ───────────────────────────────────
//
// Un bloc coince : trois issues GÉNÉRÉES DEPUIS LE RÉEL (créneaux libres du
// jour, historique de reports), chacune avec sa conséquence affichée — on
// choisit en connaissance de cause. Fonctions pures, testables. 0 LLM.

/// Minutes « utiles » restantes aujourd'hui (jusqu'à [dayEndHour]).
int usefulMinutesLeft(DateTime now, {int dayEndHour = 22}) {
  final end = dayEndHour * 60;
  final cur = now.hour * 60 + now.minute;
  return cur >= end ? 0 : end - cur;
}

/// Le DERNIER créneau libre du jour pouvant contenir [durationMin] minutes,
/// entre maintenant et [dayEndHour], en évitant les blocs `pending` restants.
/// Retourne "HH:mm" ou null si plus rien ne rentre.
String? findLastFreeSlot(
  DateTime now,
  List<ScheduleBlock> blocks,
  int durationMin, {
  int dayEndHour = 22,
  String? excludeBlockId,
}) {
  int hm(String s) {
    final p = s.split(':');
    return (int.tryParse(p.first) ?? 0) * 60 +
        (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  final nowMin = now.hour * 60 + now.minute;
  final dayEnd = dayEndHour * 60;
  // Occupations restantes : blocs pending (hors celui qu'on renégocie).
  final busy = blocks
      .where((b) =>
          b.status == 'pending' &&
          b.id != excludeBlockId &&
          !b.isPrep)
      .map((b) => (start: hm(b.startTime), end: hm(b.startTime) + b.durationMin))
      .where((b) => b.end > nowMin)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  // Parcours des trous, on garde LE DERNIER qui contient durationMin.
  int cursor = nowMin;
  int? lastFit;
  for (final b in busy) {
    final gapEnd = b.start.clamp(cursor, dayEnd);
    if (gapEnd - cursor >= durationMin) {
      lastFit = gapEnd - durationMin; // au plus tard dans ce trou
    }
    if (b.end > cursor) cursor = b.end;
    if (cursor >= dayEnd) break;
  }
  if (dayEnd - cursor >= durationMin) {
    lastFit = dayEnd - durationMin;
  }
  if (lastFit == null) return null;
  final h = lastFit ~/ 60;
  final m = lastFit % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Nombre de reports de CET engagement sur les blocs fournis (7 derniers
/// jours) — pour « 2ᵉ report cette semaine — demain il passe en premier ».
int weeklyReportCount(ScheduleBlock b, List<ScheduleBlock> weekBlocks) =>
    weekBlocks
        .where((w) => _sameEngagement(b, w) && w.skipReason == 'reporte')
        .length;

bool _sameEngagement(ScheduleBlock b, ScheduleBlock w) {
  if (w.isPrep || w.category == 'break') return false;
  if (b.taskId != null) return w.taskId == b.taskId;
  if (b.activityId != null) return w.activityId == b.activityId;
  return w.title.trim().toLowerCase() == b.title.trim().toLowerCase();
}

// ─── RENÉGOCIATION STRUCTURELLE (maquette 12b) ───────────────────────────────
//
// Déclencheur déterministe : 3 échecs du MÊME engagement sur la MÊME tranche
// de journée (bloc du jour inclus). Le coach arrête de reposer le bloc tel
// quel : stats à l'appui, options de modalité tirées des faits. 0 LLM.

/// Tranche de journée d'une heure "HH:mm" : matin | midi | apres_midi | soir.
String slotBucket(String hm) {
  final h = int.tryParse(hm.split(':').first) ?? 0;
  if (h >= 5 && h < 12) return 'matin';
  if (h >= 12 && h < 14) return 'midi';
  if (h >= 14 && h < 18) return 'apres_midi';
  return 'soir';
}

/// Libellé français d'une tranche (« le matin », « le soir »…).
String bucketLabel(String bucket) => switch (bucket) {
      'matin' => 'le matin',
      'midi' => 'le midi',
      'apres_midi' => 'l\'après-midi',
      _ => 'le soir',
    };

/// Tenue/posé d'une tranche alternative — tous engagements confondus
/// (« 6/6 tenues le matin — c'est là que tu tiens »).
class SlotStats {
  final String bucket;
  final int held;
  final int total;
  final String typicalTime; // "HH:mm" le plus fréquent parmi les blocs TENUS

  const SlotStats({
    required this.bucket,
    required this.held,
    required this.total,
    required this.typicalTime,
  });
}

/// Diagnostic structurel d'un engagement qui casse toujours au même créneau.
class StructuralDiagnosis {
  final String slotHm; // "18:00" — heure récurrente qui casse
  final String bucket; // tranche du créneau qui casse
  final int fails; // échecs sur cette tranche (bloc du jour inclus)
  final int held; // tenues sur cette tranche
  final int weeklyFreq; // occurrences posées ces 7 derniers jours (jour inclus)
  final List<SlotStats> alternatives; // tranches où ça TIENT, meilleures d'abord

  const StructuralDiagnosis({
    required this.slotHm,
    required this.bucket,
    required this.fails,
    required this.held,
    required this.weeklyFreq,
    required this.alternatives,
  });

  int get total => fails + held;
}

/// [historyBlocks] : blocs des 14 derniers jours (aujourd'hui exclu), tous
/// engagements. Le bloc [b] compte comme un échec de plus sur sa tranche
/// (on ne renégocie que ce qui est en train de casser). Retourne null tant
/// que le seuil de [minFails] échecs sur la même tranche n'est pas atteint.
StructuralDiagnosis? diagnoseStructural(
  ScheduleBlock b,
  List<ScheduleBlock> historyBlocks, {
  List<ScheduleBlock>? weekBlocks, // 7 derniers jours — pour « ×N / semaine »
  int minFails = 3,
}) {
  final pool = historyBlocks
      .where((w) => w.status != 'deleted' && !w.isPrep && w.category != 'break')
      .toList();

  // Occurrences du même engagement sur la même tranche que le bloc du jour.
  final bucket = slotBucket(b.startTime);
  final atSlot = pool
      .where((w) => _sameEngagement(b, w) && slotBucket(w.startTime) == bucket)
      .toList();
  final fails = atSlot.where((w) => w.status != 'done').length + 1; // + b
  final held = atSlot.where((w) => w.status == 'done').length;
  if (fails < minFails) return null;

  // Heure récurrente = la plus fréquente parmi les occurrences qui cassent.
  final failTimes = <String, int>{b.startTime: 1};
  for (final w in atSlot.where((w) => w.status != 'done')) {
    failTimes[w.startTime] = (failTimes[w.startTime] ?? 0) + 1;
  }
  final slotHm = _mode(failTimes);

  // Tranches alternatives où l'utilisateur TIENT — tous engagements confondus.
  final alternatives = <SlotStats>[];
  for (final alt in ['matin', 'midi', 'apres_midi', 'soir']) {
    if (alt == bucket) continue;
    final inBucket =
        pool.where((w) => slotBucket(w.startTime) == alt).toList();
    final done = inBucket.where((w) => w.status == 'done').toList();
    if (done.length < 2) continue; // pas assez de faits pour recommander
    if (done.length / inBucket.length < 0.6) continue; // ça ne tient pas là
    final times = <String, int>{};
    for (final w in done) {
      times[w.startTime] = (times[w.startTime] ?? 0) + 1;
    }
    alternatives.add(SlotStats(
      bucket: alt,
      held: done.length,
      total: inBucket.length,
      typicalTime: _mode(times),
    ));
  }
  alternatives.sort((a, x) {
    final ra = a.held / a.total;
    final rx = x.held / x.total;
    return rx != ra ? rx.compareTo(ra) : x.held.compareTo(a.held);
  });

  // Récurrence hebdo réelle : occurrences des 7 derniers jours (+ le bloc du
  // jour). Sans fenêtre courte fournie : fenêtre de 14 jours ramenée à 7.
  final weeklyFreq = weekBlocks != null
      ? weekBlocks
              .where((w) =>
                  w.status != 'deleted' && _sameEngagement(b, w))
              .length +
          1
      : ((pool.where((w) => _sameEngagement(b, w)).length + 1) / 2)
          .ceil()
          .clamp(1, 7);

  return StructuralDiagnosis(
    slotHm: slotHm,
    bucket: bucket,
    fails: fails,
    held: held,
    weeklyFreq: weeklyFreq,
    alternatives: alternatives,
  );
}

String _mode(Map<String, int> counts) {
  var best = '';
  var bestN = 0;
  final keys = counts.keys.toList()..sort();
  for (final k in keys) {
    if (counts[k]! > bestN) {
      best = k;
      bestN = counts[k]!;
    }
  }
  return best;
}
