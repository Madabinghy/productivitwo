import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  static final _localNotifs = FlutterLocalNotificationsPlugin();
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

    // Canal Android + init local notifications pour affichage foreground
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    await _localNotifs.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: darwinSettings),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload == 'orion') onOrionNotificationTap?.call();
      },
    );

    await _localNotifs
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

  static void _showLocalNotif(RemoteMessage message) {
    final notif = message.notification;
    if (notif == null) return;

    _localNotifs.show(
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
      payload: 'orion',
    );
  }

  static void _handleTap(RemoteMessage message) {
    if (message.data['type'] == 'orion_message') {
      onOrionNotificationTap?.call();
    }
  }
}
