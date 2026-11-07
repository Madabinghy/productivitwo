/// Le minimum (maquette validée 2026-11-06 « Journée difficile », écrans 5 à 8) : une PÉRIODE difficile. On garde
/// 2 ou 3 routines ([MinimumPeriod.keep]) ; toutes les autres sont GELÉES le temps de la période (ni cassées, ni
/// allongées ; une routine gelée faite quand même compte et allonge sa série). Une journée de la période qui tient
/// les routines gardées est une « journée tenue au minimum » : elle se gagne sous son vrai nom, jamais comme Journée
/// parfaite (le jour est neutre pour Journée parfaite, Métronome, Montre suisse, braises). Une question tous les
/// [kMinimumCheckDays] jours (« Toujours le minimum ? »). `data/meta.minimumPeriods` = liste de [MinimumPeriod].
const kMinimumCheckDays = 3;
const _kKept = 40;

final _re = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String minShift(String ymd, int days) {
  final d = DateTime.parse(ymd);
  return _ymd(DateTime(d.year, d.month, d.day + days));
}

class MinimumPeriod {
  /// Premier jour de la période (peut être hier, quand on y passe le lendemain d'une journée cassée).
  final String from;
  /// Dernier jour inclus ; null = en cours.
  final String? to;
  /// Routines gardées (ids).
  final List<String> keep;
  /// Jour où l'app redemande « Toujours le minimum ? ».
  final String checkAt;
  /// La remontée (lot 3) : après la période, les séries gelées se ravivent une à une. Vrai = remontée choisie.
  final bool climb;
  /// Routine ravivée → jour où elle compte de nouveau.
  final Map<String, String> revived;
  /// Jour où la dernière série a été ravivée (remontée finie), sinon null.
  final String? climbDone;
  /// Premier jour où les routines gardées comptent (bug user 2026-11-06 : passé au minimum le lendemain d'une journée cassée,
  /// hier doit être gelé pour TOUTES les routines, le minimum ne compte qu'à partir d'aujourd'hui).
  final String keepFrom;
  const MinimumPeriod({required this.from, this.to, required this.keep, required this.checkAt, this.climb = false, this.revived = const {}, this.climbDone, String? keepFrom})
      : keepFrom = keepFrom ?? from;

  Map<String, dynamic> toJson() => {
        'from': from,
        if (to != null) 'to': to,
        'keep': keep,
        'checkAt': checkAt,
        if (keepFrom != from) 'keepFrom': keepFrom,
        if (climb) 'climb': true,
        if (revived.isNotEmpty) 'revived': revived,
        if (climbDone != null) 'climbDone': climbDone,
      };

  static MinimumPeriod? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final f = raw['from'], t = raw['to'], c = raw['checkAt'], k = raw['keep'];
    if (f is! String || !_re.hasMatch(f)) return null;
    if (t != null && (t is! String || !_re.hasMatch(t) || t.compareTo(f) < 0)) return null;
    final rv = raw['revived'], cd = raw['climbDone'], kf = raw['keepFrom'];
    final check = c is String && _re.hasMatch(c) ? c : minShift(f, kMinimumCheckDays);
    // Période d'avant ce champ : ouverte le jour de checkAt − 3 ; si c'était le lendemain de son début (hier compris), les
    // routines gardées ne comptent qu'à partir de ce jour-là (au plus le lendemain du début).
    String legacyKeepFrom() {
      final opened = minShift(check, -kMinimumCheckDays);
      final next = minShift(f, 1);
      if (opened.compareTo(f) <= 0) return f;
      return opened.compareTo(next) < 0 ? opened : next;
    }
    return MinimumPeriod(
      from: f,
      to: t as String?,
      keep: k is List ? [for (final x in k) if (x is String) x] : const [],
      checkAt: check,
      keepFrom: kf is String && _re.hasMatch(kf) ? kf : legacyKeepFrom(),
      climb: raw['climb'] == true,
      revived: rv is Map ? {for (final e in rv.entries) if (e.key is String && e.value is String && _re.hasMatch(e.value as String)) e.key as String: e.value as String} : const {},
      climbDone: cd is String && _re.hasMatch(cd) ? cd : null,
    );
  }

  bool covers(String ymd) => from.compareTo(ymd) <= 0 && (to == null || to!.compareTo(ymd) >= 0);

  MinimumPeriod copyWith({String? to, List<String>? keep, String? checkAt, bool? climb, Map<String, String>? revived, String? climbDone}) => MinimumPeriod(
        from: from,
        to: to ?? this.to,
        keep: keep ?? this.keep,
        checkAt: checkAt ?? this.checkAt,
        climb: climb ?? this.climb,
        revived: revived ?? this.revived,
        climbDone: climbDone ?? this.climbDone,
        keepFrom: keepFrom,
      );

  /// Remontée en cours : choisie, période close, pas finie.
  bool get climbing => climb && to != null && climbDone == null;

  /// Jour de la période (1 = premier jour) au [ymd].
  int dayOf(String ymd) => DateTime.parse(ymd).difference(DateTime.parse(from)).inDays + 1;
}

