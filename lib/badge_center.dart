import 'package:flutter/foundation.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/chain_session_store.dart';
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/today_facts.dart';
import 'package:productivitwo_v1/utils/embers.dart' show EmberEventKind;
import 'dart:convert' show jsonEncode;

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
  /// Programmes des 400 derniers jours (après `load()`), partagés avec la
  /// feuille du mode (fenêtres d'élan gagnées sur 60 jours).
  List<DailySchedule> get schedules => _schedules;
  List<Project> _projects = const [];
  List<StrategicObjective> _objectives = const [];
  DateTime? _fetchedAt;
  Future<BadgeDeck>? _inflight;
  String? _snapshotHash; // dernier instantané envoyé au serveur (évite les écritures identiques)

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
      chainRuns: st.chainRuns,
      now: DateTime.now(),
      dayStartMin: logic.dayStartMin,
      emberSpends: logic.emberSpends,
      restPeriods: logic.restPeriods,
      restDomains: logic.restDomains,
      seasons: logic.seasons,
      acquired: logic.acquired,
      budgetWindowDays: logic.budgetWindowDays,
    );
    deck = d;
    logic.embers = d.embers;
    // Chasses attrapées : le palier visé est atteint → sortent de la chasse,
    // et le signal d'Aujourd'hui dira « Badge visé obtenu ».
    final caught = caughtHunts(logic.badgeHunts, d);
    if (caught.isNotEmpty) {
      logic.caughtHuntBadgeIds.addAll(caught.map((v) => v.badge.def.id));
      logic.stopHunts(caught.map((v) => v.badge.def.id));
    }
    _pushSnapshot(d);
    notifyListeners();
    return d;
  }

  /// Les faits du jour vécu pour « ce qu'il manque aujourd'hui »
  /// (`badge_today.dart`) : routines quotidiennes dues et leur compte, blocs
  /// du programme du jour, pointages d'élan, session Enchaîner en attente,
  /// temps des objectifs. Synchrone : tout vient de l'état local et du dernier
  /// `load()`.
  TodayFacts todayFacts() {
    final st = logic.state;
    final now = DateTime.now();
    final ymd = logic.livedTodayYmd;
    final pending = ChainSessionStore.current;
    return composeTodayFacts(
      ymd: ymd,
      now: now,
      dayStartMin: logic.dayStartMin,
      activities: st.activities,
      hits: st.habitHits,
      sessions: st.sessions,
      moodMarks: st.moodMarks,
      objectives: _objectives,
      projects: _projects,
      schedule: _schedules.where((s) => s.date == ymd).firstOrNull,
      pendingChain: pending != null && pending.isLive(now, ymd) ? pending : null,
      acquired: logic.acquired,
      budgetWindowDays: logic.budgetWindowDays,
      restingDomainIds: {for (final d in st.activeDomains) if (logic.isDomainResting(d.id)) d.id},
    );
  }

  /// Dépose l'instantané du deck dans `data/badges` quand il change (le MCP
  /// `list_badges` / `hunt_badge` et le contexte de Claude le lisent).
  void _pushSnapshot(BadgeDeck d) {
    final badges = [
      for (final b in d.badges)
        {
          'id': b.def.id,
          'family': b.def.family.name,
          'name': b.def.name,
          'level': b.level,
          'tiers': b.def.tiers,
          'value': b.value,
          'unit': b.def.unit,
          'nextTarget': b.nextTarget,
          'obtained': b.obtained == null ? null : ymdOf(b.obtained!),
          'measured': b.def.measured,
          if (b.def.family == BadgeFamily.routines)
            'domainId': logic.state.activities.where((a) => a.id == b.def.subjectId).firstOrNull?.domainId,
        },
    ];
    final since = ymdOf(DateTime.now().subtract(const Duration(days: 30)));
    final acts = {for (final a in logic.state.activities) a.id: a};
    final body = {
      'acquired': d.acquired,
      'total': d.total,
      'badges': badges,
      // Braises : réserve et séries rallumées sur 30 jours (vue coach, filtrées par domaine partagé côté serveur).
      'embers': {
        'stock': d.embers.stock,
        'rekindled': [
          for (final e in d.embers.history)
            if (e.kind == EmberEventKind.spent && e.ymd.compareTo(since) >= 0)
              {'name': acts[e.activityId]?.name ?? 'Routine', 'ymd': e.ymd, 'domainId': acts[e.activityId]?.domainId},
        ],
      },
    };
    final hash = jsonEncode(body);
    if (hash == _snapshotHash) return;
    _snapshotHash = hash;
    sync.saveBadgeSnapshot({...body, 'updatedAt': DateTime.now().toIso8601String()});
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
    // Un palier qui n'est plus acquis (règle resserrée, donnée corrigée) sort de
    // la mémoire : s'il revient pour de vrai, il sera signalé à nouveau.
    final seen = stored.toSet().intersection(keys);
    if (seen.length != stored.length) await p.setStringList(_seenKey, seen.toList());
    final fresh = newTierKeys(d, seen);
    if (fresh.isEmpty) return const [];
    await p.setStringList(_seenKey, {...seen, ...keys}.toList());
    final ids = fresh.map((k) => k.split('#').first).toSet();
    return d.badges.where((b) => ids.contains(b.def.id)).toList();
  }
}
