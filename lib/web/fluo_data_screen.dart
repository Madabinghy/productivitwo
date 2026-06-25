import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/prototypes/orbit_prototype.dart';
import 'package:productivitwo_v1/prototypes/fluo_prototype.dart';

// « Fluo Adventure » branché sur TES données (?proto=fluo, après auth).
//   • Niveau 0 = la VRAIE galaxie orbit : planètes (= domaines) autour
//     d'« Aujourd'hui ». Taille = temps 30 j (réf. p90), distance = récence.
//   • Cliquer une planète → la map du domaine (pièces = vraies activités).
//   • Terminal d'une activité → carte à nœuds (avancer coûte de l'énergie
//     gagnée par tes vraies séances). Navigation par bouton Retour (sans fusée).
class FluoDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const FluoDataScreen({super.key, required this.sync});

  @override
  State<FluoDataScreen> createState() => _FluoDataScreenState();
}

class _FluoDataScreenState extends State<FluoDataScreen> {
  List<FluoDomain>? _doms;
  List<OrbitBody>? _bodies;
  double _sunFill = 0;
  String _sunLabel = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.sync.pull();
      if (state == null) throw Exception('Aucun état chargé');
      final built = buildFluoData(state);
      if (mounted) {
        setState(() {
          _doms = built.doms;
          _bodies = built.bodies;
          _sunFill = built.sunFill;
          _sunLabel = built.sunLabel;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0820),
        body: Center(
          child: Text('Erreur : $_error',
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final doms = _doms;
    if (doms == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0820),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (doms.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0820),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Aucun domaine actif.\n'
              'Crée des domaines et des activités pour explorer ta galaxie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }
    return FluoNavScreen(
      data: doms,
      bodies: _bodies,
      sunFill: _sunFill,
      sunLabel: _sunLabel,
    );
  }
}

const _coldRef = Color(0xFF6A749A);
const _fallbackPalette = [
  Color(0xFF5BD0A0),
  Color(0xFF35E0FF),
  Color(0xFFFF5A8A),
  Color(0xFFA86BFF),
  Color(0xFFFFD36B),
  Color(0xFFFFB37E),
];

// Construit la galaxie (planètes/domaines), les pièces (activités+énergie) et le
// soleil depuis un AppState. Réutilisé par le web (FluoDataScreen) ET le mobile.
({
  List<FluoDomain> doms,
  List<OrbitBody> bodies,
  double sunFill,
  String sunLabel,
}) buildFluoData(AppState state) {
  final now = DateTime.now();
  final domains = state.activeDomains;
  if (domains.isEmpty) {
    return (doms: [], bodies: [], sunFill: 0, sunLabel: '');
  }

  // énergie par activité = nb de séances/coches réelles sur 30 j
  final energyByAct = <String, int>{};
  for (final s in state.sessions) {
    if (now.difference(s.startAt).inDays < 30) {
      energyByAct[s.activityId] = (energyByAct[s.activityId] ?? 0) + 1;
    }
  }
  for (final h in state.habitHits) {
    if (now.difference(h.ts).inDays < 30) {
      energyByAct[h.habitId] = (energyByAct[h.habitId] ?? 0) + 1;
    }
  }

  // activités par domaine (nom + énergie) + table activité→domaine
  final actsByDom = <String, List<FluoActivity>>{};
  final actToDom = <String, String>{};
  for (final a in state.activeActivities) {
    actToDom[a.id] = a.domainId;
    (actsByDom[a.domainId] ??= [])
        .add(FluoActivity(a.name, energy: energyByAct[a.id] ?? 0));
  }

  // agrégats par domaine
  final lastByDom = <String, DateTime>{};
  final min30ByDom = <String, int>{};
  final daysByDom = <String, Set<String>>{};
  for (final s in state.sessions) {
    final dom = actToDom[s.activityId];
    if (dom == null) continue;
    final prev = lastByDom[dom];
    if (prev == null || s.startAt.isAfter(prev)) lastByDom[dom] = s.startAt;
    if (now.difference(s.startAt).inDays < 30) {
      min30ByDom[dom] =
          (min30ByDom[dom] ?? 0) + s.duration.inMinutes.clamp(0, 24 * 60);
    }
    (daysByDom[dom] ??= {}).add(yyyymmdd(s.startAt));
  }

  // référence "pleine taille" = p90 (système des heatmaps de l'accueil)
  final timeRef =
      percentileOf(min30ByDom.values.toList(), 0.90).clamp(1.0, double.infinity);

  String? ringedDom;
  int best = -1;
  min30ByDom.forEach((d, m) {
    if (m > best) {
      best = m;
      ringedDom = d;
    }
  });

  final doms = <FluoDomain>[];
  final bodies = <OrbitBody>[];
  for (var i = 0; i < domains.length; i++) {
    final d = domains[i];
    final min30 = min30ByDom[d.id] ?? 0;
    final mass = (min30 / timeRef).clamp(0.0, 1.0).toDouble();
    final color = d.colorValue != null
        ? Color(d.colorValue!)
        : _fallbackPalette[i % _fallbackPalette.length];

    doms.add(FluoDomain(
      name: d.name,
      color: color,
      activities: actsByDom[d.id] ?? const [],
      mass: mass,
    ));

    final last = lastByDom[d.id];
    final days = last == null
        ? OrbitBody.maxDays
        : (now.difference(last).inMinutes / 1440).clamp(0.0, OrbitBody.maxDays);
    bodies.add(OrbitBody(
      name: d.name,
      hot: color,
      cold: Color.lerp(color, _coldRef, 0.72)!,
      mass: mass,
      angle: i * (2 * math.pi / domains.length) + 0.4,
      days: days.toDouble(),
      streak: _streak(daysByDom[d.id] ?? const {}, now),
      totalLabel: _fmtTotal(min30),
      ringed: min30 > 0 && d.id == ringedDom,
    ));
  }

  final sun = _computeSun(state, now);
  return (doms: doms, bodies: bodies, sunFill: sun.$1, sunLabel: sun.$2);
}

int _streak(Set<String> days, DateTime now) {
  if (days.isEmpty) return 0;
  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(yyyymmdd(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(yyyymmdd(cursor))) return 0;
  }
  var count = 0;
  while (days.contains(yyyymmdd(cursor))) {
    count++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return count;
}

String? _fmtTotal(int min) {
  if (min <= 0) return null;
  final h = min ~/ 60;
  final m = min % 60;
  final t =
      h > 0 ? '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}' : '${m}min';
  return '$t / 30 j';
}

// Soleil « Aujourd'hui » : minutes sur 24h glissantes / record journalier.
(double, String) _computeSun(AppState state, DateTime now) {
  var min24 = 0;
  final perDay = <String, int>{};
  for (final s in state.sessions) {
    final m = s.duration.inMinutes.clamp(0, 24 * 60);
    if (now.difference(s.startAt).inMinutes < 1440 && !s.startAt.isAfter(now)) {
      min24 += m;
    }
    perDay[yyyymmdd(s.startAt)] = (perDay[yyyymmdd(s.startAt)] ?? 0) + m;
  }
  final maxDay = perDay.values.isEmpty
      ? 60
      : math.max(60, perDay.values.reduce(math.max));
  final fill = (min24 / maxDay).clamp(0.0, 1.0);
  final label = min24 <= 0 ? 'rien encore' : '${_fmtMin(min24)} / 24h';
  return (fill, label);
}

String _fmtMin(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  if (h > 0) return '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}';
  return '${m}min';
}
