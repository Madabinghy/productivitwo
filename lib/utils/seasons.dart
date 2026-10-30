import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show mondayOf, ymdOf;

/// Saisons (lot 3 de la gamification moyen terme, 2026-10-30) : six semaines,
/// trois chasses choisies à l'ouverture et figées (on en lâche une, on ne la
/// remplace pas), un bilan à la fin. Les chasses de la saison sont aussi posées
/// dans `badgeHunts` (date visée = fin de saison) : enjeux du jour et « Badges en
/// jeu » les montrent sans rien de plus. La saison garde sa propre liste, car une
/// chasse attrapée sort de `badgeHunts`. Une saison est RÉUSSIE avec au moins
/// [kSeasonWinHunts] chasses attrapées pendant la saison : badge « Saisons ».
/// Stockage : `data/meta.seasons` (liste, la dernière peut être en cours) ; les
/// résultats ne sont jamais stockés, ils se relisent sur les dates des paliers.
const kSeasonWeeks = 6;
const kSeasonHunts = 3;
const kSeasonWinHunts = 2;
const kSeasonTiers = [1, 4, 8];
const kSeasonsKept = 40;

class SeasonHunt {
  final String badgeId;
  final int tier; // 1-based
  final String name; // nom du badge à l'ouverture (bilan même si le badge disparaît)
  const SeasonHunt({required this.badgeId, required this.tier, this.name = ''});
  Map<String, dynamic> toJson() => {'badgeId': badgeId, 'tier': tier, if (name.isNotEmpty) 'name': name};
  static SeasonHunt? fromJson(dynamic j) {
    if (j is! Map || j['badgeId'] is! String) return null;
    return SeasonHunt(badgeId: j['badgeId'] as String, tier: (j['tier'] as num?)?.toInt() ?? 1, name: (j['name'] ?? '').toString());
  }
}

class Season {
  final int n;
  final String start; // YYYY-MM-DD, jour d'ouverture
  final String end; // YYYY-MM-DD, un dimanche, inclus
  final List<SeasonHunt> hunts;
  final Set<String> dropped;
  final bool bilanSeen;
  const Season({required this.n, required this.start, required this.end, required this.hunts, this.dropped = const {}, this.bilanSeen = false});

  Map<String, dynamic> toJson() => {
        'n': n,
        'start': start,
        'end': end,
        'hunts': [for (final h in hunts) h.toJson()],
        if (dropped.isNotEmpty) 'dropped': dropped.toList(),
        if (bilanSeen) 'bilanSeen': true,
      };

  static Season? fromJson(dynamic j) {
    if (j is! Map) return null;
    final s = j['start'], e = j['end'];
    if (s is! String || e is! String || DateTime.tryParse(s) == null || DateTime.tryParse(e) == null) return null;
    final hunts = j['hunts'] is List ? [for (final x in j['hunts'] as List) if (SeasonHunt.fromJson(x) case final h?) h] : <SeasonHunt>[];
    return Season(
      n: (j['n'] as num?)?.toInt() ?? 1,
      start: s,
      end: e,
      hunts: hunts,
      dropped: j['dropped'] is List ? {for (final x in j['dropped'] as List) x.toString()} : const {},
      bilanSeen: j['bilanSeen'] == true,
    );
  }

  Season copyWith({Set<String>? dropped, bool? bilanSeen}) =>
      Season(n: n, start: start, end: end, hunts: hunts, dropped: dropped ?? this.dropped, bilanSeen: bilanSeen ?? this.bilanSeen);

  bool isOpenOn(String ymd) => start.compareTo(ymd) <= 0 && end.compareTo(ymd) >= 0;
  bool isOverOn(String ymd) => end.compareTo(ymd) < 0;
  int get totalDays => DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;
  int daysLeft(String ymd) => DateTime.parse(end).difference(DateTime.parse(ymd)).inDays.clamp(0, totalDays);
  /// Semaine en cours (1-based), calée sur les lundis à partir de l'ouverture.
  int weekOf(String ymd) => (DateTime.parse(ymd).difference(mondayOf(DateTime.parse(start))).inDays ~/ 7 + 1).clamp(1, weeks);
  int get weeks => (DateTime.parse(end).difference(mondayOf(DateTime.parse(start))).inDays ~/ 7) + 1;
  /// Part du temps écoulé (0..1), aujourd'hui compris.
  double elapsed(String ymd) => ((DateTime.parse(ymd).difference(DateTime.parse(start)).inDays + 1) / totalDays).clamp(0.0, 1.0);
}

