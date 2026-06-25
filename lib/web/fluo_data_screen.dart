import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/prototypes/fluo_prototype.dart';

// « Fluo Adventure » branché sur TES données (?proto=fluo, après auth).
//   • Cosmos : chaque domaine actif = une planète (taille = temps 30 j,
//     référence p90 comme les heatmaps de l'accueil).
//   • Map du domaine : les pièces sont les vraies activités du domaine.
//   • Carte à nœuds : par activité (procédurale pour l'instant).
class FluoDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const FluoDataScreen({super.key, required this.sync});

  @override
  State<FluoDataScreen> createState() => _FluoDataScreenState();
}

class _FluoDataScreenState extends State<FluoDataScreen> {
  List<FluoDomain>? _doms;
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
      final doms = _buildDomains(state);
      if (mounted) setState(() => _doms = doms);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF05070F),
        body: Center(
          child: Text('Erreur : $_error',
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final doms = _doms;
    if (doms == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF05070F),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (doms.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF05070F),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Aucun domaine actif.\n'
              'Crée des domaines et des activités pour explorer ton cosmos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }
    return FluoNavScreen(data: doms);
  }
}

const _fallbackPalette = [
  Color(0xFF5BD0A0),
  Color(0xFF35E0FF),
  Color(0xFFFF5A8A),
  Color(0xFFA86BFF),
  Color(0xFFFFD36B),
  Color(0xFFFFB37E),
];

List<FluoDomain> _buildDomains(AppState state) {
  final now = DateTime.now();
  final domains = state.activeDomains;
  if (domains.isEmpty) return [];

  // activités (noms) par domaine + table activité→domaine
  final actsByDom = <String, List<String>>{};
  final actToDom = <String, String>{};
  for (final a in state.activeActivities) {
    actToDom[a.id] = a.domainId;
    (actsByDom[a.domainId] ??= []).add(a.name);
  }

  // minutes des 30 derniers jours par domaine
  final min30ByDom = <String, int>{};
  for (final s in state.sessions) {
    final dom = actToDom[s.activityId];
    if (dom == null) continue;
    if (now.difference(s.startAt).inDays < 30) {
      min30ByDom[dom] =
          (min30ByDom[dom] ?? 0) + s.duration.inMinutes.clamp(0, 24 * 60);
    }
  }

  // référence "pleine taille" = p90 (même système que les heatmaps de l'accueil)
  final timeRef = percentileOf(min30ByDom.values.toList(), 0.90)
      .clamp(1.0, double.infinity);

  final out = <FluoDomain>[];
  for (var i = 0; i < domains.length; i++) {
    final d = domains[i];
    final color = d.colorValue != null
        ? Color(d.colorValue!)
        : _fallbackPalette[i % _fallbackPalette.length];
    final mass = ((min30ByDom[d.id] ?? 0) / timeRef).clamp(0.0, 1.0);
    out.add(FluoDomain(
      name: d.name,
      color: color,
      activities: actsByDom[d.id] ?? const [],
      mass: mass.toDouble(),
    ));
  }
  return out;
}
