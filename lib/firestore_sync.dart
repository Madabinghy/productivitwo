import 'package:productivitwo_v1/models.dart';

/// Stub Firebase sync — désactivé temporairement.
/// Les dépendances gRPC/BoringSSL de Firestore causent des erreurs
/// de compilation sur Xcode Cloud. On reviendra à la sync Firebase
/// via REST API dans une prochaine version.
class FirestoreSync {
  String? get uid => null;

  Future<String> signInAnonymously() async => '';
  Future<void> pushAll(AppState st) async {}
  Future<void> pushDeltas(AppState st) async {}
  Future<AppState?> pull() async => null;
}
