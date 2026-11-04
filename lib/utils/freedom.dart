import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;

/// Liberté (2026-11-04, maquette validée « Sortir d'une dépendance ») : UNE chose qu'on veut arrêter ou
/// réduire. L'app ne nomme aucune dépendance : la personne donne le nom qu'elle veut. On ne compte pas les
/// chutes, on compte les victoires : chaque envie surmontée reste acquise, même après un écart.
/// Stockage `data/meta.freedoms.<id> {plan, urges: {<id>: …}, slips: {<id>: …}}` (une par chose). Privé (jamais montré au coach
/// sans un consentement à part, lot 3).

enum FreedomGoal { stop, reduce }

enum FreedomPeriod { day, week }

/// Caps neutres, en jours de liberté d'affilée.
const kFreedomMilestones = [1, 3, 7, 14, 30, 60, 90, 180, 365];

/// Une envie « passe en 10 min » : le minuteur du moment de l'envie.
const kUrgeWaveSec = 600;

class FreedomPlan {
  final String name;
  final FreedomGoal goal;
  /// Réduire : la limite par période (« 3 par semaine »).
  final int? limit;
  final FreedomPeriod period;
  /// Ce qu'on compte, facultatif (« fois », « verres », « minutes »).
  final String unit;
  final String startYmd;
  /// Ce que ça coûte par jour, en centimes (facultatif).
  final int? costPerDay;
  final String why;
  final List<String> triggers;
  final List<String> parades;
  final String? supportName;
  final String? supportPhone;
  /// Mise en garde « si ton corps en dépend » déjà montrée.
  final bool warned;
  const FreedomPlan({
    required this.name,
    this.goal = FreedomGoal.stop,
    this.limit,
    this.period = FreedomPeriod.week,
    this.unit = 'fois',
    required this.startYmd,
    this.costPerDay,
    this.why = '',
    this.triggers = const [],
    this.parades = const [],
    this.supportName,
    this.supportPhone,
    this.warned = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'goal': goal.name,
        if (limit != null) 'limit': limit,
        'period': period.name,
        'unit': unit,
        'startYmd': startYmd,
        if (costPerDay != null) 'costPerDay': costPerDay,
        if (why.isNotEmpty) 'why': why,
        'triggers': triggers,
        'parades': parades,
        if (supportName != null && supportName!.isNotEmpty) 'supportName': supportName,
        if (supportPhone != null && supportPhone!.isNotEmpty) 'supportPhone': supportPhone,
        if (warned) 'warned': true,
      };

  static FreedomPlan? fromJson(dynamic j) {
    if (j is! Map || j['name'] is! String || j['startYmd'] is! String) return null;
    List<String> strs(dynamic v) => v is List ? [for (final x in v) if (x is String && x.trim().isNotEmpty) x] : const [];
    return FreedomPlan(
      name: j['name'] as String,
      goal: j['goal'] == 'reduce' ? FreedomGoal.reduce : FreedomGoal.stop,
      limit: (j['limit'] as num?)?.toInt(),
      period: j['period'] == 'day' ? FreedomPeriod.day : FreedomPeriod.week,
      unit: (j['unit'] as String?)?.trim().isNotEmpty == true ? j['unit'] as String : 'fois',
      startYmd: j['startYmd'] as String,
      costPerDay: (j['costPerDay'] as num?)?.toInt(),
      why: (j['why'] ?? '').toString(),
      triggers: strs(j['triggers']),
      parades: strs(j['parades']),
      supportName: j['supportName'] as String?,
      supportPhone: j['supportPhone'] as String?,
      warned: j['warned'] == true,
    );
  }

  FreedomPlan copyWith({
    String? name,
    FreedomGoal? goal,
    int? limit,
    bool clearLimit = false,
    FreedomPeriod? period,
    String? unit,
    String? startYmd,
    int? costPerDay,
    bool clearCost = false,
    String? why,
    List<String>? triggers,
    List<String>? parades,
    String? supportName,
    String? supportPhone,
    bool? warned,
  }) =>
      FreedomPlan(
        name: name ?? this.name,
        goal: goal ?? this.goal,
        limit: clearLimit ? null : (limit ?? this.limit),
        period: period ?? this.period,
        unit: unit ?? this.unit,
        startYmd: startYmd ?? this.startYmd,
        costPerDay: clearCost ? null : (costPerDay ?? this.costPerDay),
        why: why ?? this.why,
        triggers: triggers ?? this.triggers,
        parades: parades ?? this.parades,
        supportName: supportName ?? this.supportName,
        supportPhone: supportPhone ?? this.supportPhone,
        warned: warned ?? this.warned,
      );
}

/// Une envie : sa force (1 à 5), ce qui l'a déclenchée, la parade essayée, et si elle est passée.
class FreedomUrge {
  final String id;
  final int at; // ms
  final int intensity;
  final String? trigger;
  final String? parade;
  final bool passed;
  final int? durationSec;
  const FreedomUrge({required this.id, required this.at, required this.intensity, this.trigger, this.parade, this.passed = true, this.durationSec});

