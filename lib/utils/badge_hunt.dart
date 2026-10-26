import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;

/// Chasse aux badges (lot A, 2026-10) : viser un palier d'un badge, avec une
/// date facultative. Une chasse est une intention, jamais un jugement : pas de
/// pénalité, pas de rappel ; un badge attrapé sort de la chasse tout seul.
/// Rangées dans `data/meta.badgeHunts` ; trois au plus.
const kMaxBadgeHunts = 3;

class BadgeHunt {
  final String badgeId;
  final int tier; // palier visé, 1-based
  final String since; // YYYY-MM-DD
  final String? targetDate; // YYYY-MM-DD, facultatif
  const BadgeHunt({required this.badgeId, required this.tier, required this.since, this.targetDate});

  Map<String, dynamic> toJson() => {
        'badgeId': badgeId,
        'tier': tier,
        'since': since,
        if (targetDate != null) 'targetDate': targetDate,
      };

  static BadgeHunt? fromOrNull(dynamic j) {
    if (j is! Map) return null;
    final id = j['badgeId'];
    if (id is! String || id.isEmpty) return null;
    return BadgeHunt(
      badgeId: id,
      tier: (j['tier'] as num?)?.toInt() ?? 1,
      since: (j['since'] ?? '').toString(),
      targetDate: j['targetDate'] as String?,
    );
  }
}

/// Ce que la fiche d'un badge attend pour viser / retirer une chasse :
/// AppLogic sur mobile, `WebHuntStore` sur le web.
abstract class HuntStore {
  List<BadgeHunt> get hunts;
  Future<void> hunt(BadgeHunt h);
  Future<void> stop(Iterable<String> badgeIds);
}

List<BadgeHunt> parseBadgeHunts(dynamic raw) =>
    raw is List ? raw.map(BadgeHunt.fromOrNull).whereType<BadgeHunt>().toList() : const [];

/// Ce qui fait avancer la chasse aujourd'hui.
enum LeverKind { routine, chain, elan, reading, objective, action, time, day, none }

class HuntLever {
  final LeverKind kind;
  final String text;
  final String? activityId; // routine à cocher, activité à chronométrer
  const HuntLever(this.kind, this.text, {this.activityId});
}

class HuntView {
  final BadgeHunt hunt;
  final BadgeState badge;
  final int tierValue;
  const HuntView({required this.hunt, required this.badge, required this.tierValue});

  bool get caught => badge.level >= hunt.tier;
  num get remaining => (tierValue - badge.value).clamp(0, tierValue);
  double get progress => tierValue <= 0 ? 0 : (badge.value / tierValue).clamp(0.0, 1.0);

