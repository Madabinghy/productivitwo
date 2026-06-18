import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:productivitwo_v1/web/web_auth_screen.dart';
import 'package:productivitwo_v1/web/web_home_screen.dart';
import 'package:productivitwo_v1/web/mobile_preview_screen.dart';
import 'package:productivitwo_v1/web/world_test_screen.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/web/web_email_signin_screen.dart';
import 'package:productivitwo_v1/web/web_magic_link_complete_screen.dart';
import 'package:productivitwo_v1/web/flame_proto_screen.dart';
import 'package:productivitwo_v1/web/flame_proto2_screen.dart';
import 'package:productivitwo_v1/web/flame_data_proto_screen.dart';
import 'package:productivitwo_v1/web/dev_auth_screen.dart';

// ── Couleurs Productivitwo ────────────────────────────────────────────────────

const _kPrimary   = Color(0xFF1D9E75);
const _kDark      = Color(0xFF155F47);
const _kSeedLight = _kPrimary;
const _kSeedDark  = Color(0xFF27C48F);

// ── WebApp ────────────────────────────────────────────────────────────────────

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Productivitwo — Projects',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kSeedLight,
          brightness: Brightness.light,
        ).copyWith(
          primary: _kPrimary,
          secondary: _kDark,
          surface: const Color(0xFFD6EEE6),
          surfaceContainerLowest: const Color(0xFFC8E8DC),
          surfaceContainerHighest: const Color(0xFFB0DDCB),
        ),
        scaffoldBackgroundColor: const Color(0xFFC8E8DC),
        useMaterial3: true,
      ),

      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kSeedDark,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _kSeedDark,
          secondary: _kPrimary,
          surface: const Color(0xFF0C1C14),
          surfaceContainerLowest: const Color(0xFF07100D),
          surfaceContainerHighest: const Color(0xFF152B1E),
        ),
        scaffoldBackgroundColor: const Color(0xFF07100D),
        useMaterial3: true,
      ),

      themeMode: ThemeMode.dark,

      // Overlay assistant au-dessus du Navigator → visible même par-dessus les
      // sheets/modales (sinon caché).
      builder: (context, child) => GlobalAssistantOverlay(child: child!),
      home: _AuthGate(),
    );
  }
}

/// Widget stateful dédié à la gate d'authentification.
/// Le stream Firebase est créé une seule fois dans initState et
/// réutilisé sans recréation à chaque rebuild du MaterialApp.
class _AuthGate extends StatefulWidget {
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  Stream<User?>? _stream;
  bool _demoSigningIn = false;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
  }

  Future<void> _signInDemo() async {
    try {
      final resp = await http.get(Uri.parse(
        'https://us-central1-productivitwo-app.cloudfunctions.net/getDemoToken',
      ));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final token = (jsonDecode(resp.body) as Map)['token'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(token);
    } catch (e) {
      debugPrint('Demo sign-in error: $e');
    } finally {
      if (mounted) setState(() => _demoSigningIn = false);
    }
  }

  Stream<User?>? _buildStream() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.authStateChanges();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final uri = Uri.base;
      final params = uri.queryParameters;

      // Prototypes moteur de jeu Flame (isolés, sans auth) — évaluation « Le Monde ».
      if (params['flame'] == '1') return const FlameProtoScreen();
      if (params['flame'] == '2') return const FlameProto2Screen();

      // DEV-LOGIN LOCAL (localhost uniquement) : connexion sur TON compte via
      // getCustomToken(uid + token API). Ne fait RIEN en prod (gardé par l'hôte).
      // S'affiche tant qu'on n'est pas sur un VRAI compte (donc aussi en démo).
      final isLocalHost = uri.host == 'localhost' || uri.host == '127.0.0.1';
      User? cur;
      try { cur = FirebaseAuth.instance.currentUser; } catch (_) {}
      final isRealUser = cur != null && cur.uid != 'demo-productivitwo';
      if (isLocalHost && params['devauth'] == '1' && !isRealUser) {
        return DevAuthScreen(onSignedIn: () { if (mounted) setState(() {}); });
      }

      // Mode démo : connexion sur compte partagé demo-productivitwo
      if (params['demo'] == 'true') {
        bool alreadyDemo = false;
        try {
          alreadyDemo = FirebaseAuth.instance.currentUser?.uid == 'demo-productivitwo';
        } catch (_) {}

        if (!alreadyDemo && !_demoSigningIn) {
          _demoSigningIn = true;
          _signInDemo();
        }

        if (_demoSigningIn) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
      }

      // Détecte un magic link dans l'URL courante (web uniquement).
      // On lit directement les query params pour éviter un race condition
      // avec l'initialisation Firebase (isSignInWithEmailLink peut throw).
      bool signedIn = false;
      try { signedIn = FirebaseAuth.instance.currentUser != null; } catch (_) {}
      if (!signedIn &&
          params['mode'] == 'signIn' &&
          params.containsKey('oobCode')) {
        // /email-signin = lien émis par l'app native → relay vers le custom scheme.
        // Tout autre chemin = lien émis par le web → on complète la connexion ici.
        if (uri.path.contains('email-signin')) {
          return WebEmailSignInScreen(emailLink: uri.toString());
        }
        // onSignedIn force un rebuild de la gate une fois connecté : sans ça, le
        // StreamBuilder (sous cet écran) n'est pas monté donc personne n'écoute
        // authStateChanges → l'écran resterait bloqué sur "Connexion en cours".
        return WebMagicLinkCompleteScreen(
          emailLink: uri.toString(),
          onSignedIn: () { if (mounted) setState(() {}); },
        );
      }
    }

    final isDemo = kIsWeb && Uri.base.queryParameters['demo'] == 'true';
    final stream = _stream;
    if (stream == null) return const WebAuthScreen();

    return StreamBuilder<User?>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const WebAuthScreen();
        }
        // Page de DÉV : prévisu mobile native dans un cadre téléphone.
        if (kIsWeb &&
            Uri.base.queryParameters['mobilepreview'] == 'true') {
          return MobilePreviewScreen(sync: FirestoreSync());
        }
        // Page de DÉV : ouvre direct le Monde (cinématique/combat) — recharge
        // la page pour re-tester.
        if (kIsWeb &&
            Uri.base.queryParameters['worldtest'] == 'true') {
          return WorldTestScreen(sync: FirestoreSync());
        }
        // Proto Flame AVEC TES DONNÉES : rend ton vrai WorldLayout en Flame.
        if (kIsWeb && Uri.base.queryParameters['flame'] == '3') {
          return FlameDataProtoScreen(sync: FirestoreSync());
        }
        return WebHomeScreen(isDemo: isDemo);
      },
    );
  }
}