  Map<String, dynamic> toJson() => {
        'at': at,
        'intensity': intensity,
        if (trigger != null) 'trigger': trigger,
        if (parade != null) 'parade': parade,
        'passed': passed,
        if (durationSec != null) 'durationSec': durationSec,
      };

  static FreedomUrge? fromJson(String id, dynamic j) {
    if (j is! Map || j['at'] is! num) return null;
    return FreedomUrge(
      id: id,
      at: (j['at'] as num).toInt(),
      intensity: ((j['intensity'] as num?)?.toInt() ?? 3).clamp(1, 5),
      trigger: j['trigger'] as String?,
      parade: j['parade'] as String?,
      passed: j['passed'] != false,
      durationSec: (j['durationSec'] as num?)?.toInt(),
    );
  }
}

/// Un écart (arrêter) ou une consommation (réduire) : combien, ce qui a poussé, et la prochaine fois.
class FreedomSlip {
  final String id;
  final int at; // ms
  final int count;
  final List<String> triggers;
  final String? next;
  const FreedomSlip({required this.id, required this.at, this.count = 1, this.triggers = const [], this.next});

  Map<String, dynamic> toJson() => {
        'at': at,
        'count': count,
        if (triggers.isNotEmpty) 'triggers': triggers,
        if (next != null && next!.isNotEmpty) 'next': next,
      };

  static FreedomSlip? fromJson(String id, dynamic j) {
    if (j is! Map || j['at'] is! num) return null;
    return FreedomSlip(
      id: id,
      at: (j['at'] as num).toInt(),
      count: ((j['count'] as num?)?.toInt() ?? 1).clamp(1, 999),
      triggers: j['triggers'] is List ? [for (final x in j['triggers'] as List) if (x is String) x] : const [],
      next: j['next'] as String?,
    );
  }
}

class Freedom {
  final FreedomPlan? plan;
  final Map<String, FreedomUrge> urges;
  final Map<String, FreedomSlip> slips;
  const Freedom({this.plan, this.urges = const {}, this.slips = const {}});

  bool get active => plan != null;
  List<FreedomUrge> get urgeList => urges.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  List<FreedomSlip> get slipList => slips.values.toList()..sort((a, b) => a.at.compareTo(b.at));

  Map<String, dynamic> toJson() => {
        if (plan != null) 'plan': plan!.toJson(),
        'urges': {for (final e in urges.entries) e.key: e.value.toJson()},
        'slips': {for (final e in slips.entries) e.key: e.value.toJson()},
      };

