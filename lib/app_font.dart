import 'package:flutter/foundation.dart';

/// Police de l'app sur iPhone : Inter, embarquée (`assets/fonts/`).
///
/// Sous iOS 27, la police du système ne rend plus les graisses demandées
/// (w700 / w800 s'affichent en trait moyen). Une police embarquée ne dépend ni
/// d'iOS ni de Flutter. Ailleurs (Android, web, tests) : null = police d'origine.
String? get kAppFont => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? 'Inter' : null;
