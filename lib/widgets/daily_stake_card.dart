import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/gold_economy.dart';

const _kGold = Color(0xFFC9A84C);

/// Corps de la carte « Mise du jour » (commitment device honnête).
/// Partagé web/mobile : on lui passe un [AppLogic] + [FirestoreSync] déjà prêts.
/// Règle les mises passées non réglées à l'ouverture, puis affiche l'état du jour.
class DailyStakeCardBody extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final VoidCallback? onChanged;
  const DailyStakeCardBody(
      {required this.logic, required this.sync, this.onChanged, super.key});

  @override
  State<DailyStakeCardBody> createState() => _DailyStakeCardBodyState();
}

class _DailyStakeCardBodyState extends State<DailyStakeCardBody> {
  AppLogic get logic => widget.logic;
  bool _busy = false;
  int _amount = 10;
  String? _settledMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
  }

  Future<void> _settle() async {
    final res = await logic.settleDueStakes(widget.sync);
    if (!mounted || res.isEmpty) return;
    final last = res.last;
    setState(() => _settledMsg =
        'Mise du ${_fmtYmd(last.ymd)} : ${(last.ratio * 100).round()} % → +${last.payout} or');
    widget.onChanged?.call();
  }

  Future<void> _place() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await logic.placeStakeToday(widget.sync, _amount);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged?.call();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mise impossible (solde insuffisant ou déjà misée).')));
    }
  }

  static String _fmtYmd(String ymd) => ymd.length == 8
      ? '${ymd.substring(6, 8)}/${ymd.substring(4, 6)}'
      : ymd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final placed = logic.stakePlacedToday();
    final tally = logic.dailyRoutineTally(today);
    final gold = logic.gold;

    final children = <Widget>[];

    // Bandeau de règlement d'hier (one-shot).
    if (_settledMsg != null) {
      children.add(_banner(cs, _settledMsg!));
      children.add(const SizedBox(height: 10));
    }

    if (placed) {
      // Mise en jeu : montant + progression du jour.
      final amt = logic.stakeAmountToday();
      final ratioPct =
          tally.due == 0 ? 0 : ((tally.met / tally.due) * 100).round();
      children.add(Row(children: [
        const Text('🎲', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('En jeu : $amt or',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: _kGold)),
        ),
        Text('${tally.met}/${tally.due} routines',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.6))),
      ]));
      children.add(const SizedBox(height: 8));
      children.add(ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: tally.due == 0 ? 0 : (tally.met / tally.due),
          minHeight: 7,
          backgroundColor: cs.surfaceContainerHighest.withOpacity(.4),
          color: ratioPct >= 100 ? Colors.green.shade500 : _kGold,
        ),
      ));
      children.add(const SizedBox(height: 8));
      children.add(Text(
        ratioPct >= 100
            ? 'Journée tenue ! Tu récupères ta mise + ${(GoldEconomy.stakeBonusRate * 100).round()} % au prochain passage.'
            : 'Termine tes routines : tu récupères ta mise au prorata, + ${(GoldEconomy.stakeBonusRate * 100).round()} % à 100 %.',
        style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.55)),
      ));
    } else if (tally.due == 0) {
      children.add(Text(
        'Aucune routine quotidienne à miser aujourd\'hui.',
        style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: cs.onSurface.withOpacity(.45)),
      ));
    } else {
      // Choix du montant + bouton miser.
      final cap = gold < GoldEconomy.stakeMaxPerDay
          ? gold
          : GoldEconomy.stakeMaxPerDay;
      final presets = [5, 10, 20, 50].where((p) => p <= cap).toList();
      if (presets.isEmpty && cap >= 1) presets.add(cap);
      if (_amount > cap) _amount = cap < 1 ? 1 : cap;
      children.add(Text(
        'Mise sur ta journée : récupère ta mise au prorata des routines tenues, '
        '+ ${(GoldEconomy.stakeBonusRate * 100).round()} % si tu fais 100 %.',
        style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.6)),
      ));
      children.add(const SizedBox(height: 10));
      if (cap < 1) {
        children.add(Text('Pas assez d\'or pour miser.',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(.45))));
      } else {
        children.add(Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in presets)
              ChoiceChip(
                label: Text('$p'),
                selected: _amount == p,
                onSelected: _busy ? null : (_) => setState(() => _amount = p),
                selectedColor: _kGold.withOpacity(.25),
              ),
          ],
        ));
        children.add(const SizedBox(height: 10));
        children.add(Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: (_busy || _amount > gold || _amount < 1) ? null : _place,
            icon: const Icon(Icons.casino_outlined, size: 16),
            label: Text(
                'Miser $_amount or  ·  100 % → +${GoldEconomy.stakePayout(_amount, 1.0)}'),
            style: FilledButton.styleFrom(
                backgroundColor: _kGold, foregroundColor: Colors.black),
          ),
        ));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _banner(ColorScheme cs, String msg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _kGold.withOpacity(.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kGold.withOpacity(.4)),
        ),
        child: Row(children: [
          const Text('💰', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _kGold)),
          ),
        ]),
      );
}