  /// Jours restants jusqu'à la date visée (null sans date), et rythme requis.
  int? daysLeft(DateTime now) {
    final t = hunt.targetDate == null ? null : DateTime.tryParse(hunt.targetDate!);
    if (t == null) return null;
    return t.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// « 2 par jour jusqu'au 15 nov. » pour les compteurs ; « 10 jours à tenir »
  /// pour les séries ; null si rien à dire.
  String paceLabel(DateTime now) {
    final b = badge;
    final unit = b.def.unitLong.isEmpty ? '' : ' ${b.def.unitLong}';
    final left = daysLeft(now);
    final fam = b.def.family;
    if (fam == BadgeFamily.routines || fam == BadgeFamily.days || b.def.id == 'maree-haute') {
      return '${remaining.round()} jour${remaining >= 2 ? 's' : ''} à tenir${left != null ? ' · ${_until(left)}' : ''}';
    }
    if (b.def.tiers.length == 1 && tierValue == 1) return left != null ? _until(left) : 'une fois suffit';
    if (left != null && left > 0 && remaining > 0) {
      final perDay = remaining / left;
      final p = perDay >= 1 ? '${perDay.ceil()} par jour' : 'un tous les ${(left / remaining).ceil()} jours';
      return 'encore ${_n(remaining)}$unit · $p · ${_until(left)}';
    }
    return 'encore ${_n(remaining)}$unit${left != null ? ' · ${_until(left)}' : ''}';
  }

  static String _n(num v) => v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');
  static String _until(int left) => left < 0 ? 'date passée, on continue' : (left == 0 ? 'aujourd’hui' : 'd’ici $left jour${left > 1 ? 's' : ''}');

  /// Le levier du jour, selon la famille. `todayReached` = la routine visée a
  /// atteint sa cible aujourd'hui ; `readingDue` = un relevé est attendu.
  HuntLever lever({bool todayReached = false, bool readingDue = false, int todayRoutinesDue = 0, int todayRoutinesReached = 0, int todayBlocks = 0, int todayBlocksDone = 0}) {
    final b = badge;
    final id = b.def.id;
    if (id.startsWith('serie-')) {
      return HuntLever(LeverKind.routine, todayReached ? '« ${b.def.name} » atteinte aujourd’hui, la série continue' : 'Coche « ${b.def.name} » aujourd’hui', activityId: b.def.subjectId);
    }
    if (id.startsWith('temps-')) return HuntLever(LeverKind.time, 'Lance le chrono sur une activité de « ${b.def.name} »');
    switch (id) {
      case 'journee-parfaite':
        return HuntLever(LeverKind.day, 'Aujourd’hui : $todayRoutinesReached / $todayRoutinesDue routines, $todayBlocksDone / $todayBlocks blocs · tout faire');
      case 'semaine-solide':
      case 'mois-solide':
      case 'vent-contraire':
        return HuntLever(LeverKind.day, 'Aujourd’hui : $todayRoutinesReached / $todayRoutinesDue routines, $todayBlocksDone / $todayBlocks blocs · tenir 80 %');
      case 'trajectoire':
        return const HuntLever(LeverKind.objective, 'Tiens le temps engagé cette semaine et note ton relevé');
      case 'releve-fidele':
        return HuntLever(LeverKind.reading, readingDue ? 'Un relevé est attendu : note-le aujourd’hui' : 'Prochain relevé à son échéance, sans en manquer');
      case 'cible-atteinte':
      case 'premiere-cible':
        return const HuntLever(LeverKind.objective, 'Marque l’objectif « Atteint » quand il l’est');
      case 'actions':
        return const HuntLever(LeverKind.action, 'Coche des actions : Actions, un bloc, Enchaîner');
      case 'malgre-tout':
        return const HuntLever(LeverKind.elan, 'Quand l’élan est bas, pointe-le et fais quand même une chose');
      case 'barometre':
      case 'maree-haute':
        return const HuntLever(LeverKind.elan, 'Pointe ton élan aujourd’hui');
      case 'enchaineur':
        return const HuntLever(LeverKind.chain, 'Lance un Enchaîner et mène-le jusqu’au récap');
      case 'plein-jour':
        return const HuntLever(LeverKind.chain, 'Lance Enchaîner avant le premier bloc et tiens jusqu’au dernier');
      default:
        return const HuntLever(LeverKind.none, '');
    }
  }
}

/// Les chasses appariées au deck (celles dont le badge n'existe plus sont ignorées).
List<HuntView> huntViews(List<BadgeHunt> hunts, BadgeDeck deck) => [
      for (final h in hunts)
        if (deck.byId(h.badgeId) case final b? when h.tier >= 1 && h.tier <= b.def.tiers.length)
          HuntView(hunt: h, badge: b, tierValue: b.def.tiers[h.tier - 1]),
    ];

/// Chasses attrapées (palier atteint) : à retirer, et à signaler comme visées.
List<HuntView> caughtHunts(List<BadgeHunt> hunts, BadgeDeck deck) => huntViews(hunts, deck).where((v) => v.caught).toList();

BadgeHunt newHunt(BadgeState b, int tier, DateTime now, {DateTime? targetDate}) =>
    BadgeHunt(badgeId: b.def.id, tier: tier, since: ymdOf(now), targetDate: targetDate == null ? null : ymdOf(targetDate));
