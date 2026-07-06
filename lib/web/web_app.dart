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
import 'package:productivitwo_v1/prototypes/td_prototype.dart';
import 'package:productivitwo_v1/prototypes/overworld_prototype.dart';
import 'package:productivitwo_v1/prototypes/level_prototype.dart';
import 'package:productivitwo_v1/prototypes/rive_poc_screen.dart';
import 'package:productivitwo_v1/prototypes/expedition_prototype.dart';
import 'package:productivitwo_v1/web/fluo_data_screen.dart';
import 'package:productivitwo_v1/web/flame_data_proto_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_preview_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_home_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_routine_types_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_streak_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_balance_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_project_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_celebration_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_onboarding_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_focus_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_lair_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_strategy_screen.dart';
import 'package:productivitwo_v1/main.dart'
    show softpopShellEnabled, loadSoftpopShellFlag;
import 'package:productivitwo_v1/web/orbit_data_screen.dart';
import 'package:productivitwo_v1/web/rpg_data_screen.dart';
import 'package:productivitwo_v1/web/pet_data_screen.dart';
import 'package:productivitwo_v1/web/defense_data_screen.dart';
import 'package:productivitwo_v1/web/village_data_screen.dart';
import 'package:productivitwo_v1/web/iso_world_screen.dart';
import 'package:productivitwo_v1/web/organic_map_screen.dart';
import 'package:productivitwo_v1/web/dev_auth_screen.dart';

