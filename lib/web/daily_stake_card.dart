import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/daily_stake_card.dart';

/// Carte « Mise du jour » pour le web : `_FocusView` n'a pas d'AppLogic, donc on
/// le construit ici (modèle `chrono_launcher.dart`) puis on délègue à
/// [DailyStakeCardBody] (partagé avec le mobile).
class DailyStakeCard extends StatefulWidget {
  final FirestoreSync sync;
  const DailyStakeCard({required this.sync, super.key});

  @override
  State<DailyStakeCard> createState() => _DailyStakeCardState();
}

class _DailyStakeCardState extends State<DailyStakeCard> {
  AppLogic? _logic;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await widget.sync.pull();
    if (state == null || !mounted) return;
    final logic = AppLogic(state, () {
      if (mounted) setState(() {});
    });
    logic.sync = widget.sync;
    logic.reconcileLiveGold(widget.sync); // solde à jour des gains du jour
    setState(() => _logic = logic);
  }

  @override
  Widget build(BuildContext context) {
    final l = _logic;
    if (l == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return DailyStakeCardBody(
      logic: l,
      sync: widget.sync,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }
}
