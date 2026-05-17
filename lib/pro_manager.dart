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

const kRevenueCatApiKey = 'REVENUECAT_IOS_API_KEY'; // appl_xxxx...
const kEntitlementPro = 'pro';
const kProductMonthly = 'productivitwo_pro_monthly';
const kProductAnnual = 'productivitwo_pro_annual';

class ProManager {
  static final ValueNotifier<bool> notifier = ValueNotifier(false);
  static bool get isPro => notifier.value;

  static Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey));
    await _syncStatus();
  }

  static Future<void> _syncStatus() async {
    try {
      final info = await Purchases.getCustomerInfo();
      notifier.value =
          info.entitlements.active.containsKey(kEntitlementPro);
    } catch (_) {
      // Pas de connexion — on conserve l'état précédent
    }
  }

  // Appeler après un achat ou une restauration réussis
  static void _setActive(CustomerInfo info) {
    notifier.value = info.entitlements.active.containsKey(kEntitlementPro);
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
}
