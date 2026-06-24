import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/prototypes/defense_prototype.dart';

// Prototype « Défense néon » branché sur TES données (?proto=defense, après auth).
// Chaque domaine actif = une tourelle (couleur du domaine) ; sa « charge » (cadence
// de tir) = ta régularité récente sur ce domaine. Zéro stratégie : ça canarde tout
// seul, tu regardes le juice.
class DefenseDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const DefenseDataScreen({super.key, required this.sync});

  @override
  State<DefenseDataScreen> createState() => _DefenseDataScreenState();
}

class _DefenseDataScreenState extends State<DefenseDataScreen> {
  List<TurretSpec>? _turrets;
  String? _error;

  static const _fallback = Color(0xFF35E0FF);
  static const int _maxTurrets = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.sync.pull();
      if (state == null) throw Exception('Aucun état chargé');

      final now = DateTime.now();
      final actToDom = <String, String>{};
      for (final a in state.activities) {
        actToDom[a.id] = a.domainId;
      }

      // dernière activité par domaine (session OU routine)
      final lastByDom = <String, DateTime>{};
      void mark(String? dom, DateTime ts) {
        if (dom == null) return;
        final prev = lastByDom[dom];
        if (prev == null || ts.isAfter(prev)) lastByDom[dom] = ts;
      }

      for (final s in state.sessions) {
        mark(actToDom[s.activityId], s.startAt);
      }
      for (final hh in state.habitHits) {
        mark(actToDom[hh.habitId], hh.ts);
      }

      // domaines triés par activité récente (les plus actifs en tourelles)
      final domains = state.activeDomains.toList()
        ..sort((a, b) {
          final da = lastByDom[a.id];
          final db = lastByDom[b.id];
          final ta = da == null ? 0 : da.millisecondsSinceEpoch;
          final tb = db == null ? 0 : db.millisecondsSinceEpoch;
          return tb.compareTo(ta);
        });

      final turrets = <TurretSpec>[];
      for (final d in domains.take(_maxTurrets)) {
        final last = lastByDom[d.id];
        final days =
            last == null ? 99.0 : now.difference(last).inMinutes / 1440.0;
        final charge = days < 1
            ? 1.0
            : days < 3
                ? 0.65
                : days < 7
                    ? 0.4
                    : 0.2;
        turrets.add(TurretSpec(
          d.colorValue != null ? Color(d.colorValue!) : _fallback,
          charge,
          d.name,
        ));
      }

      if (mounted) setState(() => _turrets = turrets);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF06070F),
        body: Center(
            child: Text('Erreur : $_error',
                style: const TextStyle(color: Colors.white70))),
      );
    }
    final t = _turrets;
    if (t == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF06070F),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (t.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF06070F),
        body: Center(
          child: Text('Aucun domaine actif à déployer.',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF06070F),
      body: DefenseView(turrets: t),
    );
  }
}
