import 'package:flutter/material.dart';

// Stub mobile/desktop : doit exposer les mêmes symboles que web_app.dart utilisés
// par main.dart (import conditionnel), sinon le build non-web ne compile pas.
const String kWebBuildTag = 'mobile';

class WebApp extends StatelessWidget {
  const WebApp({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
