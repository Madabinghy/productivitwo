import 'package:shared_preferences/shared_preferences.dart';

/// Dernier onglet choisi (Focus ou Tout) des lanceurs de routines et
/// d'activités (retour user 2026-11-01) : rouverts sur le même onglet.
class LauncherTabStore {
  static const kRoutines = 'launcher_focus_routines';
  static const kActivities = 'launcher_focus_activities';
  static final Map<String, bool> _cache = {};

  /// Valeur en mémoire (null tant que pas lue depuis le lancement).
  static bool? peek(String key) => _cache[key];

  /// Tests : oublie les choix en mémoire.
  static void resetForTest() => _cache.clear();

  static Future<bool> load(String key) async {
    final c = _cache[key];
    if (c != null) return c;
    try {
      final p = await SharedPreferences.getInstance();
      return _cache[key] = p.getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> save(String key, bool focus) async {
    _cache[key] = focus;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, focus);
    } catch (_) {}
  }
}
