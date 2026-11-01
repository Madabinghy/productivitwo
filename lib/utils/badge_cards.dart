import 'package:productivitwo_v1/utils/badges_logic.dart';

/// Badges en cartes (maquette validée 2026-11-01 « Badges en cartes ») : un
/// badge devient une carte à collectionner. Le palier atteint donne la RARETÉ
/// du cadre (bronze → argent → or → légendaire, le dernier palier est
/// toujours légendaire), un badge commencé mais pas obtenu est une carte
/// grisée avec sa jauge, un badge jamais commencé est une carte de dos avec
/// un indice. Rien ne change dans le calcul des badges. Logique pure.

enum CardRarity { none, bronze, argent, or, legend }

/// Rareté d'un badge : badge simple obtenu = or ; à paliers, les paliers se
/// répartissent sur bronze → argent → or, le dernier est légendaire
/// (5 paliers : bronze, bronze, argent, or, légendaire).
CardRarity rarityOf(BadgeState b) {
  if (!b.acquired) return CardRarity.none;
  final n = b.def.tiers.length;
  if (n <= 1) return CardRarity.or;
  final l = b.level.clamp(1, n);
  if (l >= n) return CardRarity.legend;
  final i = ((l - 1) * 3) ~/ (n - 1);
  return const [CardRarity.bronze, CardRarity.argent, CardRarity.or][i.clamp(0, 2)];
}

/// La rareté que donnerait chaque palier (pour la fiche « les paliers = les cadres »).
List<CardRarity> rarityLadder(BadgeDef d) {
  final n = d.tiers.length;
  return [
    for (var l = 1; l <= n; l++) rarityOf(BadgeState(def: d, level: l, value: d.tiers[l - 1])),
  ];
}

String rarityLabel(CardRarity r) => switch (r) {
      CardRarity.none => '',
      CardRarity.bronze => 'Bronze',
      CardRarity.argent => 'Argent',
      CardRarity.or => 'Or',
      CardRarity.legend => 'Légendaire',
    };

enum CardFace { won, started, hidden }

/// Face de la carte : gagnée, commencée (grisée + jauge) ou de dos.
CardFace faceOf(BadgeState b) {
  if (b.acquired) return CardFace.won;
  if (b.value > 0) return CardFace.started;
  return CardFace.hidden;
}

/// Indice d'une carte de dos : le premier palier, en clair.
String cardHint(BadgeState b) {
  final d = b.def;
  if (!d.measured) return 'bientôt';
  final first = d.tiers.isEmpty ? 1 : d.tiers.first;
  if (d.unitLong.isNotEmpty) return '${fmtInt(first)} ${d.unitLong}';
  if (d.unit.isNotEmpty) return '${fmtInt(first)} ${d.unit}';
  return badgeFamilyLabel(d.family);
}

/// Ce qu'on lit sous le nom : « 3 / 5 j », « le 12 oct. », « complète ».
String cardFooter(BadgeState b, {required String Function(DateTime) date}) {
  if (b.complete) return 'complète';
  if (b.showGauge) return '${_num(b.value)} / ${fmtInt(b.nextTarget!)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}';
  if (b.acquired && b.obtained != null) return date(b.obtained!);
  return '';
}

String _num(num v) => v is int || v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');

/// L'album : cartes gagnées / total (une carte par badge, séries de routine
/// comprises seulement quand elles ont un palier) et le compte par rareté.
class CardAlbum {
  final int won;
  final int total;
  final Map<CardRarity, int> byRarity;
  const CardAlbum(this.won, this.total, this.byRarity);
  double get ratio => total == 0 ? 0 : won / total;
}

CardAlbum cardAlbum(BadgeDeck deck) {
  final cards = deck.counted;
  final by = <CardRarity, int>{};
  var won = 0;
  for (final b in cards) {
    final r = rarityOf(b);
    if (r == CardRarity.none) continue;
    won++;
    by[r] = (by[r] ?? 0) + 1;
  }
  return CardAlbum(won, cards.length, by);
}

/// Ordre d'une famille dans l'album : gagnées (plus rare d'abord), puis
/// commencées (plus avancée d'abord), puis de dos.
List<BadgeState> albumOrder(List<BadgeState> badges) {
  int faceRank(BadgeState b) => switch (faceOf(b)) { CardFace.won => 0, CardFace.started => 1, CardFace.hidden => 2 };
  return [...badges]..sort((a, b) {
      final f = faceRank(a).compareTo(faceRank(b));
      if (f != 0) return f;
      final r = rarityOf(b).index.compareTo(rarityOf(a).index);
      if (r != 0) return r;
      final p = (b.progress ?? 0).compareTo(a.progress ?? 0);
      if (p != 0) return p;
      return a.def.name.compareTo(b.def.name);
    });
}

/// Une carte à retourner : gagnée ou montée de rareté depuis la dernière fois.
class NewCard {
  final BadgeState badge;
  /// Rareté d'avant (none = nouvelle carte).
  final CardRarity before;
  const NewCard(this.badge, this.before);
  CardRarity get after => rarityOf(badge);
  bool get upgrade => before != CardRarity.none;
}

/// Les cartes à retourner : palier atteint au-delà de celui déjà vu
/// ([seen] = badge → palier vu). Un palier qui ne change pas la rareté se
/// retourne aussi (le cadre ne bouge pas, les points si). Ordre : la moins
/// rare d'abord, pour finir sur la plus belle.
List<NewCard> newCards(BadgeDeck deck, Map<String, int> seen) {
  final out = <NewCard>[];
  for (final b in deck.badges) {
    if (!b.acquired) continue;
    final was = seen[b.def.id] ?? 0;
    if (b.level <= was) continue;
    final before = was <= 0 ? CardRarity.none : rarityOf(BadgeState(def: b.def, level: was, value: b.def.tiers[(was - 1).clamp(0, b.def.tiers.length - 1)]));
    out.add(NewCard(b, before));
  }
  out.sort((a, c) {
    final r = a.after.index.compareTo(c.after.index);
    return r != 0 ? r : a.badge.def.name.compareTo(c.badge.def.name);
  });
  return out;
}

/// Ce qui est vu une fois les cartes retournées.
Map<String, int> seenOf(BadgeDeck deck) => {
      for (final b in deck.badges)
        if (b.acquired) b.def.id: b.level,
    };

/// « Nouvelle carte » / « Passe en or » / « Palier 7 j ».
String newCardLine(NewCard c) {
  final b = c.badge;
  if (!c.upgrade) return 'Nouvelle carte';
  if (c.after != c.before) return 'Passe en ${rarityLabel(c.after).toLowerCase()}';
  final t = b.def.tiers[(b.level - 1).clamp(0, b.def.tiers.length - 1)];
  return 'Palier ${fmtInt(t)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}';
}
