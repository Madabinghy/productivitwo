/// Braises (maquette validée 2026-10-30) : une journée parfaite forge une
/// braise (réserve plafonnée à [kEmberCap]) ; une braise rallume une série de
/// routine cassée HIER, à condition d'atteindre la routine aujourd'hui. Le jour
/// comblé compte pour la série seulement, jamais pour les journées parfaites ou
/// solides. Une série ne se rallume qu'une fois tous les
/// [kRekindleCooldownDays] jours.
///
/// Stockage : `data/meta.emberSpends` = liste de [EmberSpend]. La réserve n'est
/// jamais stockée : elle se recalcule depuis les journées parfaites et les
/// rallumages effectifs. Un rallumage dont la routine n'a pas été atteinte le
/// jour même ne coûte rien (la braise « revient »).
const kEmberCap = 3;
const kRekindleCooldownDays = 30;
const kEmberSpendsKept = 60;

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime _parse(String ymd) => DateTime.parse(ymd);
String ymdShift(String ymd, int days) {
  final d = _parse(ymd);
  return _ymd(DateTime(d.year, d.month, d.day + days));
}

class EmberSpend {
  final String activityId;
  /// Jour comblé (la veille de [spentYmd]).
  final String lostYmd;
  /// Jour du rallumage : la routine doit y être atteinte.
  final String spentYmd;
  const EmberSpend({required this.activityId, required this.lostYmd, required this.spentYmd});

  Map<String, dynamic> toJson() => {'activityId': activityId, 'lostYmd': lostYmd, 'spentYmd': spentYmd};

  static EmberSpend? from(dynamic raw) {
    if (raw is! Map) return null;
    final a = raw['activityId'], l = raw['lostYmd'], s = raw['spentYmd'];
    if (a is! String || l is! String || s is! String) return null;
    if (DateTime.tryParse(l) == null || DateTime.tryParse(s) == null) return null;
    return EmberSpend(activityId: a, lostYmd: l, spentYmd: s);
  }

  static List<EmberSpend> listFrom(dynamic raw) =>
      raw is List ? [for (final x in raw) if (EmberSpend.from(x) case final s?) s] : const [];
}

enum EmberEventKind { earned, capped, spent }

class EmberEvent {
  final EmberEventKind kind;
  final String ymd;
  final String? activityId;
  const EmberEvent(this.kind, this.ymd, {this.activityId});
}

class EmberLedger {
  /// Braises en réserve, rallumages effectifs déduits.
  final int stock;
  /// Rallumage du jour encore en attente (routine pas atteinte) : réserve une braise.
  final EmberSpend? pending;
  /// Jours comblés par routine (rallumages effectifs) : la série les compte.
  final Map<String, Set<String>> bridged;
  /// Rallumages effectifs ou en attente (pour la règle des 30 jours).
  final List<EmberSpend> used;
  /// Du plus récent au plus ancien.
  final List<EmberEvent> history;
  /// Journées parfaites closes (pour recalculer le registre sans le deck).
  final List<String> perfectYmds;
  const EmberLedger({this.stock = 0, this.pending, this.bridged = const {}, this.used = const [], this.history = const [], this.perfectYmds = const []});

  /// Braises encore libres aujourd'hui.
  int get available => (stock - (pending == null ? 0 : 1)).clamp(0, kEmberCap);
  static const empty = EmberLedger();
}

/// Rejoue les journées parfaites et les rallumages dans l'ordre. Le même jour,
/// un rallumage passe avant la braise forgée ce jour-là (elle n'est acquise
/// qu'à la bascule). [reached] = jours atteints par routine (sans les jours
/// comblés) ; [perfectYmds] = journées closes parfaites.
EmberLedger emberLedger({
  required Iterable<String> perfectYmds,
  required List<EmberSpend> spends,
  required Map<String, Set<String>> reached,
  required String todayYmd,
}) {
  final perfect = perfectYmds.where((d) => d.compareTo(todayYmd) < 0).toSet();
  final dates = {...perfect, for (final s in spends) s.spentYmd}.toList()..sort();
  final bySpentDay = <String, List<EmberSpend>>{};
  for (final s in spends) {
    bySpentDay.putIfAbsent(s.spentYmd, () => []).add(s);
  }
  var stock = 0;
  EmberSpend? pending;
  final bridged = <String, Set<String>>{};
  final used = <EmberSpend>[];
  final history = <EmberEvent>[];
  final rekindledOn = <String, String>{};
  for (final d in dates) {
    for (final s in bySpentDay[d] ?? const <EmberSpend>[]) {
      if (s.lostYmd != ymdShift(s.spentYmd, -1)) continue;
      final last = rekindledOn[s.activityId];
      if (last != null && _parse(s.spentYmd).difference(_parse(last)).inDays < kRekindleCooldownDays) continue;
      final done = reached[s.activityId]?.contains(s.spentYmd) ?? false;
      if (stock <= 0) continue;
      if (done) {
        stock--;
        bridged.putIfAbsent(s.activityId, () => {}).add(s.lostYmd);
        used.add(s);
        rekindledOn[s.activityId] = s.spentYmd;
        history.add(EmberEvent(EmberEventKind.spent, s.spentYmd, activityId: s.activityId));
      } else if (s.spentYmd == todayYmd && pending == null) {
        pending = s;
        used.add(s);
        rekindledOn[s.activityId] = s.spentYmd;
      }
    }
    if (perfect.contains(d)) {
      if (stock < kEmberCap) {
        stock++;
        history.add(EmberEvent(EmberEventKind.earned, d));
      } else {
        history.add(EmberEvent(EmberEventKind.capped, d));
      }
    }
  }
  return EmberLedger(stock: stock, pending: pending, bridged: bridged, used: used, history: history.reversed.toList(), perfectYmds: perfect.toList()..sort());
}

