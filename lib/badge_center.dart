import 'package:flutter/foundation.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:shared_preferences/shared_preferences.dart';

/// Le deck de badges de la personne, calculé à la demande (lot 3, 2026-10) :
/// programmes des 400 derniers jours, projets et objectifs relus au plus une
/// fois toutes les cinq minutes, le reste depuis l'état local. Garde aussi la
/// mémoire des paliers déjà SIGNALÉS dans Aujourd'hui (`badge_signals_seen`,
/// SharedPreferences) : un déblocage se montre une fois, jamais deux ; au tout
/// premier calcul, tout l'acquis est réputé vu (pas de rafale au premier lancement).
class BadgeCenter extends ChangeNotifier {
  final AppLogic logic;
  final FirestoreSync sync;
  BadgeCenter({required this.logic, required this.sync});

  static const _seenKey = 'badge_signals_seen';
  static const _ttl = Duration(minutes: 5);

  BadgeDeck? deck;
  List<DailySchedule> _schedules = const [];
  List<Project> _projects = const [];
  List<StrategicObjective> _objectives = const [];
  DateTime? _fetchedAt;
  Future<BadgeDeck>? _inflight;

  Future<BadgeDeck> load({bool refresh = false}) {
    final stale = _fetchedAt == null || DateTime.now().difference(_fetchedAt!) > _ttl;
    if (_inflight != null && !refresh) return _inflight!;
    if (!stale && !refresh && deck != null) return Future.value(_recompute());
    return _inflight = _fetch().whenComplete(() => _inflight = null);
  }

  Future<BadgeDeck> _fetch() async {
    final now = DateTime.now();
    try {
      final results = await Future.wait([
        sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 400))), ymdOf(now)),
        sync.fetchProjects(),
        sync.fetchStrategicObjectives(),
      ]);
      _schedules = results[0] as List<DailySchedule>;
      _projects = results[1] as List<Project>;
      _objectives = results[2] as List<StrategicObjective>;
      _fetchedAt = now;
    } catch (_) {
      // Hors connexion : on calcule avec ce qu'on a (l'état local suffit aux séries).
    }
    return _recompute();
  }

  BadgeDeck _recompute() {
    final st = logic.state;
    final d = computeBadges(
      activities: st.activities,
      habitHits: st.habitHits,
      schedules: _schedules,
      projects: _projects,
      objectives: _objectives,
      sessions: st.sessions,
      moodMarks: st.moodMarks,
      now: DateTime.now(),
      dayStartMin: logic.dayStartMin,
    );
    deck = d;
    notifyListeners();
    return d;
  }

  /// Badges dont un palier acquis n'a pas encore été signalé. Marque ces
  /// paliers comme vus (ils ne reviendront pas) et renvoie les badges à montrer.
  Future<List<BadgeState>> takeSignals(BadgeDeck d) async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getStringList(_seenKey);
    final keys = acquiredTierKeys(d);
    if (stored == null) {
      await p.setStringList(_seenKey, keys.toList());
      return const [];
    }
    final seen = stored.toSet();
    final fresh = newTierKeys(d, seen);
    if (fresh.isEmpty) return const [];
    await p.setStringList(_seenKey, {...seen, ...keys}.toList());
    final ids = fresh.map((k) => k.split('#').first).toSet();
    return d.badges.where((b) => ids.contains(b.def.id)).toList();
  }
}
