import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/web/web_auth_screen.dart';
import 'package:productivitwo_v1/web/web_home_screen.dart';
import 'package:productivitwo_v1/web/web_email_signin_screen.dart';

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

      themeMode: ThemeMode.system,

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

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
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
    // Détecte un magic link dans l'URL courante (web uniquement).
    // On lit directement les query params pour éviter un race condition
    // avec l'initialisation Firebase (isSignInWithEmailLink peut throw).
    if (kIsWeb) {
      final uri = Uri.base;
      final params = uri.queryParameters;
      if (params['mode'] == 'signIn' && params.containsKey('oobCode')) {
        return WebEmailSignInScreen(emailLink: uri.toString());
      }
    }

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
        return const WebHomeScreen();
      },
    );
  }
}
