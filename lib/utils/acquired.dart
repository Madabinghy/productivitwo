import 'package:productivitwo_v1/utils/engagement_stats.dart' show mondayOf, ymdOf;

/// Routine acquise (maquette validée « Routine acquise », 2026-10-30) : une
/// fois le palier de 66 jours atteint, l'app propose — une seule fois — de
/// passer la routine en ACQUISE. Elle sort de la journée parfaite, des enjeux
/// du jour, du compte du matin et du rappel du soir ; elle reste cochable, sa
/// série et ses paliers continuent, et elle compte toujours dans le contrat de
/// son objectif (Ma semaine, semaines tenues, coach). Si elle DÉCROCHE (deux
/// semaines closes d'affilée sous [kSlipDays] jours tenus), une carte propose
/// de la remettre en routine active ; « C'est voulu » la fait taire
/// [kQuietWeeks] semaines. Aucun badge : le jeu recule quand l'habitude est là.
/// Stockage : `data/meta.acquired {activityId: {since, quietUntil?}}` et
/// `data/meta.acquireAsked` (ids à qui la question a déjà été posée).
const kAcquireTier = 66;
const kSlipDays = 4;
const kQuietWeeks = 4;

class Acquired {
  final String since; // YYYY-MM-DD, premier jour hors journée parfaite
  final String? quietUntil;
  const Acquired(this.since, {this.quietUntil});
  Map<String, dynamic> toJson() => {'since': since, if (quietUntil != null) 'quietUntil': quietUntil};
}

final _ymd = RegExp(r'^\d{4}-\d{2}-\d{2}$');

Map<String, Acquired> parseAcquired(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, Acquired>{};
  raw.forEach((k, v) {
    if (v is! Map) return;
    final s = v['since'], q = v['quietUntil'];
    if (s is! String || !_ymd.hasMatch(s)) return;
    out[k.toString()] = Acquired(s, quietUntil: q is String && _ymd.hasMatch(q) ? q : null);
  });
  return out;
}

Set<String> parseAcquireAsked(dynamic raw) => raw is List ? {for (final x in raw) x.toString()} : const {};

/// Acquise au jour [ymd] (le jour du passage compris).
bool isAcquiredOn(Map<String, Acquired> acquired, String id, String ymd) {
  final a = acquired[id];
  return a != null && a.since.compareTo(ymd) <= 0;
}

/// Ids acquis au jour [ymd].
Set<String> acquiredOn(Map<String, Acquired> acquired, String ymd) => {
      for (final e in acquired.entries)
        if (e.value.since.compareTo(ymd) <= 0) e.key
    };

/// La question se pose une fois la série au palier de 66 jours (sa plus longue
/// série, `longest`), à une routine pas encore acquise ni déjà interrogée.
bool shouldProposeAcquire({required String id, required int longest, required Map<String, Acquired> acquired, required Set<String> asked}) =>
    longest >= kAcquireTier && !acquired.containsKey(id) && !asked.contains(id);

/// Jours tenus des deux dernières semaines closes (la plus ancienne d'abord),
/// null si elles ne sont pas toutes deux postérieures au passage en acquise.
(int, int)? lastTwoWeeks(Set<String> reached, String since, DateTime today) {
  final thisMonday = mondayOf(today);
  final w1 = thisMonday.subtract(const Duration(days: 14));
  final w2 = thisMonday.subtract(const Duration(days: 7));
  if (ymdOf(w1).compareTo(since) < 0) return null;
  int count(DateTime m) => [for (var i = 0; i < 7; i++) ymdOf(DateTime(m.year, m.month, m.day + i))].where(reached.contains).length;
  return (count(w1), count(w2));
}

/// Décroche : deux semaines closes d'affilée sous [kSlipDays] jours tenus,
/// hors période « c'est voulu ».
bool isSlipping(Acquired a, Set<String> reached, DateTime today) {
  final t = ymdOf(today);
  if (a.quietUntil != null && a.quietUntil!.compareTo(t) >= 0) return false;
  final w = lastTwoWeeks(reached, a.since, today);
  return w != null && w.$1 < kSlipDays && w.$2 < kSlipDays;
}

String quietUntilFrom(DateTime today) => ymdOf(today.add(const Duration(days: kQuietWeeks * 7)));
