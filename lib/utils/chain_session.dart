import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Session d'Enchaîner en attente (2026-10) : sortir de l'écran ne clôt plus la
/// session, elle reste reprenable depuis MAINTENANT tant que la journée vécue
/// est la même et que la dernière activité date de moins de
/// [kChainResumeWindowMin] minutes. Une session COMPTE pour le badge
/// Enchaîneur dès [kChainCountedMin] choses faites, sortie ou pas ; « Plein
/// jour » garde seul l'exigence de la file vidée du premier au dernier bloc.
/// Logique pure ; la persistance est dans `chain_session_store.dart`.
const kChainCountedMin = 3;
const kChainResumeWindowMin = 45;
const kChainTiers = [5, 20, 50];

bool chainRunCounts(ChainRun r) => r.doneCount >= kChainCountedMin;

/// « Session comptée · 4 choses » / « Encore 1 chose pour qu'elle compte ».
String chainCountLine(int doneCount) {
  if (doneCount >= kChainCountedMin) return 'Session comptée · $doneCount chose${doneCount > 1 ? 's' : ''}';
  final left = kChainCountedMin - doneCount;
  return 'Encore $left chose${left > 1 ? 's' : ''} pour qu\'elle compte';
}

class PendingChain {
  final String runId;
  final String date; // jour vécu du programme, YYYY-MM-DD
  final DateTime startedAt;
  final DateTime lastActiveAt;
  final int doneCount;
  final List<DateTime> doneAts;
  final List<String> deferred;
  final Set<String> dismissed;
  final Set<String> finishedBlocks;
  final String? firstBlockId;
  final String? lastBlockId;
  final int totalAtStart;
  const PendingChain({
    required this.runId,
    required this.date,
    required this.startedAt,
    required this.lastActiveAt,
    required this.doneCount,
    required this.doneAts,
    required this.deferred,
    required this.dismissed,
    required this.finishedBlocks,
    required this.firstBlockId,
    required this.lastBlockId,
    required this.totalAtStart,
  });

  /// Reprenable : même journée vécue et moins de 45 min d'inactivité.
  bool isLive(DateTime now, String livedYmd) => date == livedYmd && now.difference(lastActiveAt).inMinutes <= kChainResumeWindowMin;

  Map<String, dynamic> toJson() => {
        'runId': runId,
        'date': date,
        'startedAt': startedAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'doneCount': doneCount,
        'doneAts': doneAts.map((d) => d.toIso8601String()).toList(),
        'deferred': deferred,
        'dismissed': dismissed.toList(),
        'finishedBlocks': finishedBlocks.toList(),
        'firstBlockId': firstBlockId,
        'lastBlockId': lastBlockId,
        'totalAtStart': totalAtStart,
      };

  static PendingChain? from(dynamic j) {
    if (j is! Map) return null;
    final started = DateTime.tryParse(j['startedAt']?.toString() ?? '');
    final last = DateTime.tryParse(j['lastActiveAt']?.toString() ?? '');
    final runId = j['runId']?.toString();
    final date = j['date']?.toString();
    if (started == null || last == null || runId == null || date == null) return null;
    List<String> strs(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
    return PendingChain(
      runId: runId,
      date: date,
      startedAt: started,
      lastActiveAt: last,
      doneCount: (j['doneCount'] as num?)?.toInt() ?? 0,
      doneAts: [for (final s in strs(j['doneAts'])) if (DateTime.tryParse(s) case final d?) d],
      deferred: strs(j['deferred']),
      dismissed: strs(j['dismissed']).toSet(),
      finishedBlocks: strs(j['finishedBlocks']).toSet(),
      firstBlockId: j['firstBlockId']?.toString(),
      lastBlockId: j['lastBlockId']?.toString(),
      totalAtStart: (j['totalAtStart'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ce qui a été fait PENDANT la pause et entre dans la session à la reprise :
/// blocs du programme passés « fait » entre [since] et [now] (hors ceux que la
/// file avait déjà épuisés), routines quotidiennes dont la cible du jour vécu a
/// été atteinte par un +1 de la fenêtre. Renvoie les instants.
List<DateTime> resumedDoneAts(
  List<ScheduleBlock> blocks,
  List<HabitHit> hits,
  List<Activity> activities, {
  required DateTime since,
  required DateTime now,
  required int dayStartMin,
  Set<String> finishedBlocks = const {},
}) {
  final out = <DateTime>[];
  for (final b in blocks) {
    final t = b.doneAt;
    if (b.status != 'done' || t == null || finishedBlocks.contains(b.id)) continue;
    if (t.isAfter(since) && !t.isAfter(now)) out.add(t);
  }
  final ymd = ymdOf(livedDate(now, dayStartMin));
  for (final a in activities) {
    if (a.deleted || !a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    final target = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
    final dayHits = hits.where((h) => h.habitId == a.id && ymdOf(livedDate(h.ts, dayStartMin)) == ymd).toList()..sort((x, y) => x.ts.compareTo(y.ts));
    if (dayHits.length < target) continue;
    final reachedAt = dayHits[target - 1].ts;
    if (reachedAt.isAfter(since) && !reachedAt.isAfter(now)) out.add(reachedAt);
  }
  out.sort();
  return out;
}
