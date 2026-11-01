import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/collection_badges.dart';

/// Les paliers déjà vus, par badge (cartes retournées), sur l'appareil.
/// Première fois : tout ce qui est déjà gagné compte vu (pas d'avalanche).
class CardSeenStore {
  static const _key = 'badge_cards_seen';
  static const _collKey = 'collection_badges_seen';
  static Map<String, int>? _seen;
  /// Paliers vus des badges de collection (même règle : premier passage = vus).
  static Map<String, int>? _coll;
  static bool _ready = false;

  static bool get ready => _ready;

  static Future<void> load() async {
    if (_ready) return;
    try {
      final p = await SharedPreferences.getInstance();
      final coll = p.getString(_collKey);
      if (coll != null) {
        final c = jsonDecode(coll);
        if (c is Map) _coll = {for (final e in c.entries) e.key.toString(): (e.value as num).toInt()};
      }
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is Map) _seen = {for (final e in j.entries) e.key.toString(): (e.value as num).toInt()};
    } catch (_) {
    } finally {
      _ready = true;
    }
  }

  /// Les cartes à retourner ; premier passage = tout est vu, rien à retourner.
  static List<NewCard> pending(BadgeDeck deck) {
    if (!_ready) return const [];
    if (_seen == null) {
      _seen = seenOf(deck);
      _save();
      return const [];
    }
    return newCards(deck, _seen!);
  }

  /// Badges de collection qui viennent de tomber (palier au-delà du vu).
  static List<CollectionBadge> pendingCollection(BadgeDeck deck) {
    if (!_ready) return const [];
    final all = collectionBadges(deck);
    if (_coll == null) {
      _coll = {for (final b in all) b.id: b.level};
      _saveColl();
      return const [];
    }
    return [for (final b in all) if (b.level > (_coll![b.id] ?? 0)) b];
  }

  static void markCollectionSeen(Iterable<CollectionBadge> badges) {
    final c = _coll ?? {};
    for (final b in badges) {
      if (b.level > (c[b.id] ?? 0)) c[b.id] = b.level;
    }
    _coll = c;
    _saveColl();
  }

  static Future<void> _saveColl() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_collKey, jsonEncode(_coll));
    } catch (_) {}
  }

  static bool isNew(BadgeState b) => _seen != null && b.acquired && b.level > (_seen![b.def.id] ?? 0);

  static void markSeen(Iterable<BadgeState> badges) {
    final s = _seen ?? {};
    for (final b in badges) {
      if (b.level > (s[b.def.id] ?? 0)) s[b.def.id] = b.level;
    }
    _seen = s;
    _save();
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_seen));
    } catch (_) {}
  }
}
