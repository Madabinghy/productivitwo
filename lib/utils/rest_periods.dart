/// Historique des veilles (lot « Pause, record et reprise », 2026-10-30) :
/// `data/meta.restPeriods` = liste de [RestPeriod]. `restDomains` (date de fin
/// seule) reste la source de « en veille maintenant » ; les périodes servent à
/// geler les séries de routine des domaines en veille, jours passés compris.
/// Une veille commence aujourd'hui au plus tôt : jamais rétroactive (pour hier,
/// il y a les braises). Logique alignée avec `functions/src/rest_periods.ts`.
const kRestPeriodsKept = 60;

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _shift(String ymd, int days) {
  final d = DateTime.parse(ymd);
  return _ymd(DateTime(d.year, d.month, d.day + days));
}

final _ymdRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class RestPeriod {
  final String domainId;
  /// Premier jour gelé (`YYYY-MM-DD`).
  final String from;
  /// Dernier jour gelé, inclus.
  final String to;
  const RestPeriod({required this.domainId, required this.from, required this.to});

  Map<String, dynamic> toJson() => {'domainId': domainId, 'from': from, 'to': to};

  static RestPeriod? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final d = raw['domainId'], f = raw['from'], t = raw['to'];
    if (d is! String || f is! String || t is! String) return null;
    if (!_ymdRe.hasMatch(f) || !_ymdRe.hasMatch(t) || t.compareTo(f) < 0) return null;
    return RestPeriod(domainId: d, from: f, to: t);
  }

  bool covers(String ymd) => from.compareTo(ymd) <= 0 && to.compareTo(ymd) >= 0;
}

List<RestPeriod> parseRestPeriods(dynamic raw) =>
    raw is List ? [for (final x in raw) if (RestPeriod.fromJson(x) case final p?) p] : const [];

List<RestPeriod> _capped(List<RestPeriod> l) => l.length > kRestPeriodsKept ? l.sublist(l.length - kRestPeriodsKept) : l;

/// Met [domainId] en veille de [todayYmd] à [untilYmd] inclus : prolonge ou
/// raccourcit la période qui couvre aujourd'hui, sinon en ouvre une.
List<RestPeriod> withRestSet(List<RestPeriod> periods, String domainId, String todayYmd, String untilYmd) {
  if (untilYmd.compareTo(todayYmd) < 0) return periods;
  var found = false;
  final next = <RestPeriod>[];
  for (final p in periods) {
    if (!found && p.domainId == domainId && p.covers(todayYmd)) {
      found = true;
      next.add(RestPeriod(domainId: domainId, from: p.from, to: untilYmd));
    } else {
      next.add(p);
    }
  }
  if (!found) next.add(RestPeriod(domainId: domainId, from: todayYmd, to: untilYmd));
  return _capped(next);
}

/// Lève la veille de [domainId] aujourd'hui : la période en cours s'arrête
/// hier, ou disparaît si elle commençait aujourd'hui.
List<RestPeriod> withRestLifted(List<RestPeriod> periods, String domainId, String todayYmd) {
  final yesterday = _shift(todayYmd, -1);
  return [
    for (final p in periods)
      if (p.domainId == domainId && p.covers(todayYmd)) ...[
        if (p.from.compareTo(yesterday) <= 0) RestPeriod(domainId: domainId, from: p.from, to: yesterday),
      ] else
        p,
  ];
}

/// Jours gelés d'un domaine jusqu'à [todayYmd] inclus. Une veille posée sans
/// période (avant ce lot, ou par un vieux client) gèle au moins aujourd'hui.
Set<String> frozenDaysOf(String? domainId, List<RestPeriod> periods, Map<String, String> restDomains, String todayYmd) {
  if (domainId == null || domainId.isEmpty) return const {};
  final out = <String>{};
  for (final p in periods) {
    if (p.domainId != domainId || p.from.compareTo(todayYmd) > 0) continue;
    var d = p.from;
    final end = p.to.compareTo(todayYmd) < 0 ? p.to : todayYmd;
    var guard = 0;
    while (d.compareTo(end) <= 0 && guard++ < 400) {
      out.add(d);
      d = _shift(d, 1);
    }
  }
  final until = restDomains[domainId];
  if (until != null && until.compareTo(todayYmd) >= 0) out.add(todayYmd);
  return out;
}
