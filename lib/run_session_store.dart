import 'dart:convert';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart' show Session;
import 'package:productivitwo_v1/utils/run_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance (appareil) de la Guérilla / Offensive en attente : une seule à
/// la fois. `current` est lu de façon synchrone après `load()`.
class RunSessionStore {
  static const _key = 'run_pending';
  static PendingRun? current;
  static bool _loaded = false;

  static Future<PendingRun?> load() async {
    if (_loaded) return current;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      current = raw == null ? null : PendingRun.from(jsonDecode(raw));
    } catch (_) {
      current = null;
    }
    return current;
  }

  static Future<void> save(PendingRun r) async {
    current = r;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(r.toJson()));
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

  /// La session reprenable, ou null ; une session expirée est close
  /// (enregistrée telle quelle) puis oubliée.
  static Future<PendingRun?> live(AppLogic logic) async {
    final p = await load();
    if (p == null) return null;
    if (p.isLive(DateTime.now(), logic.livedTodayYmd)) return p;
    await closeAsIs(logic, p);
    return null;
  }

  /// Termine la session telle quelle : ses coups comptent ; le chrono d'un
  /// coup resté ouvert (app tuée en plein coup) s'arrête.
  static Future<void> closeAsIs(AppLogic logic, PendingRun p) async {
    if (logic.state.sessions.any((s) => s.endAt == null && !s.startAt.isBefore(p.startedAt))) logic.stopActive(notify: false);
    final run = expiredRunOf(p);
    if (run != null) {
      logic.recordChainRun(run);
      logic.sync?.saveChainRun(run);
    }
    await clear();
  }
}

/// Un coup passé ou fait en moins d'une minute ne laisse pas de session « 0 min »
/// dans les chronos (retour user 2026-10-30 : « Courir · 0 min » après « Pas ça »).
void dropShortSession(AppLogic logic, Session? s) {
  if (s == null || s.endAt == null || s.endAt!.difference(s.startAt).inSeconds >= 60) return;
  logic.deleteSession(s.id);
  logic.sync?.deleteSession(s.id);
}
