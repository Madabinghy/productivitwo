// siri_service.dart — pont Flutter ⇆ raccourcis Siri (iOS uniquement)
//
// Les raccourcis Siri sont définis nativement (ios/Runner/SiriIntents.swift) et
// apparaissent automatiquement dans l'app Raccourcis. Ce service sert juste à
// rafraîchir leurs options (liste des routines) et à ouvrir l'app Raccourcis.

import 'dart:io';

import 'package:flutter/services.dart';

const _kIosWidgetChannel = MethodChannel('com.madabinghy.productivitwo/widget');

class SiriService {
  SiriService._();

  /// Demande à iOS de rafraîchir les options des raccourcis (ex : routines).
  /// À appeler quand les routines changent ou depuis le bouton « Ajouter à Siri ».
  static Future<void> refreshShortcuts() async {
    if (!Platform.isIOS) return;
    try {
      await _kIosWidgetChannel.invokeMethod('updateSiriShortcuts');
    } catch (_) {}
  }
}
