import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

/// Badges de collection (maquettes validées 2026-11-01 « Badges de
/// collection » + « Badges en écusson ») : les cartes se récoltent, les badges
/// se méritent. Chaque carte rapporte des points selon son cadre (bronze 1 ·
/// argent 2 · or 3 · légendaire 5) ; les points et les familles complètes
/// débloquent des badges, dessinés en écusson au métal du palier et montés
/// sur une plaque gravée. Tout se calcule depuis les cartes : rien de stocké.
/// Logique pure.

const kCollectorTiers = [10, 25, 50, 80, 120];
const kGoldCaseTiers = [5, 15, 30];
const kLegendTiers = [1, 3, 10];

int cardPoints(CardRarity r) => switch (r) {
      CardRarity.none => 0,
      CardRarity.bronze => 1,
      CardRarity.argent => 2,
      CardRarity.or => 3,
      CardRarity.legend => 5,
    };

/// Points de toutes les cartes gagnées (séries de routine comprises).
int collectionPoints(BadgeDeck deck) => deck.badges.fold(0, (s, b) => s + cardPoints(rarityOf(b)));

class CollectionBadge {
  final String id;
  final String name;
  /// Dessin de l'écusson (`BadgePainter.paintSymbol`).
  final String symbol;
  /// Paliers (valeurs à atteindre), du premier au dernier.
  final List<int> tiers;
  final int value;
  final int level;
  /// Texte du ruban (famille), sinon chevrons des paliers.
  final String? ribbon;
  /// Unité courte de la valeur : « pts », « or », « ★ », « cartes ».
  final String unit;
  /// Ce qu'il manque, en clair (cartes à gagner d'une famille…).
  final List<String> missing;
  /// Métal propre (famille complète : argent puis or), sinon celui du palier.
  final CardRarity? metalOverride;
  const CollectionBadge({
    required this.id,
    required this.name,
    required this.symbol,
    required this.tiers,
    required this.value,
    required this.level,
    this.ribbon,
    required this.unit,
    this.missing = const [],
    this.metalOverride,
  });

  bool get acquired => level > 0;
  bool get complete => level >= tiers.length;
  int? get next => complete ? null : tiers[level];
  double get progress => next == null ? 1 : (value / next!).clamp(0.0, 1.0).toDouble();

  /// Métal de l'écusson : le palier atteint (bronze → argent → or, le
  /// dernier est légendaire), comme les cartes.
  CardRarity get metal => metalOverride ?? rarityOf(BadgeState(def: BadgeDef(id: id, family: BadgeFamily.days, name: name, symbol: symbol, tiers: tiers), level: level, value: value));

  /// « Palier III » / « Discipline » / « Pas encore ».
  String get palier {
    if (ribbon != null) return acquired ? (level >= 2 ? 'Toutes en or' : 'Toutes gagnées') : 'Pas encore';
    if (!acquired) return 'Pas encore';
    return 'Palier ${roman(level)}';
  }

  /// Le chiffre gravé : « 50 pts », « 12 / 12 », « 5 or ».
  String get figure {
    if (ribbon != null) return level == 1 ? '$value / ${tiers.first} or' : '$value / ${tiers.first}';
    return '$value $unit';
  }

  /// « prochain 80 pts » / « tous les paliers ».
  String get nextLine => next == null ? 'tous les paliers' : 'prochain : $next $unit';
}

String roman(int n) => const ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'][n.clamp(0, 10)];

int _levelOf(List<int> tiers, int v) => tiers.where((t) => v >= t).length;

/// Libellé court d'une famille pour le ruban.
String familyRibbon(BadgeFamily f) => switch (f) {
      BadgeFamily.routines => 'SÉRIES',
      BadgeFamily.objectives => 'OBJECTIFS',
      BadgeFamily.days => 'JOURNÉES',
      BadgeFamily.discipline => 'DISCIPLINE',
      BadgeFamily.chain => 'ENCHAÎNER',
      BadgeFamily.actions => 'ACTIONS',
      BadgeFamily.time => 'TEMPS',
    };

