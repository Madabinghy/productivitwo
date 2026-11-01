import 'package:productivitwo_v1/models.dart';

/// Guérilla / Offensive en attente (2026-10-30, retour user : quitter l'app
/// annulait tout) : la session est écrite sur l'appareil après chaque coup et
/// reprenable tant que la journée vécue est la même et que la dernière
/// activité date de moins de [kRunResumeWindowMin] minutes. Passé ce délai,
/// elle est close telle quelle (`expiredRunOf`) : ses coups comptent. [extra]
/// porte l'état propre au mode (coups passés, front, durée…). Logique pure ;
/// la persistance est dans `run_session_store.dart`.
const kRunResumeWindowMin = 45;

class PendingRun {
  final String kind; // kGuerillaKind | kOffensiveKind
  final String runId;
  final String date; // jour vécu, YYYY-MM-DD
  final DateTime startedAt;
  final DateTime lastActiveAt;
  final int done; // coups faits (guérilla) / gagnés (offensive)
  final Map<String, dynamic> extra;
  const PendingRun({
    required this.kind,
    required this.runId,
    required this.date,
    required this.startedAt,
    required this.lastActiveAt,
    required this.done,
    this.extra = const {},
  });

  /// [livedYmd] accepté avec ou sans tirets (`2026-10-30` / `20261030`) : la
  /// comparaison des deux formats rendait toute session « expirée » (bug du 2026-10-30).
  bool isLive(DateTime now, String livedYmd) =>
      date.replaceAll('-', '') == livedYmd.replaceAll('-', '') && now.difference(lastActiveAt).inMinutes <= kRunResumeWindowMin;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'runId': runId,
        'date': date,
        'startedAt': startedAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'done': done,
        'extra': extra,
      };

  static PendingRun? from(dynamic j) {
    if (j is! Map) return null;
    final started = DateTime.tryParse(j['startedAt']?.toString() ?? '');
    final last = DateTime.tryParse(j['lastActiveAt']?.toString() ?? '');
    final kind = j['kind']?.toString();
    final runId = j['runId']?.toString();
    final date = j['date']?.toString();
    if (started == null || last == null || kind == null || runId == null || date == null) return null;
    final extra = j['extra'];
    return PendingRun(
      kind: kind,
      runId: runId,
      date: date,
      startedAt: started,
      lastActiveAt: last,
      done: (j['done'] as num?)?.toInt() ?? 0,
      extra: extra is Map ? Map<String, dynamic>.from(extra) : const {},
    );
  }

  List<String> strings(String key) {
    final v = extra[key];
    return v is List ? v.map((e) => e.toString()).toList() : const [];
  }

  int? intOf(String key) => (extra[key] as num?)?.toInt();
}

/// La session close telle quelle, à enregistrer quand elle n'est plus
/// reprenable (null sans coup : rien à garder).
ChainRun? expiredRunOf(PendingRun p) {
  if (p.done <= 0) return null;
  return ChainRun(
    id: p.runId,
    date: p.date,
    startedAt: p.startedAt,
    endedAt: p.lastActiveAt,
    doneCount: p.done,
    total: p.intOf('total') ?? p.done,
    completed: false,
    kind: p.kind,
    bodyBefore: p.intOf('bodyBefore'),
    fullCount: p.intOf('full'),
  );
}

/// « Guérilla en cours · 2 coups » / « Offensive en cours · 3 coups ».
String pendingRunLabel(PendingRun p, {required String name}) => '$name en cours · ${p.done} coup${p.done > 1 ? 's' : ''}';
