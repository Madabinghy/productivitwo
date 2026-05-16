import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProManager {
  static const _key = 'productivitwo_pro';

  static final ValueNotifier<bool> notifier = ValueNotifier(false);
  static bool get isPro => notifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    notifier.value = prefs.getBool(_key) ?? false;
  }

  // Appeler après validation RevenueCat / StoreKit
  static Future<void> activate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    notifier.value = true;
  }

  static Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    notifier.value = false;
  }
}
