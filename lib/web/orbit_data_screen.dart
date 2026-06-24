import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/prototypes/orbit_prototype.dart';

// Prototype « Système orbital » branché sur TES données (?proto=orbit, après auth).
// Chaque domaine actif devient une planète :
//   • récence de sa dernière session   → rayon d'orbite (proche = récent)
//   • minutes des 30 derniers jours    → taille (AU PRORATA du domaine le + investi)
//   • jours consécutifs avec session   → chaleur / série
//   • couleur du domaine               → teinte chaude
// Le soleil « Aujourd'hui » grossit selon le temps loggé sur 24h glissantes,
// normalisé sur ton record journalier.
class OrbitDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const OrbitDataScreen({super.key, required this.sync});

  @override
  State<OrbitDataScreen> createState() => _OrbitDataScreenState();
}

class _OrbitDataScreenState extends State<OrbitDataScreen> {
  List<OrbitBody>? _bodies;
  String? _error;
  int _domainCount = 0;
  double _sunFill = 0;
  String _sunLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.sync.pull();
      if (state == null) throw Exception('Aucun état chargé');
      final bodies = _buildBodies(state);
      final sun = _computeSun(state);
      if (mounted) {
        setState(() {
          _bodies = bodies;
          _domainCount = bodies.length;
          _sunFill = sun.$1;
          _sunLabel = sun.$2;
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
    final bodies = _bodies;
    if (bodies == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0820),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (bodies.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0820),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Aucun domaine actif à afficher.\n'
              'Crée des domaines et logue du temps pour peupler ta galaxie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0820),
      body: Stack(
        children: [
          Positioned.fill(
            child: OrbitView(
              bodies: bodies,
              interactive: false,
              onTapBody: _showInfo,
              sunFill: _sunFill,
              sunLabel: _sunLabel,
            ),
          ),
          Positioned(
            left: 24,
            top: 56,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ta galaxie',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text('$_domainCount domaines en orbite · touche une planète',
                    style: const TextStyle(
                        fontSize: 15, color: Color(0xFFA99FD6))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo(OrbitBody b) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1C1640),
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${b.name} — ${b.subtitle}'
            '${b.totalLabel != null ? ' · ${b.totalLabel}' : ''}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
  }
}

// ── Adapter AppState → planètes ─────────────────────────────────────────────
const _coldRef = Color(0xFF6A749A);
const _fallbackPalette = [
  Color(0xFFFFD36B),
  Color(0xFF9CC6F0),
  Color(0xFFE0A6FF),
  Color(0xFFFF9EC4),
  Color(0xFF7DFFCE),
  Color(0xFFFFB37E),
];

List<OrbitBody> _buildBodies(AppState state) {
  final now = DateTime.now();
  final domains = state.activeDomains;
  if (domains.isEmpty) return [];

  // activityId → domainId (activités actives)
  final actToDom = <String, String>{};
  for (final a in state.activeActivities) {
    actToDom[a.id] = a.domainId;
  }

  // agrège les sessions par domaine
  final lastByDom = <String, DateTime>{};
  final minutes30ByDom = <String, int>{};
  final daysWithSessionByDom = <String, Set<String>>{};

  for (final s in state.sessions) {
    final dom = actToDom[s.activityId];
    if (dom == null) continue;
    final start = s.startAt;
    final prev = lastByDom[dom];
    if (prev == null || start.isAfter(prev)) lastByDom[dom] = start;
    if (now.difference(start).inDays < 30) {
      minutes30ByDom[dom] =
          (minutes30ByDom[dom] ?? 0) + s.duration.inMinutes.clamp(0, 24 * 60);
    }
    (daysWithSessionByDom[dom] ??= {}).add(yyyymmdd(start));
  }

  final maxMin = minutes30ByDom.values.isEmpty
      ? 1
      : minutes30ByDom.values.reduce(math.max);

  // domaine le + investi → anneau de Saturne
  String? ringedDom;
  int best = -1;
  minutes30ByDom.forEach((d, m) {
    if (m > best) {
      best = m;
      ringedDom = d;
    }
  });

  final bodies = <OrbitBody>[];
  for (var i = 0; i < domains.length; i++) {
    final d = domains[i];
    final last = lastByDom[d.id];
    final days = last == null
        ? OrbitBody.maxDays
        : (now.difference(last).inMinutes / 1440).clamp(0.0, OrbitBody.maxDays);
    final min30 = minutes30ByDom[d.id] ?? 0;
    // taille STRICTEMENT au prorata du domaine le + investi (linéaire) :
    // on voit d'un coup d'œil sur quoi on passe le plus de temps ; petit = petit.
    final mass = maxMin <= 0 ? 0.0 : (min30 / maxMin).clamp(0.0, 1.0);
    final streak = _streak(daysWithSessionByDom[d.id] ?? const {}, now);

    final hot = d.colorValue != null
        ? Color(d.colorValue!)
        : _fallbackPalette[i % _fallbackPalette.length];
    final cold = Color.lerp(hot, _coldRef, 0.72)!;

    bodies.add(OrbitBody(
      name: d.name,
      hot: hot,
      cold: cold,
      mass: mass.toDouble(),
      angle: i * (2 * math.pi / domains.length) + 0.4,
      days: days.toDouble(),
      streak: streak,
      totalLabel: _fmtTotal(min30),
      ringed: min30 > 0 && d.id == ringedDom,
    ));
  }
  return bodies;
}

// Soleil « Aujourd'hui » : minutes loggées sur 24h glissantes, normalisées sur
// le record journalier (« sur un max »). Retourne (remplissage 0..1, libellé).
(double, String) _computeSun(AppState state) {
  final now = DateTime.now();
  var min24 = 0;
  final perDay = <String, int>{};
  for (final s in state.sessions) {
    final m = s.duration.inMinutes.clamp(0, 24 * 60);
    if (now.difference(s.startAt).inMinutes < 1440 &&
        !s.startAt.isAfter(now)) {
      min24 += m;
    }
    perDay[yyyymmdd(s.startAt)] = (perDay[yyyymmdd(s.startAt)] ?? 0) + m;
  }
  // max = ton meilleur jour (au moins 60 min pour éviter un soleil plein trop vite)
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

// jours consécutifs avec session, en partant d'aujourd'hui (ou hier si vide)
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
  final t = h > 0 ? '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}' : '${m}min';
  return '$t / 30 j';
}