  Freedom copyWith({FreedomPlan? plan, bool clearPlan = false, Map<String, FreedomUrge>? urges, Map<String, FreedomSlip>? slips}) =>
      Freedom(plan: clearPlan ? null : (plan ?? this.plan), urges: urges ?? this.urges, slips: slips ?? this.slips);
}

Freedom parseFreedom(dynamic raw) {
  if (raw is! Map) return const Freedom();
  final urges = <String, FreedomUrge>{};
  if (raw['urges'] is Map) {
    for (final e in (raw['urges'] as Map).entries) {
      final u = FreedomUrge.fromJson(e.key.toString(), e.value);
      if (u != null) urges[u.id] = u;
    }
  }
  final slips = <String, FreedomSlip>{};
  if (raw['slips'] is Map) {
    for (final e in (raw['slips'] as Map).entries) {
      final s = FreedomSlip.fromJson(e.key.toString(), e.value);
      if (s != null) slips[s.id] = s;
    }
  }
  return Freedom(plan: FreedomPlan.fromJson(raw['plan']), urges: urges, slips: slips);
}

/// Plusieurs libertés (2026-11-04, retour user) : `data/meta.freedoms.<id> = {plan, urges, slips}`.
Map<String, Freedom> parseFreedoms(dynamic raw) {
  final out = <String, Freedom>{};
  if (raw is Map) {
    for (final e in raw.entries) {
      out[e.key.toString()] = parseFreedom(e.value);
    }
  }
  return out;
}

/// Les libertés suivies (plan posé), de la plus ancienne à la plus récente.
List<String> activeFreedomIds(Map<String, Freedom> all) {
  final ids = [for (final e in all.entries) if (e.value.active) e.key];
  ids.sort((a, b) {
    final c = all[a]!.plan!.startYmd.compareTo(all[b]!.plan!.startYmd);
    return c != 0 ? c : a.compareTo(b);
  });
  return ids;
}

// ── Où j'en suis ─────────────────────────────────────────────────────────────

DateTime _start(FreedomPlan p) => DateTime.parse(p.startYmd);

/// Arrêter : libre depuis le départ, ou depuis le dernier écart.
DateTime freeSince(Freedom f) {
  final p = f.plan!;
  final start = _start(p);
  final slips = f.slipList;
  if (slips.isEmpty) return start;
  final last = DateTime.fromMillisecondsSinceEpoch(slips.last.at);
  return last.isAfter(start) ? last : start;
}

/// « 12 j 6 h », « 5 h », « 20 min ».
String freeLabel(Duration d) {
  if (d.isNegative) return '0 min';
  if (d.inDays >= 1) return '${d.inDays} j${d.inHours % 24 > 0 ? ' ${d.inHours % 24} h' : ''}';
  if (d.inHours >= 1) return '${d.inHours} h';
  return '${d.inMinutes} min';
}

/// Envies surmontées : jamais perdues, même après un écart.
int urgesOvercome(Freedom f) => f.urges.values.where((u) => u.passed).length;

/// Jours de liberté depuis le départ (jours sans écart, aujourd'hui exclu tant qu'il n'est pas fini).
int freeDaysTotal(Freedom f, DateTime now) {
  final p = f.plan;
  if (p == null) return 0;
  final start = _start(p);
  final today = DateTime(now.year, now.month, now.day);
  final slipDays = {for (final s in f.slips.values) ymdOf(DateTime.fromMillisecondsSinceEpoch(s.at))};
  var n = 0;
  for (var d = start; d.isBefore(today); d = DateTime(d.year, d.month, d.day + 1)) {
    if (!slipDays.contains(ymdOf(d))) n++;
  }
  return n;
}

/// Ce qui n'a pas été dépensé (centimes). Arrêter : coût × jours sans écart. Réduire : coût par unité de la
/// limite non utilisée n'a pas de sens sans prix unitaire, donc rien.
int savedCents(Freedom f, DateTime now) {
  final p = f.plan;
  if (p == null || p.costPerDay == null || p.goal == FreedomGoal.reduce) return 0;
  return p.costPerDay! * freeDaysTotal(f, now);
}

/// Prochain cap neutre (jours d'affilée) et jours qui restent ; null au-delà du dernier.
({int days, int left})? nextMilestone(Duration free) {
  final d = free.inDays;
  for (final m in kFreedomMilestones) {
    if (m > d) return (days: m, left: m - d);
  }
  return null;
}

String milestoneLabel(int days) => switch (days) {
      1 => '1 jour',
      7 => '1 semaine',
      14 => '2 semaines',
      30 => '1 mois',
      60 => '2 mois',
      90 => '3 mois',
      180 => '6 mois',
      365 => '1 an',
      _ => '$days jours',
    };

/// Réduire : ce qui a été consommé dans la période en cours (jour ou semaine du lundi).
int usedThisPeriod(Freedom f, DateTime now) {
  final p = f.plan;
  if (p == null) return 0;
  final today = DateTime(now.year, now.month, now.day);
  final from = p.period == FreedomPeriod.day ? today : DateTime(today.year, today.month, today.day - (today.weekday - 1));
  return f.slips.values.where((s) => !DateTime.fromMillisecondsSinceEpoch(s.at).isBefore(from)).fold(0, (a, s) => a + s.count);
}

/// Réduire : au-delà de la limite = un écart.
bool overLimit(Freedom f, DateTime now) {
  final p = f.plan;
  return p != null && p.goal == FreedomGoal.reduce && p.limit != null && usedThisPeriod(f, now) > p.limit!;
}

/// Une barre par jour sur [days] jours : nombre d'envies, et si le jour a un écart.
List<({String ymd, int urges, bool slip})> urgeDays(Freedom f, DateTime now, {int days = 14}) {
  final today = DateTime(now.year, now.month, now.day);
  final byDay = <String, int>{};
  for (final u in f.urges.values) {
    final y = ymdOf(DateTime.fromMillisecondsSinceEpoch(u.at));
    byDay[y] = (byDay[y] ?? 0) + 1;
  }
  final slipDays = {for (final s in f.slips.values) ymdOf(DateTime.fromMillisecondsSinceEpoch(s.at))};
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final y = ymdOf(DateTime(today.year, today.month, today.day - i));
        return (ymd: y, urges: byDay[y] ?? 0, slip: slipDays.contains(y));
      }(),
  ];
}

