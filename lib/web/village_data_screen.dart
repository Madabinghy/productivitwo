import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/prototypes/village_prototype.dart';

// Prototype « Village » branché sur TES données (?proto=village, après auth).
// Chaque séance loggée → une maison (couleur du domaine) ; chaque routine
// cochée → un arbre. Ordre chronologique : ton village s'est bâti au fil du temps.
class VillageDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const VillageDataScreen({super.key, required this.sync});

  @override
  State<VillageDataScreen> createState() => _VillageDataScreenState();
}

class _VillageDataScreenState extends State<VillageDataScreen> {
  List<VillageElement>? _els;
  int _today = 0;
  int _capped = 0;
  String? _error;

  static const int _maxShown = 200;
  static const _fallback = Color(0xFF8AA0C8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.sync.pull();
      if (state == null) throw Exception('Aucun état chargé');

      // activityId → couleur du domaine
      final domColor = <String, Color>{};
      final colorByDom = <String, Color>{
        for (final d in state.activeDomains)
          d.id: d.colorValue != null ? Color(d.colorValue!) : _fallback,
      };
      for (final a in state.activities) {
        domColor[a.id] = colorByDom[a.domainId] ?? _fallback;
      }

      final now = DateTime.now();
      final today = yyyymmdd(now);

      // (timestamp, élément)
      final acts = <(DateTime, VillageElement)>[];
      for (final s in state.sessions) {
        acts.add((
          s.startAt,
          VillageElement(BuildKind.house, domColor[s.activityId] ?? _fallback)
        ));
      }
      for (final hh in state.habitHits) {
        acts.add((hh.ts, const VillageElement(BuildKind.tree, Color(0xFF5BA94E))));
      }
      acts.sort((a, b) => a.$1.compareTo(b.$1));

      final total = acts.length;
      final kept = total > _maxShown ? acts.sublist(total - _maxShown) : acts;
      final todayCount =
          acts.where((e) => yyyymmdd(e.$1) == today).length;

      if (mounted) {
        setState(() {
          _els = kept.map((e) => e.$2).toList();
          _today = todayCount;
          _capped = total > _maxShown ? total : 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Erreur : $_error')));
    }
    final els = _els;
    if (els == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: VillageView(elements: els, todayCount: _today, cappedFrom: _capped),
    );
  }
}