List<MinimumPeriod> parseMinimumPeriods(dynamic raw) =>
    raw is List ? [for (final x in raw) if (MinimumPeriod.fromJson(x) case final p?) p] : const [];

List<Map<String, dynamic>> minimumPeriodsToJson(List<MinimumPeriod> l) => [for (final p in l) p.toJson()];

/// La période qui couvre [todayYmd], sinon null.
MinimumPeriod? currentMinimum(List<MinimumPeriod> periods, String todayYmd) {
  for (final p in periods.reversed) {
    if (p.covers(todayYmd)) return p;
  }
  return null;
}

/// La période qui couvre [ymd] (un jour passé compris), sinon null.
MinimumPeriod? minimumOn(List<MinimumPeriod> periods, String ymd) => currentMinimum(periods, ymd);

/// Jours au minimum jusqu'à [todayYmd] inclus.
Set<String> minimumDaysUpTo(List<MinimumPeriod> periods, String todayYmd) {
  final out = <String>{};
  for (final p in periods) {
    if (p.from.compareTo(todayYmd) > 0) continue;
    final end = p.to == null || p.to!.compareTo(todayYmd) > 0 ? todayYmd : p.to!;
    var d = p.from;
    var guard = 0;
    while (d.compareTo(end) <= 0 && guard++ < 400) {
      out.add(d);
      d = minShift(d, 1);
    }
  }
  return out;
}

/// Jours où [activityId] est gelée par le minimum (jours de période où elle n'est pas gardée), jusqu'à aujourd'hui,
/// plus, pendant une remontée, les jours d'après la période jusqu'à ce qu'elle soit ravivée.
/// [routine] faux = une activité chronométrée : elle revient dès le début de la remontée
/// (retour user 2026-11-07 : la Montre suisse reprend, seules les routines remontent pas à pas).
Set<String> minimumFrozenDaysOf(String activityId, List<MinimumPeriod> periods, String todayYmd, {bool routine = true}) {
  final out = <String>{};
  for (final p in periods) {
    if (p.from.compareTo(todayYmd) > 0) continue;
    if (p.keep.contains(activityId)) {
      // Gardée : gelée seulement avant keepFrom (hier pris avec le minimum).
      for (final d in minimumDaysUpTo([p], todayYmd)) {
        if (d.compareTo(p.keepFrom) < 0) out.add(d);
      }
      continue;
    }
    out.addAll(minimumDaysUpTo([p], todayYmd));
    if (!routine || !p.climb || p.to == null) continue;
    final back = p.revived[activityId] ?? p.climbDone;
    var d = minShift(p.to!, 1);
    var guard = 0;
    while (d.compareTo(todayYmd) <= 0 && (back == null || d.compareTo(back) < 0) && guard++ < 400) {
      out.add(d);
      d = minShift(d, 1);
    }
  }
  return out;
}

/// La remontée en cours, sinon null.
MinimumPeriod? currentClimb(List<MinimumPeriod> periods) {
  for (final p in periods.reversed) {
    if (p.climbing) return p;
  }
  return null;
}

/// « Ça va mieux » pas à pas : la période s'arrête hier et la remontée commence (rien ravivé encore).
List<MinimumPeriod> withClimbStarted(List<MinimumPeriod> periods, String todayYmd) {
  final ended = withMinimumEnded(periods, todayYmd);
  if (ended.isEmpty) return ended;
  final last = ended.last;
  if (last.to == null || last.to != minShift(todayYmd, -1)) return ended;
  return [...ended.sublist(0, ended.length - 1), last.copyWith(climb: true)];
}

/// Ravive [ids] aujourd'hui ; quand toutes les routines [all] (non gardées) le sont, la remontée est finie.
List<MinimumPeriod> withRevived(List<MinimumPeriod> periods, Iterable<String> ids, Iterable<String> all, String todayYmd) => [
      for (final p in periods)
        if (!p.climbing)
          p
        else
          () {
            final rv = {...p.revived, for (final id in ids) id: p.revived[id] ?? todayYmd};
            final done = all.where((id) => !p.keep.contains(id)).every(rv.containsKey);
            return p.copyWith(revived: rv, climbDone: done ? todayYmd : null);
          }(),
    ];

