import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/web/web_auth_screen.dart';
import 'package:productivitwo_v1/web/web_home_screen.dart';

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Productivitwo — Projects',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B57F0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      ),
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
