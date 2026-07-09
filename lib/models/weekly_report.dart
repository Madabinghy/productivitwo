part of '../models.dart';

// ─── RAPPORT HEBDO (phase 2, maquettes 16a/16b/16c) ──────────────────────────
//
// Doc users/{uid}/weekly_reports/{lundi YYYY-MM-DD}, généré côté serveur :
// agrégats 100 % déterministes + narratif/question (1 appel, classe
// quotidienne). La décision proposée n'est appliquée aux modalités du domaine
// que si l'utilisateur valide (« Oui — on réorganise »).

class ReportVital {
  String label;
  int done;
  int target;
  ReportVital({required this.label, this.done = 0, this.target = 0});

  static ReportVital from(Map j) => ReportVital(
        label: j['label'] ?? '',
        done: (j['done'] as num?)?.toInt() ?? 0,
        target: (j['target'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'label': label, 'done': done, 'target': target};
}

class ReportDomainFact {
  String domainId;
  String name;
  String intention;
  List<ReportVital> vitals;
  ReportDomainFact({
    required this.domainId,
    required this.name,
    this.intention = '',
    List<ReportVital>? vitals,
  }) : vitals = vitals ?? [];

  bool get vitalHeld =>
      vitals.isNotEmpty && vitals.every((v) => v.done >= v.target);

  static ReportDomainFact from(Map j) => ReportDomainFact(
        domainId: j['domainId'] ?? '',
        name: j['name'] ?? '',
        intention: j['intention'] ?? '',
        vitals: (j['vitals'] as List?)
                ?.whereType<Map>()
                .map(ReportVital.from)
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'domainId': domainId,
        'name': name,
        'intention': intention,
        'vitals': vitals.map((v) => v.toJson()).toList(),
      };
}

class ReportMotif {
  String cause;
  int count;
  int brokenTotal;
  List<String> hours; // "14:00", …
  List<Map<String, dynamic>> samples; // {weekday, time, held}

  ReportMotif({
    required this.cause,
    this.count = 0,
    this.brokenTotal = 0,
    List<String>? hours,
    List<Map<String, dynamic>>? samples,
  })  : hours = hours ?? [],
        samples = samples ?? [];

  /// « toujours entre 14 h et 16 h » — calculé des heures réelles.
  String get hoursLabel {
    if (hours.isEmpty) return '';
    final hs = hours.map((h) => int.tryParse(h.split(':').first) ?? 0).toList();
    final min = hs.reduce((a, b) => a < b ? a : b);
    final max = hs.reduce((a, b) => a > b ? a : b);
    return min == max
        ? 'toujours vers $min h'
        : 'toujours entre $min h et $max h';
  }

  static ReportMotif from(Map j) => ReportMotif(
        cause: j['cause'] ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        brokenTotal: (j['brokenTotal'] as num?)?.toInt() ?? 0,
        hours: (j['hours'] as List?)?.map((e) => e.toString()).toList(),
        samples: (j['samples'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'cause': cause,
        'count': count,
        'brokenTotal': brokenTotal,
        'hours': hours,
        'samples': samples,
      };
}

class WeeklyDecision {
  String? domainId;
  String domainName;
  String from;
  String to;
  String reason;

  WeeklyDecision({
    this.domainId,
    this.domainName = '',
    this.from = '',
    this.to = '',
    this.reason = '',
  });

  static WeeklyDecision fromJson(Map j) => WeeklyDecision(
        domainId: j['domainId'],
        domainName: j['domainName'] ?? '',
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        reason: j['reason'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'domainId': domainId,
        'domainName': domainName,
        'from': from,
        'to': to,
        'reason': reason,
      };
}

class WeeklyReport {
  String weekStart; // lundi YYYY-MM-DD — id du doc
  String weekEnd;
  int isoWeek;
  String kind; // "full" | "short" (17b = PR 4)
  DateTime generatedAt;
  int held;
  int total;
  int checkinsDone;
  List<ReportDomainFact> domains;
  List<ReportMotif> motifs;
  String narrative;
  String? question;
  WeeklyDecision? proposedDecision;
  String decisionStatus; // none | pending | applied | declined

  WeeklyReport({
    required this.weekStart,
    this.weekEnd = '',
    this.isoWeek = 0,
    this.kind = 'full',
    DateTime? generatedAt,
    this.held = 0,
    this.total = 0,
    this.checkinsDone = 0,
    List<ReportDomainFact>? domains,
    List<ReportMotif>? motifs,
    this.narrative = '',
    this.question,
    this.proposedDecision,
    this.decisionStatus = 'none',
  })  : generatedAt = generatedAt ?? DateTime.now(),
        domains = domains ?? [],
        motifs = motifs ?? [];

  static WeeklyReport from(Map j) {
    final facts = (j['facts'] as Map?) ?? {};
    final engagements = (facts['engagements'] as Map?) ?? {};
    return WeeklyReport(
      weekStart: j['weekStart'] ?? j['id'] ?? '',
      weekEnd: j['weekEnd'] ?? facts['weekEnd'] ?? '',
      isoWeek: (j['isoWeek'] as num?)?.toInt() ??
          (facts['isoWeek'] as num?)?.toInt() ??
          0,
      kind: j['kind'] ?? 'full',
      generatedAt: _parseDate(j['generatedAt']),
      held: (engagements['held'] as num?)?.toInt() ?? 0,
      total: (engagements['total'] as num?)?.toInt() ?? 0,
      checkinsDone: (facts['checkinsDone'] as num?)?.toInt() ?? 0,
      domains: (facts['domains'] as List?)
              ?.whereType<Map>()
              .map(ReportDomainFact.from)
              .toList() ??
          [],
      motifs: (facts['motifs'] as List?)
              ?.whereType<Map>()
              .map(ReportMotif.from)
              .toList() ??
          [],
      narrative: j['narrative'] ?? '',
      question: j['question'],
      proposedDecision: j['proposedDecision'] is Map
          ? WeeklyDecision.fromJson(j['proposedDecision'] as Map)
          : null,
      decisionStatus: j['decisionStatus'] ?? 'none',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': weekStart,
        'weekStart': weekStart,
        'weekEnd': weekEnd,
        'isoWeek': isoWeek,
        'kind': kind,
        'generatedAt': generatedAt.toIso8601String(),
        'facts': {
          'weekStart': weekStart,
          'weekEnd': weekEnd,
          'isoWeek': isoWeek,
          'engagements': {'held': held, 'total': total},
          'checkinsDone': checkinsDone,
          'domains': domains.map((d) => d.toJson()).toList(),
          'motifs': motifs.map((m) => m.toJson()).toList(),
        },
        'narrative': narrative,
        'question': question,
        'proposedDecision': proposedDecision?.toJson(),
        'decisionStatus': decisionStatus,
      };
}