/// Force moyenne des envies sur [days] jours avant [now], ou null sans envie.
double? meanIntensity(Freedom f, DateTime now, {int days = 7, int offsetDays = 0}) {
  final to = now.subtract(Duration(days: offsetDays));
  final from = to.subtract(Duration(days: days));
  final l = f.urges.values.where((u) {
    final t = DateTime.fromMillisecondsSinceEpoch(u.at);
    return t.isAfter(from) && !t.isAfter(to);
  }).toList();
  if (l.isEmpty) return null;
  return l.fold(0, (a, u) => a + u.intensity) / l.length;
}

/// Écart de force des envies, 7 derniers jours face aux 7 d'avant, en % (−40 = 40 % moins fortes).
int? intensityTrendPct(Freedom f, DateTime now) {
  final cur = meanIntensity(f, now), prev = meanIntensity(f, now, offsetDays: 7);
  if (cur == null || prev == null || prev == 0) return null;
  return ((cur - prev) / prev * 100).round();
}

// ── Ce que ça m'apprend ──────────────────────────────────────────────────────

/// Les moments de la journée de la carte des envies (début inclus, heures).
const kUrgeSlots = [6, 10, 14, 18, 22, 2];

int urgeSlotOf(DateTime t) {
  final h = t.hour;
  if (h >= 2 && h < 6) return 5;
  if (h >= 22 || h < 2) return 4;
  if (h >= 18) return 3;
  if (h >= 14) return 2;
  if (h >= 10) return 1;
  return 0;
}

/// Carte des envies : [0] = semaine, [1] = week-end ; 6 moments chacun (nombre d'envies).
List<List<int>> urgeHeat(Freedom f, DateTime now, {int days = 30}) {
  final from = now.subtract(Duration(days: days));
  final out = [List<int>.filled(6, 0), List<int>.filled(6, 0)];
  for (final u in f.urges.values) {
    final t = DateTime.fromMillisecondsSinceEpoch(u.at);
    if (t.isBefore(from) || t.isAfter(now)) continue;
    out[t.weekday >= 6 ? 1 : 0][urgeSlotOf(t)]++;
  }
  return out;
}

/// Part de chaque déclencheur dans les envies (30 jours), du plus fréquent au moins fréquent.
List<({String trigger, int count, double share})> triggerShares(Freedom f, DateTime now, {int days = 30}) {
  final from = now.subtract(Duration(days: days));
  final m = <String, int>{};
  var total = 0;
  for (final u in f.urges.values) {
    final t = DateTime.fromMillisecondsSinceEpoch(u.at);
    if (t.isBefore(from) || u.trigger == null) continue;
    m[u.trigger!] = (m[u.trigger!] ?? 0) + 1;
    total++;
  }
  final l = [for (final e in m.entries) (trigger: e.key, count: e.value, share: total == 0 ? 0.0 : e.value / total)];
  l.sort((a, b) => b.count.compareTo(a.count));
  return l;
}

/// Taux de réussite de chaque parade (envies passées / essayées), « Rien de fait » compris (parade null).
List<({String? parade, int passed, int tried})> paradeRates(Freedom f) {
  final m = <String?, ({int passed, int tried})>{};
  for (final u in f.urges.values) {
    final cur = m[u.parade] ?? (passed: 0, tried: 0);
    m[u.parade] = (passed: cur.passed + (u.passed ? 1 : 0), tried: cur.tried + 1);
  }
  final l = [for (final e in m.entries) (parade: e.key, passed: e.value.passed, tried: e.value.tried)];
  l.sort((a, b) {
    final ra = a.tried == 0 ? 0 : a.passed / a.tried, rb = b.tried == 0 ? 0 : b.passed / b.tried;
    final c = rb.compareTo(ra);
    return c != 0 ? c : b.tried.compareTo(a.tried);
  });
  return l;
}

/// La parade qui marche le mieux (au moins 3 essais), pour la mettre en avant au moment de l'envie.
String? bestParade(Freedom f) {
  for (final r in paradeRates(f)) {
    if (r.parade != null && r.tried >= 3) return r.parade;
  }
  return null;
}

/// Durée moyenne d'une envie passée (secondes), ou null.
int? meanUrgeSec(Freedom f) {
  final l = f.urges.values.where((u) => u.passed && u.durationSec != null).map((u) => u.durationSec!).toList();
  if (l.isEmpty) return null;
  return (l.reduce((a, b) => a + b) / l.length).round();
}

/// Les déclencheurs des écarts (30 jours) : « les 2 écarts » quand un déclencheur les explique tous.
Map<String, int> slipTriggers(Freedom f, DateTime now, {int days = 30}) {
  final from = now.subtract(Duration(days: days));
  final m = <String, int>{};
  for (final s in f.slips.values) {
    if (DateTime.fromMillisecondsSinceEpoch(s.at).isBefore(from)) continue;
    for (final t in s.triggers) {
      m[t] = (m[t] ?? 0) + 1;
    }
  }
  return m;
}
