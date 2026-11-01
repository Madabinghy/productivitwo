import 'dart:async';

import 'package:flutter/material.dart';

/// Flutter garde ouvert un SnackBar à action quand la navigation accessible est
/// active (réglages d'accessibilité iOS) : il resterait affiché indéfiniment.
/// Ces helpers le ferment TOUJOURS après sa durée.
extension ClosingSnackBar on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showClosingSnackBar(SnackBar snackBar) {
    final ctrl = showSnackBar(snackBar);
    var closed = false;
    ctrl.closed.then((_) => closed = true);
    // La durée court à partir de l'apparition (+ l'animation d'entrée).
    Timer(snackBar.duration + const Duration(milliseconds: 300), () {
      if (!closed) ctrl.close();
    });
    return ctrl;
  }
}

/// Message avec « Annuler » qui se ferme toujours après [duration].
void showUndoSnackBar(BuildContext context, String message, VoidCallback onUndo, {Duration duration = const Duration(seconds: 5)}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showClosingSnackBar(SnackBar(persist: false, 
    content: Text(message),
    duration: duration,
    action: SnackBarAction(label: 'Annuler', onPressed: onUndo),
  ));
}
