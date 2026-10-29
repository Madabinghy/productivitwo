import 'dart:async';

import 'package:flutter/material.dart';

/// Message avec « Annuler » qui se ferme TOUJOURS après [duration] : Flutter
/// garde ouvert un SnackBar à action quand la navigation accessible est active
/// (réglages d'accessibilité iOS), il resterait affiché indéfiniment.
void showUndoSnackBar(BuildContext context, String message, VoidCallback onUndo, {Duration duration = const Duration(seconds: 5)}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final ctrl = messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: duration,
    action: SnackBarAction(label: 'Annuler', onPressed: onUndo),
  ));
  var closed = false;
  ctrl.closed.then((_) => closed = true);
  Timer(duration, () {
    if (!closed) ctrl.close();
  });
}
