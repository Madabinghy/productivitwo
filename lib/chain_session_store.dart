import 'dart:convert';
import 'package:productivitwo_v1/utils/chain_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance (appareil) de la session d'Enchaîner en attente : une seule à
/// la fois. `current` est lu de façon synchrone par MAINTENANT après `load()`.
class ChainSessionStore {
  static const _key = 'chain_pending';
  static PendingChain? current;
  static bool _loaded = false;

  static Future<PendingChain?> load() async {
    if (_loaded) return current;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      current = raw == null ? null : PendingChain.from(jsonDecode(raw));
    } catch (_) {
      current = null;
    }
    return current;
  }

  static Future<void> save(PendingChain c) async {
    current = c;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(c.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    current = null;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}
