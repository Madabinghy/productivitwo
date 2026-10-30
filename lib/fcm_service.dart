import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:productivitwo_v1/notifications.dart';
import 'package:url_launcher/url_launcher.dart';

// Canal ORION — priorité haute, son par défaut
const _kOrionChannelId = 'orion_messages';
const _kOrionChannelName = 'Messages ORION';
const _kOrionNotifId = 100;

/// Handler top-level requis par firebase_messaging pour le background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Rien à faire : iOS gère l'affichage en background automatiquement via FCM
}

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;

  // Appelé quand une notif ORION est tapée (app en arrière-plan ou terminée)
  static void Function()? onOrionNotificationTap;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// À appeler après login (uid connu). Idempotent.
  static Future<void> init(String uid) async {
    if (!_supported) return;
    if (!_initialized) await _setup();

    // Enregistre/renouvelle le token FCM dans Firestore
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(uid, token);

    // Met à jour si le token se renouvelle
    _messaging.onTokenRefresh.listen((newToken) => _saveToken(uid, newToken));

    // Messages FCM reçus en foreground → affiche une notif locale
    FirebaseMessaging.onMessage.listen((message) {
      _showLocalNotif(message);
    });

    // Tap sur notif quand l'app est en arrière-plan (mais pas terminée)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  }

  static Future<void> _setup() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Permission iOS
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Plugin partagé avec NotificationService : JAMAIS de second
    // `initialize` ici (il remplaçait le routage des taps des notifications
    // de l'app). Les taps des affichages foreground passent par
    // NotificationService.onNotificationTap (charge utile « orion » / URL).
    final localNotifs = await NotificationService.plugin();
    await localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kOrionChannelId,
          _kOrionChannelName,
          description: 'Notifications de l\'agent IA ORION',
          importance: Importance.high,
        ));

    // Gestion tap quand app était terminée
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);

    _initialized = true;
  }

  static Future<void> _saveToken(String uid, String token) async {
    await FirebaseFirestore.instance
        .collection('users/$uid/orion_config')
        .doc('main')
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  static Future<void> _showLocalNotif(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;

    final type = message.data['type'] as String?;
    final url = message.data['url'] as String?;
    final payload = (type == 'github_pr' && url != null) ? url : NotificationService.kPayloadOrion;

    final localNotifs = await NotificationService.plugin();
    await localNotifs.show(
      _kOrionNotifId,
      notif.title ?? '◉ ORION',
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kOrionChannelId,
          _kOrionChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static void _handleTap(RemoteMessage message) {
    final type = message.data['type'] as String?;
    if (type == 'orion_message') {
      onOrionNotificationTap?.call();
    } else if (type == 'github_pr') {
      final url = message.data['url'] as String?;
      if (url != null) _openUrl(url);
    }
  }

  /// Ouvre une URL de notification (PR GitHub) dans le navigateur.
  static Future<void> openUrl(String url) => _openUrl(url);

  static Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> clearOrionBadge() => NotificationService.cancelById(_kOrionNotifId);
}