/// Remontées finies (badge « La remontée »).
List<String> climbsDone(List<MinimumPeriod> periods) => [for (final p in periods) if (p.climb && p.climbDone != null) p.climbDone!]..sort();

/// Ouvre une période du [fromYmd] (aujourd'hui, ou hier) avec les routines [keep]. Une période en cours est remplacée.
List<MinimumPeriod> withMinimumStarted(List<MinimumPeriod> periods, String fromYmd, List<String> keep, String todayYmd) {
  final kept = [for (final p in periods) if (!p.covers(todayYmd)) p];
  final next = [...kept, MinimumPeriod(from: fromYmd, keep: keep, checkAt: minShift(todayYmd, kMinimumCheckDays), keepFrom: todayYmd)];
  return next.length > _kKept ? next.sublist(next.length - _kKept) : next;
}

/// « Ça va mieux » : la période s'arrête hier (aujourd'hui compte normalement) ; commencée aujourd'hui, elle disparaît.
List<MinimumPeriod> withMinimumEnded(List<MinimumPeriod> periods, String todayYmd) {
  final yesterday = minShift(todayYmd, -1);
  return [
    for (final p in periods)
      if (!p.covers(todayYmd))
        p
      else if (p.from.compareTo(yesterday) <= 0)
        p.copyWith(to: yesterday),
  ];
}

/// « Encore 3 jours au minimum » : la prochaine question dans [kMinimumCheckDays] jours.
List<MinimumPeriod> withMinimumExtended(List<MinimumPeriod> periods, String todayYmd) =>
    [for (final p in periods) p.covers(todayYmd) ? p.copyWith(checkAt: minShift(todayYmd, kMinimumCheckDays)) : p];

/// Change les routines gardées de la période en cours.
List<MinimumPeriod> withMinimumKeep(List<MinimumPeriod> periods, String todayYmd, List<String> keep) =>
    [for (final p in periods) p.covers(todayYmd) ? p.copyWith(keep: keep) : p];

/// L'app doit-elle redemander « Toujours le minimum ? » aujourd'hui ?
bool minimumCheckDue(MinimumPeriod p, String todayYmd) => p.checkAt.compareTo(todayYmd) <= 0;

/// Journées tenues au minimum : jours clos d'une période où toutes les routines gardées (encore existantes) ont été
/// atteintes. [reached] = jours atteints par routine (jours comblés par une braise compris ou non, au choix de l'appelant).
List<String> minimumHeldDays(List<MinimumPeriod> periods, Map<String, Set<String>> reached, String todayYmd) {
  final out = <String>[];
  for (final d in minimumDaysUpTo(periods, minShift(todayYmd, -1)).toList()..sort()) {
    final p = minimumOn(periods, d);
    if (p == null || d.compareTo(p.keepFrom) < 0) continue;
    final keep = [for (final id in p.keep) if (reached.containsKey(id)) id];
    if (keep.isEmpty) continue;
    if (keep.every((id) => reached[id]!.contains(d))) out.add(d);
  }
  return out;
}

/// Routines proposées pour le minimum : les plus souvent tenues sur les [window] derniers jours clos, 3 au plus.
List<String> suggestMinimum(Map<String, Set<String>> reached, String todayYmd, {int window = 30, int count = 3}) {
  final days = [for (var i = 1; i <= window; i++) minShift(todayYmd, -i)];
  final scored = [
    for (final e in reached.entries) (e.key, days.where(e.value.contains).length),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored.take(count)) if (s.$2 > 0) s.$1];
}

/// Jours neutres pour Journée parfaite / Métronome / Montre suisse : la période, puis la remontée tant qu'elle dure.
Set<String> minimumNeutralDays(List<MinimumPeriod> periods, String todayYmd) {
  final out = minimumDaysUpTo(periods, todayYmd);
  for (final p in periods) {
    if (!p.climb || p.to == null) continue;
    var d = minShift(p.to!, 1);
    var guard = 0;
    while (d.compareTo(todayYmd) <= 0 && (p.climbDone == null || d.compareTo(p.climbDone!) < 0) && guard++ < 400) {
      out.add(d);
      d = minShift(d, 1);
    }
  }
  return out;
}
