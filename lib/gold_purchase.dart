import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

/// Achat-à-l'usage : propose d'acheter un consommable au moment où il sert
/// (suppression → joker, routine → gel, deadline → sursis).
///
/// `purchaseGold` vérifie le solde côté serveur (transaction) → renvoie `false`
/// si insuffisant. Si [logic] est fourni, on met à jour l'état local de façon
/// optimiste (sinon le prochain pull reconverge).
Future<bool> offerBuyConsumable(
  BuildContext context,
  FirestoreSync sync, {
  required String itemKey,
  required int price,
  required String label,
  String? rationale,
  AppLogic? logic,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Acheter « $label » ?'),
      content: Text(
        '${rationale ?? 'Tu n\'as pas cet item en stock.'}\n\nCoût : $price or.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kGoldColor),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const GoldIcon(size: 16, color: Colors.white),
          label: Text('Acheter ($price)'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final done = await sync.purchaseGold(
      price: price, label: 'Achat : $label', incInventory: itemKey);
  if (done && logic != null) {
    logic.state.gold -= price;
    logic.state.goldInventory[itemKey] =
        (logic.state.goldInventory[itemKey] ?? 0) + 1;
    logic.onChange();
  }
  if (!done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Solde insuffisant pour « $label » ($price or).'),
    ));
  }
  return done;
}
