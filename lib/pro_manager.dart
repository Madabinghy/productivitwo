import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// À REMPLIR avant de soumettre sur l'App Store :
//   1. Créer une app dans RevenueCat (app.revenuecat.com)
//   2. Copier la clé API iOS  → kRevenueCatApiKey
//   3. Créer l'entitlement "pro" dans RevenueCat
//   4. Créer les produits dans App Store Connect puis les lier dans RevenueCat
//      - Abonnement mensuel  → kProductMonthly  (ex: com.madabinghy.productivitwo.pro_monthly)
//      - Abonnement annuel   → kProductAnnual   (ex: com.madabinghy.productivitwo.pro_annual)
// ─────────────────────────────────────────────────────────────────────────────

const kRevenueCatApiKey = 'appl_mPnLsGNfqBUGiVIOqRuCbRzlOYk';
const kEntitlementPro = 'pro';
const kProductMonthly = 'productivitwo_pro_monthly';
const kProductAnnual = 'productivitwo_pro_annual';

class ProManager {
  static final ValueNotifier<bool> notifier = ValueNotifier(false);
  static bool get isPro => notifier.value;

  // Pro effectif = abonnement RevenueCat OU grant Firestore (formation_access.
  // proUntil > maintenant — accordé depuis l'admin, ex. beta-testeurs).
  static bool _rcPro = false;
  static bool _grantPro = false;
  static void _recompute() => notifier.value = _rcPro || _grantPro;

  static Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey));
    await _syncStatus();
    await refreshGrant();
  }

  static Future<void> _syncStatus() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _rcPro = info.entitlements.active.containsKey(kEntitlementPro);
      _recompute();
    } catch (_) {
      // Pas de connexion — on conserve l'état précédent
    }
  }

  // Lit le grant Pro Firestore (formation_access/{uid}.proUntil) et recalcule.
  static Future<void> refreshGrant([String? uid]) async {
    final u = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (u == null) {
      _grantPro = false;
      _recompute();
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('formation_access')
          .doc(u)
          .get();
      final data = doc.data();
      final until = data?['proUntil'];
      if (until is Timestamp) {
        _grantPro = until.toDate().isAfter(DateTime.now());
      } else if (until == null && data?['isPro'] == true) {
        _grantPro = true; // legacy / sans expiration
      } else {
        _grantPro = false;
      }
    } catch (_) {
      // Pas de doc / pas d'accès — on garde l'état RevenueCat
    }
    _recompute();
  }

  // Appeler après un achat ou une restauration réussis
  static void _setActive(CustomerInfo info) {
    _rcPro = info.entitlements.active.containsKey(kEntitlementPro);
    _recompute();
  }

  static Future<CustomerInfo?> purchase(Package package) async {
    final info = await Purchases.purchasePackage(package);
    _setActive(info);
    return info;
  }

  static Future<CustomerInfo?> restore() async {
    final info = await Purchases.restorePurchases();
    _setActive(info);
    return info;
  }

  static Future<void> deactivate() async {
    _rcPro = false;
    _grantPro = false;
    _recompute();
  }

  // Appeler après Sign in with Apple pour lier les achats au compte
  static Future<void> loginUser(String uid) async {
    try {
      final info = await Purchases.logIn(uid);
      _rcPro = info.customerInfo.entitlements.active.containsKey(kEntitlementPro);
      _recompute();
    } catch (_) {}
    await refreshGrant(uid);
  }

  // Appeler après déconnexion
  static Future<void> logoutUser() async {
    try {
      await Purchases.logOut();
    } catch (_) {}
    await _syncStatus();
    await refreshGrant(null);
  }
}