List<Season> parseSeasons(dynamic raw) => raw is List ? [for (final x in raw) if (Season.fromJson(x) case final s?) s] : const [];

/// Fin d'une saison ouverte le [startYmd] : le dimanche de la 6ᵉ semaine pleine
/// (ouverte un lundi : ce lundi + 41 jours ; sinon le lundi suivant + 41).
String seasonEndFor(String startYmd) {
  final d = DateTime.parse(startYmd);
  final firstMonday = d.weekday == DateTime.monday ? d : mondayOf(d).add(const Duration(days: 7));
  return ymdOf(DateTime(firstMonday.year, firstMonday.month, firstMonday.day + kSeasonWeeks * 7 - 1));
}

Season? currentSeason(List<Season> seasons, String todayYmd) {
  for (final s in seasons.reversed) {
    if (s.isOpenOn(todayYmd)) return s;
  }
  return null;
}

/// Dernière saison close dont le bilan n'a pas été vu.
Season? unseenBilan(List<Season> seasons, String todayYmd) {
  for (final s in seasons.reversed) {
    if (s.isOverOn(todayYmd)) return s.bilanSeen ? null : s;
  }
  return null;
}

List<Season> withSeasonOpened(List<Season> seasons, List<SeasonHunt> hunts, String todayYmd) {
  final next = [
    for (final s in seasons) s.isOverOn(todayYmd) && !s.bilanSeen ? s.copyWith(bilanSeen: true) : s,
    Season(n: seasons.isEmpty ? 1 : seasons.map((s) => s.n).reduce((a, b) => a > b ? a : b) + 1, start: todayYmd, end: seasonEndFor(todayYmd), hunts: hunts.take(kSeasonHunts).toList()),
  ];
  return next.length > kSeasonsKept ? next.sublist(next.length - kSeasonsKept) : next;
}

List<Season> withSeasonReplaced(List<Season> seasons, Season updated) => [for (final s in seasons) s.n == updated.n ? updated : s];

enum SeasonHuntState { caught, onTrack, push, dropped, missed }

class SeasonHuntView {
  final SeasonHunt hunt;
  final BadgeState? badge;
  final SeasonHuntState state;
  final DateTime? caughtOn;
  const SeasonHuntView(this.hunt, this.badge, this.state, {this.caughtOn});

  int get target => badge == null || hunt.tier < 1 || hunt.tier > badge!.def.tiers.length ? 0 : badge!.def.tiers[hunt.tier - 1];
  num get value => badge?.value ?? 0;
  double get progress => state == SeasonHuntState.caught ? 1 : (target <= 0 ? 0 : (value / target).clamp(0.0, 1.0).toDouble());
  String get name => badge == null ? (hunt.name.isEmpty ? hunt.badgeId : hunt.name) : seasonHuntLabel(badge!, hunt.tier);
}

String seasonHuntLabel(BadgeState b, int tier) {
  final t = tier >= 1 && tier <= b.def.tiers.length ? b.def.tiers[tier - 1] : 0;
  if (b.def.tiers.length == 1 && t <= 1) return b.def.name;
  final unit = b.def.unit.isEmpty ? '' : ' ${b.def.unit}';
  return b.def.id.startsWith('serie-') ? '${b.def.name} · série $t$unit' : '${b.def.name} · ${fmtInt(t)}$unit';
}

/// État d'une chasse de [s] sur [deck] au jour [todayYmd] : attrapée (palier
/// obtenu pendant la saison), lâchée, en bonne voie (avancée ≥ 85 % du temps
/// écoulé) ou à pousser ; saison close et pas attrapée = manquée.
SeasonHuntView seasonHuntView(Season s, SeasonHunt h, BadgeDeck deck, String todayYmd) {
  final b = deck.byId(h.badgeId);
  if (s.dropped.contains(h.badgeId)) return SeasonHuntView(h, b, SeasonHuntState.dropped);
  final i = h.tier - 1;
  final d = b == null || i < 0 || i >= b.tierDates.length ? null : b.tierDates[i];
  if (d != null) {
    final y = ymdOf(d);
    if (y.compareTo(s.start) >= 0 && y.compareTo(s.end) <= 0) return SeasonHuntView(h, b, SeasonHuntState.caught, caughtOn: d);
  }
  if (s.isOverOn(todayYmd)) return SeasonHuntView(h, b, SeasonHuntState.missed);
  final v = SeasonHuntView(h, b, SeasonHuntState.onTrack);
  return v.progress >= s.elapsed(todayYmd) * 0.85 ? v : SeasonHuntView(h, b, SeasonHuntState.push);
}

