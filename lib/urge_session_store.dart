import 'dart:convert';
import 'package:productivitwo_v1/utils/urge_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance (appareil) de l'envie en cours : une seule à la fois.
class UrgeSessionStore {
  static const _key = 'urge_pending';
  static PendingUrge? current;
  static bool _loaded = false;

  /// L'envie en cours, ou null ; une envie trop ancienne est oubliée.
  static Future<PendingUrge?> load() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString(_key);
        current = raw == null ? null : PendingUrge.from(jsonDecode(raw));
      } catch (_) {
        current = null;
      }
    }
    if (current != null && current!.isStale(DateTime.now())) await clear();
    return current;
  }

  static Future<void> save(PendingUrge u) async {
    current = u;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(u.toJson()));
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