/// Une série cassée hier, et si elle peut être rallumée.
class LostSeries {
  final String activityId;
  final String name;
  /// Longueur de la série tenue jusqu'à avant-hier (jours comblés compris).
  final int length;
  /// Prochain palier de la série, s'il en reste un.
  final int? nextTier;
  /// Rallumage armé aujourd'hui, braise en attente du +1.
  final bool pending;
  /// Raison qui empêche de rallumer (null = rallumable).
  final String? blocked;
  const LostSeries({required this.activityId, required this.name, required this.length, this.nextTier, this.pending = false, this.blocked});
  bool get rekindlable => blocked == null && !pending;
}

/// [skip] = jours gelés par une veille : enjambés, jamais comptés.
int _runEndingAt(Set<String> days, String ymd, {Set<String> skip = const {}}) {
  var n = 0;
  var d = ymd;
  var guard = 0;
  while (guard++ < 4000) {
    if (days.contains(d)) {
      n++;
    } else if (!skip.contains(d)) {
      break;
    }
    d = ymdShift(d, -1);
  }
  return n;
}

/// Les séries cassées hier ([todayYmd] − 1) : routine atteinte avant-hier (série
/// ≥ 1, jours comblés compris) et pas hier. [routines] = (id, nom) des routines
/// quotidiennes actives ; [tiers] = paliers des séries ; [frozen] = jours gelés
/// par une veille, par routine (hier gelé = rien de perdu).
List<LostSeries> lostYesterday({
  required List<(String id, String name)> routines,
  required Map<String, Set<String>> reached,
  required EmberLedger ledger,
  required String todayYmd,
  List<int> tiers = const [3, 7, 21, 66, 100],
  Map<String, Set<String>> frozen = const {},
}) {
  final yesterday = ymdShift(todayYmd, -1);
  final before = ymdShift(todayYmd, -2);
  final out = <LostSeries>[];
  for (final (id, name) in routines) {
    final days = {...?reached[id], ...?ledger.bridged[id]};
    final skip = frozen[id] ?? const <String>{};
    if (days.contains(yesterday) || skip.contains(yesterday)) continue;
    final len = _runEndingAt(days, before, skip: skip);
    if (len <= 0) continue;
    final next = tiers.where((t) => t > len).firstOrNull;
    final pending = ledger.pending?.activityId == id;
    String? blocked;
    if (!pending) {
      final last = ledger.used.where((s) => s.activityId == id).map((s) => s.spentYmd).fold<String?>(null, (m, d) => m == null || d.compareTo(m) > 0 ? d : m);
      if (last != null && _parse(todayYmd).difference(_parse(last)).inDays < kRekindleCooldownDays) {
        blocked = 'déjà rallumée le ${_short(last)} · une fois par mois';
      } else if (ledger.pending != null) {
        blocked = 'une braise est déjà en attente aujourd’hui';
      } else if (ledger.available <= 0) {
        blocked = 'aucune braise en réserve';
      }
    }
    out.add(LostSeries(activityId: id, name: name, length: len, nextTier: next, pending: pending, blocked: blocked));
  }
  out.sort((a, b) {
    if (a.rekindlable != b.rekindlable) return a.rekindlable ? -1 : 1;
    return b.length.compareTo(a.length);
  });
  return out;
}

String _short(String ymd) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  final d = _parse(ymd);
  return '${d.day} ${months[d.month - 1]}';
}

/// Nouvelle liste à écrire pour rallumer [activityId] aujourd'hui (les plus
/// anciens rallumages au-delà de [kEmberSpendsKept] sont oubliés).
List<EmberSpend> withRekindle(List<EmberSpend> spends, String activityId, String todayYmd) {
  final next = [
    for (final s in spends)
      if (!(s.activityId == activityId && s.spentYmd == todayYmd)) s,
    EmberSpend(activityId: activityId, lostYmd: ymdShift(todayYmd, -1), spentYmd: todayYmd),
  ];
  return next.length > kEmberSpendsKept ? next.sublist(next.length - kEmberSpendsKept) : next;
}

/// Annule le rallumage armé aujourd'hui pour [activityId] (seulement s'il est
/// encore en attente : un rallumage effectif ne se défait pas).
List<EmberSpend> withoutPending(List<EmberSpend> spends, String activityId, String todayYmd) =>
    [for (final s in spends) if (!(s.activityId == activityId && s.spentYmd == todayYmd)) s];
