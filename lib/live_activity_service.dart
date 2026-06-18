import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// Pont vers la Live Activity iOS (ActivityKit). No‑op hors iOS.
///
/// Phase 1 : démarrer / terminer une Live Activity « minuteur » en local (quand
/// l'app tourne ou est observée via le stream des sessions).
/// Phase 2 : `pushToStartToken` (push‑to‑start, app fermée) — posé dans Firestore
/// et consommé côté Cloud Function (APNs direct).
///
/// Côté natif : `MethodChannel('productivitwo/live_activity')` géré dans
/// `ios/Runner/LiveActivityManager.swift` (enregistré par AppDelegate).
class LiveActivityService {
  LiveActivityService._() {
    if (_supported) _ch.setMethodCallHandler(_handleNative);
  }
  static final LiveActivityService instance = LiveActivityService._();

  static const MethodChannel _ch = MethodChannel('productivitwo/live_activity');

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// id de la Live Activity en cours (pour la terminer), null = aucune.
  String? _activityId;

  bool get isRunning => _activityId != null;

  /// Appelé quand un token APNs arrive (push‑to‑start ou token d'activité). Posé
  /// par `main.dart` pour persister dans Firestore. `type` ∈ {pushToStart, activity}.
  void Function(String type, String token, {String? activityId})? onToken;

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'onPushToStartToken':
        onToken?.call('pushToStart', call.arguments as String);
        break;
      case 'onActivityToken':
        final m = (call.arguments as Map).cast<String, dynamic>();
        onToken?.call('activity', m['token'] as String,
            activityId: m['id'] as String?);
        break;
    }
    return null;
  }

  /// (Phase 2) Démarre l'observation des tokens push‑to‑start ActivityKit (iOS
  /// 17.2+) : à chaque token, `onToken` est rappelé → à stocker dans Firestore.
  Future<void> registerForRemoteStart() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('registerPushToStart');
    } catch (_) {}
  }

  /// Démarre (ou met à jour) la Live Activity « minuteur » : compte AU‑DESSUS
  /// depuis `startAt` (session ouverte, sans durée fixe).
  Future<void> start({
    required String activityName,
    required DateTime startAt,
    int colorArgb = 0xFF4F8DF7,
  }) async {
    if (!_supported) return;
    try {
      final id = await _ch.invokeMethod<String>('start', {
        'name': activityName,
        'startAtMs': startAt.millisecondsSinceEpoch,
        'colorArgb': colorArgb,
      });
      if (id != null && id.isNotEmpty) _activityId = id;
    } catch (_) {
      // ActivityKit indisponible (iOS < 16.1 / désactivé) → on ignore.
    }
  }

  /// Termine la Live Activity en cours (s'il y en a une).
  Future<void> end() async {
    if (!_supported) return;
    final id = _activityId;
    _activityId = null;
    try {
      await _ch.invokeMethod('end', {'id': id});
    } catch (_) {}
  }

  /// (Phase 2) Token push‑to‑start ActivityKit (iOS 17.2+) à stocker dans
  /// Firestore pour permettre le démarrage distant app fermée. null si indispo.
  Future<String?> pushToStartToken() async {
    if (!_supported) return null;
    try {
      return await _ch.invokeMethod<String>('pushToStartToken');
    } catch (_) {
      return null;
    }
  }
}
