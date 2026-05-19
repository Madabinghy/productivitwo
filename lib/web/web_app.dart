import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/web/web_auth_screen.dart';
import 'package:productivitwo_v1/web/web_home_screen.dart';

// ── Couleurs Productivitwo ────────────────────────────────────────────────────

const _kPrimary   = Color(0xFF6B57F0); // violet principal
const _kTeal      = Color(0xFF1D9E75); // teal actif
const _kSeedLight = _kPrimary;
const _kSeedDark  = Color(0xFF8B77FF); // violet éclairci pour fond sombre

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Productivitwo — Projects',
      debugShowCheckedModeBanner: false,

      // ── Thème clair ────────────────────────────────────────────────────────
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kSeedLight,
          brightness: Brightness.light,
        ).copyWith(
          primary: _kPrimary,
          secondary: _kTeal,
        ),
        useMaterial3: true,
      ),

      // ── Thème sombre ───────────────────────────────────────────────────────
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kSeedDark,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _kSeedDark,
          secondary: _kTeal,
          surface: const Color(0xFF1C1830),
          surfaceContainerLowest: const Color(0xFF120F22),
          surfaceContainerHighest: const Color(0xFF2A2445),
        ),
        useMaterial3: true,
      ),

      // Suit la préférence système de l'utilisateur
      themeMode: ThemeMode.system,

      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data == null) return const WebAuthScreen();
          return const WebHomeScreen();
        },
      ),
    );
  }
}
