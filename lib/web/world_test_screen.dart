import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/web/unified_world_sheet.dart';

/// Page de DÉV : ouvre directement le sheet du Monde (cinématique/combat) au
/// chargement. Accès via `?worldtest=true` → on recharge la page pour re-tester.
class WorldTestScreen extends StatefulWidget {
  final FirestoreSync sync;
  const WorldTestScreen({required this.sync, super.key});
  @override
  State<WorldTestScreen> createState() => _WorldTestScreenState();
}

class _WorldTestScreenState extends State<WorldTestScreen> {
  AppLogic? _logic;
  String? _error;
  bool _opening = false;
  FirestoreSync get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await sync.pull();
      if (state == null) {
        if (mounted) setState(() => _error = 'Impossible de charger les données.');
        return;
      }
      final logic = AppLogic(state, () {
        if (mounted) setState(() {});
      });
      logic.sync = sync;
      final projects = await sync.fetchProjects();
      logic.updateGanttCounts(projects);
      if (!mounted) return;
      setState(() => _logic = logic);
      _open();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open() async {
    if (_opening || _logic == null) return;
    _opening = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showUnifiedWorldSheet(context, _logic!, sync);
    _opening = false;
    if (mounted) setState(() {}); // ré-affiche le bouton si on a fermé le sheet
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1512),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              )
            : _logic == null
                ? const CircularProgressIndicator()
                : FilledButton.icon(
                    onPressed: _open,
                    icon: const Text('🌍', style: TextStyle(fontSize: 16)),
                    label: const Text('Ouvrir le Monde'),
                  ),
      ),
    );
  }
}
