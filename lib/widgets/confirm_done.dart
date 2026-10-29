import 'package:flutter/material.dart';

/// Confirmation avant de marquer une action ou une tâche comme faite (retour
/// user 2026-10-30 : une coche par erreur, sans savoir laquelle). Les gestes
/// délibérés qui proposent déjà « Annuler » (glisser vers la droite) s'en
/// passent ; une coche d'un simple tap la demande.
Future<bool> confirmDone(BuildContext context, {required String title, bool task = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(task ? 'Tâche faite ?' : 'Action faite ?'),
      content: Text('« $title »', maxLines: 4, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui, c'est fait")),
      ],
    ),
  );
  return ok == true;
}