// ── Tampon de build ───────────────────────────────────────────────────────────
// Affiché en bas de CHAQUE écran web + imprimé au démarrage (terminal flutter run
// + console navigateur). Sert à vérifier d'un coup d'œil qu'on n'exécute pas un
// vieux build en local. À bumper à chaque changement de routing/auth notable.
const String kWebBuildTag = 'build 2026-06-23g · sans scorpion compagnon';

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
      // sheets/modales (sinon caché). + tampon de build (coin bas-gauche).
      builder: (context, child) => GlobalAssistantOverlay(
        child: Stack(children: [
          child!,
          Positioned(
            left: 4,
            bottom: 2,
            child: IgnorePointer(
              child: Text(
                kWebBuildTag,
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withOpacity(.35),
                    decoration: TextDecoration.none),
              ),
            ),
          ),
        ]),
      ),
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
    // Flag refonte (par navigateur) : permet à la PWA installée (start_url "/")
    // d'ouvrir directement le shell Soft Pop une fois activé.
    loadSoftpopShellFlag().then((_) {
      if (mounted) setState(() {});
    });
    softpopShellEnabled.addListener(_onSoftpopFlag);
  }

  void _onSoftpopFlag() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    softpopShellEnabled.removeListener(_onSoftpopFlag);
    super.dispose();
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
      // Toutes les routes de PROTOTYPES (jeu, previews Soft Pop) sont réservées
      // au dev local : plus exposées en prod depuis le pivot productivité.
      final isLocalHost = uri.host == 'localhost' || uri.host == '127.0.0.1';

      if (isLocalHost) {
        // Prototypes moteur de jeu Flame (isolés, sans auth) — évaluation « Le Monde ».
        if (params['flame'] == '1') return const FlameProtoScreen();
        if (params['flame'] == '2') return const FlameProto2Screen();

        // Proto Tower Defense jouable (sans auth ni données) — test du feeling.
        if (params['proto'] == 'td') return const TdGameScreen();
        // Proto Overworld fluo (héros déplaçable) — sans auth.
        if (params['proto'] == 'world') return const OverworldScreen();
        // Proto Carte de niveau fluo (héros explorable, pièces, POI) — sans auth.
        if (params['proto'] == 'level') return const LevelScreen();
        // POC Rive (perso animé chargé depuis le réseau) — sans auth.
        if (params['proto'] == 'rive') return const RivePocScreen();
        // Proto Expédition de la semaine (carte d'ascension, défis, combats) — sans auth.
        if (params['proto'] == 'expedition') return const ExpeditionScreen();
        // Aperçus refonte « Soft Pop » (sans auth ni données). Les écrans sont des
        // Scaffold sans MaterialApp → on les enveloppe ici pour l'entrée web.
        final softpop = params['softpop'];
        if (softpop != null) {
          final screen = <String, Widget>{
            '1': const SoftPopPreviewScreen(),
            'home': const SoftPopHomeScreen(),
            'routine': const SoftPopRoutineTypesScreen(),
            'streak': const SoftPopStreakScreen(),
            'balance': const SoftPopBalanceScreen(),
            'project': const SoftPopProjectScreen(),
            'celebrate': const SoftPopCelebrationScreen(),
            'onboarding': const SoftPopOnboardingScreen(),
            'focus': const SoftPopFocusScreen(),
            'lair': const SoftPopLairScreen(),
            'strategy': const SoftPopStrategyScreen(),
          }[softpop];
          if (screen != null) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('fr', 'FR'),
              home: screen,
            );
          }
        }
      }

      // DEV-LOGIN LOCAL (localhost uniquement) : connexion sur TON compte via
      // getCustomToken(uid + token API). Ne fait RIEN en prod (gardé par l'hôte).
      // S'affiche tant qu'on n'est pas sur un VRAI compte (donc aussi en démo).
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
          // En localhost, les pages de DÉV (worldtest / mobilepreview / flame=3)
          // exigent une vraie session → on bascule direct sur le dev-login (token
          // pré‑rempli depuis l'URL ou le localStorage) plutôt que l'auth publique.
          final p = Uri.base.queryParameters;
          final localhost =
              Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';
          if (kIsWeb &&
              localhost &&
              (p['worldtest'] == 'true' ||
                  p['mobilepreview'] == 'true' ||
                  p['flame'] == '3' ||
                  p['devauth'] == '1')) {
            return DevAuthScreen(
                onSignedIn: () {
                  if (mounted) setState(() {});
                });
          }
          return const WebAuthScreen();
        }
        // Page de DÉV : prévisu mobile native dans un cadre téléphone.
        if (kIsWeb &&
            Uri.base.queryParameters['mobilepreview'] == 'true') {
          return MobilePreviewScreen(sync: FirestoreSync());
        }
        // Nouvelle UI Soft Pop AVEC TES DONNÉES (sans build iOS) : ?softpop=app
        // l'active, et le flag persistant la rouvre ensuite à la racine "/"
        // (donc la PWA installée ouvre directement le shell). Réversible.
        if (kIsWeb &&
            (Uri.base.queryParameters['softpop'] == 'app' ||
                softpopShellEnabled.value)) {
          if (Uri.base.queryParameters['softpop'] == 'app') {
            softpopShellEnabled.value = true;
          }
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
        // Protos « avec tes données » (galaxie, RPG, compagnon, défense,
        // village, iso, carte organique) : DEV LOCAL UNIQUEMENT depuis le
        // pivot productivité — plus accessibles en prod, même authentifié.
        final protoDev = kIsWeb &&
            (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1');
        // « Fluo Adventure » : galaxie (domaines autour d'Aujourd'hui) → tape
        // une planète → map (activités) → carte à nœuds (?proto=orbit / fluo).
        if (protoDev &&
            (Uri.base.queryParameters['proto'] == 'orbit' ||
                Uri.base.queryParameters['proto'] == 'fluo')) {
          return FluoDataScreen(sync: FirestoreSync());
        }
        // Galaxie « pure » (contemplation, tap = info, sans navigation).
        if (protoDev && Uri.base.queryParameters['proto'] == 'galaxy') {
          return OrbitDataScreen(sync: FirestoreSync());
        }
        // Proto « RPG / Stats » AVEC TES DONNÉES : domaines = attributs.
        if (protoDev && Uri.base.queryParameters['proto'] == 'rpg') {
          return RpgDataScreen(sync: FirestoreSync());
        }
        // Proto « Compagnon » AVEC TES DONNÉES : humeur = ta régularité.
        if (protoDev && Uri.base.queryParameters['proto'] == 'pet') {
          return PetDataScreen(sync: FirestoreSync());
        }
        // Proto « Défense néon » AVEC TES DONNÉES : domaines = tourelles.
        if (protoDev && Uri.base.queryParameters['proto'] == 'defense') {
          return DefenseDataScreen(sync: FirestoreSync());
        }
        // Proto « Village » AVEC TES DONNÉES : chaque action bâtit ton monde.
        if (protoDev && Uri.base.queryParameters['proto'] == 'village') {
          return VillageDataScreen(sync: FirestoreSync());
        }
        // Proto « Monde isométrique » AVEC TES DONNÉES (pixel-art blocks).
        if (protoDev && Uri.base.queryParameters['world'] == 'iso') {
          return IsoWorldScreen(sync: FirestoreSync());
        }
        // Carte ORGANIQUE contemplative (parchemin, type deepnight).
        if (protoDev && Uri.base.queryParameters['map'] == 'organic') {
          return OrganicMapScreen(sync: FirestoreSync());
        }
        return WebHomeScreen(isDemo: isDemo);
      },
    );
  }
}