/// Tous les badges de collection, dans l'ordre de l'étagère : Collectionneur,
/// Écrin d'or, Légende, puis une Famille complète par famille (hors séries de
/// routine, dont le nombre dépend des routines).
List<CollectionBadge> collectionBadges(BadgeDeck deck) {
  final pts = collectionPoints(deck);
  final gold = deck.badges.where((b) => rarityOf(b).index >= CardRarity.or.index).length;
  final legend = deck.badges.where((b) => rarityOf(b) == CardRarity.legend).length;
  final out = <CollectionBadge>[
    CollectionBadge(id: 'collector', name: 'Collectionneur', symbol: 'cards', tiers: kCollectorTiers, value: pts, level: _levelOf(kCollectorTiers, pts), unit: 'pts'),
    CollectionBadge(id: 'gold-case', name: 'Écrin d’or', symbol: 'chest', tiers: kGoldCaseTiers, value: gold, level: _levelOf(kGoldCaseTiers, gold), unit: 'or'),
    CollectionBadge(id: 'legend', name: 'Légende', symbol: 'crown', tiers: kLegendTiers, value: legend, level: _levelOf(kLegendTiers, legend), unit: '★'),
  ];
  for (final f in BadgeFamily.values) {
    if (f == BadgeFamily.routines) continue;
    final cards = deck.ofFamily(f).where((b) => b.def.measured).toList();
    if (cards.isEmpty) continue;
    final won = cards.where((b) => b.acquired).length;
    final goldN = cards.where((b) => rarityOf(b).index >= CardRarity.or.index).length;
    final allGold = won == cards.length && cards.every((b) => rarityOf(b).index >= CardRarity.or.index);
    final level = won < cards.length ? 0 : (allGold ? 2 : 1);
    out.add(CollectionBadge(
      id: 'family-${f.name}',
      name: '${badgeFamilyLabel(f)} au complet',
      symbol: 'crest',
      tiers: [cards.length, cards.length],
      // Toutes gagnées : la jauge suit alors les cartes en or (vers l'écusson or).
      value: level == 1 ? goldN : won,
      level: level,
      ribbon: familyRibbon(f),
      unit: 'cartes',
      missing: level == 0
          ? [for (final b in cards) if (!b.acquired) b.def.name]
          : (level == 1 ? [for (final b in cards) if (rarityOf(b).index < CardRarity.or.index) b.def.name] : const []),
      metalOverride: level == 0 ? null : (level == 2 ? CardRarity.or : CardRarity.argent),
    ));
  }
  return out;
}

/// L'étagère : badges obtenus d'abord (plus beau métal d'abord), puis les
/// plus avancés.
List<CollectionBadge> shelfOrder(List<CollectionBadge> all) => [...all]..sort((a, b) {
      if (a.acquired != b.acquired) return a.acquired ? -1 : 1;
      final m = b.metal.index.compareTo(a.metal.index);
      if (m != 0) return m;
      return b.progress.compareTo(a.progress);
    });

/// Le prochain badge à portée (pour l'en-tête de l'album) : la jauge la plus
/// avancée parmi ceux qui ont encore un palier.
CollectionBadge? nextCollectionBadge(List<CollectionBadge> all) {
  final open = all.where((b) => !b.complete).toList()..sort((a, b) => b.progress.compareTo(a.progress));
  return open.firstOrNull;
}

/// « Elle compte pour » (récolte, 2026-11-01) : les badges de collection
/// qu'une carte nourrit, avec ce qu'elle y apporte.
List<(CollectionBadge, String)> cardFeeds(BadgeState card, BadgeDeck deck) {
  final all = {for (final b in collectionBadges(deck)) b.id: b};
  final r = rarityOf(card);
  final out = <(CollectionBadge, String)>[];
  final collector = all['collector'];
  if (collector != null) {
    out.add((collector, r == CardRarity.none ? 'bronze = +1 pt' : '+${cardPoints(r)} pt${cardPoints(r) > 1 ? 's' : ''}'));
  }
  final fam = all['family-${card.def.family.name}'];
  if (fam != null) {
    final n = fam.tiers.first;
    out.add((fam, card.acquired ? '1 des $n' : 'il la faut pour le compléter'));
  }
  if (r.index >= CardRarity.or.index && all['gold-case'] != null) {
    final g = all['gold-case']!;
    out.add((g, '1 des ${g.value}'));
  }
  if (r == CardRarity.legend && all['legend'] != null) {
    final l = all['legend']!;
    out.add((l, '1 des ${l.value}'));
  }
  return out;
}