List<SeasonHuntView> seasonViews(Season s, BadgeDeck deck, String todayYmd) => [for (final h in s.hunts) seasonHuntView(s, h, deck, todayYmd)];

int caughtCount(List<SeasonHuntView> views) => views.where((v) => v.state == SeasonHuntState.caught).length;

/// Saisons closes réussies (≥ [kSeasonWinHunts] chasses attrapées), avec leur
/// date de fin, de la plus ancienne à la plus récente.
List<Season> wonSeasons(List<Season> seasons, BadgeDeck deck, String todayYmd) => [
      for (final s in seasons)
        if (s.isOverOn(todayYmd) && caughtCount(seasonViews(s, deck, todayYmd)) >= kSeasonWinHunts) s
    ];

/// Paliers obtenus pendant la saison (hors séries de routine), « Méditation 21 j ».
List<String> tiersDuring(Season s, BadgeDeck deck) {
  final out = <String>[];
  for (final b in deck.badges) {
    for (var i = 0; i < b.tierDates.length && i < b.def.tiers.length; i++) {
      final d = b.tierDates[i];
      if (d == null) continue;
      final y = ymdOf(d);
      if (y.compareTo(s.start) >= 0 && y.compareTo(s.end) <= 0) out.add(seasonHuntLabel(b, i + 1));
    }
  }
  return out;
}

/// Groupe d'une proposition de chasse à l'ouverture.
enum SeasonPickGroup { objectives, reachable, restart }

class SeasonPick {
  final BadgeState badge;
  final int tier;
  final SeasonPickGroup group;
  const SeasonPick(this.badge, this.tier, this.group);
  int get target => badge.def.tiers[tier - 1];
  String get label => seasonHuntLabel(badge, tier);
  /// « encore 32 j », « 3 de plus » : ce qu'il reste.
  String get remaining {
    final left = (target - badge.value).clamp(0, target);
    final unit = badge.def.unit.isEmpty ? '' : ' ${badge.def.unit}';
    return 'encore ${fmtInt(left)}$unit';
  }
}

/// Propositions pour une saison : le prochain palier de chaque badge à paliers
/// qui peut tomber en six semaines. « De tes objectifs » = badges portés par un
/// objectif (temps, trajectoire, relevés, semaines tenues, séries des routines
/// engagées) ; « Pour repartir » = Reprise et séries cassées qui avaient tenu ;
/// le reste « À portée ». Les plus avancés d'abord, quatre par groupe au plus.
List<SeasonPick> seasonPicks(BadgeDeck deck, {Set<String> engagedRoutineIds = const {}}) {
  final out = <SeasonPick>[];
  for (final b in deck.badges) {
    final next = b.nextTarget;
    if (next == null) continue;
    final tier = b.level + 1;
    final id = b.def.id;
    if (id == 'saisons' || id == 'premiere-cible' || id == 'cible-atteinte') continue;
    final left = next - b.value;
    final serie = id.startsWith('serie-');
    if (serie && left > kSeasonWeeks * 7) continue;
    if (id == 'semaines-tenues' && left > kSeasonWeeks) continue;
    if (id == 'trajectoire' && left > kSeasonWeeks) continue;
    final SeasonPickGroup g;
    if (id == 'reprise' || (serie && b.value == 0 && b.level > 0)) {
      g = SeasonPickGroup.restart;
    } else if (id.startsWith('temps-') || id == 'trajectoire' || id == 'releve-fidele' || id == 'semaines-tenues' || (serie && engagedRoutineIds.contains(b.def.subjectId))) {
      g = SeasonPickGroup.objectives;
    } else {
      if ((b.progress ?? 0) < .25 && !serie) continue;
      g = SeasonPickGroup.reachable;
    }
    out.add(SeasonPick(b, tier, g));
  }
  out.sort((a, b) => (b.badge.progress ?? 0).compareTo(a.badge.progress ?? 0));
  final kept = <SeasonPick>[];
  for (final g in SeasonPickGroup.values) {
    kept.addAll(out.where((p) => p.group == g).take(4));
  }
  return kept;
}
