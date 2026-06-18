# Live Activity « minuteur » — setup Xcode / Apple (Phase 1)

Objectif Phase 1 : afficher un minuteur live (écran verrouillé + Dynamic Island) **quand l'app
tourne / est observée** (y compris une session lancée depuis le web, via le stream Firestore).
La Phase 2 (push‑to‑start, **app fermée**) ajoutera une Cloud Function + APNs.

> ⚠️ Tout l'iOS ci‑dessous se valide **dans Xcode sur un vrai iPhone iOS 16.1+** (les Live
> Activities ne marchent pas en simulateur pour les pushs ; Phase 1 marche en simulateur iOS 16.2+).

## Fichiers livrés (code)
- `lib/live_activity_service.dart` — pont Dart (MethodChannel `productivitwo/live_activity`), no‑op hors iOS.
- `lib/main.dart` — stream des sessions côté mobile → démarre/termine la Live Activity.
- `ios/Runner/AppDelegate.swift` — enregistre le channel, délègue au manager.
- `ios/Runner/LiveActivityManager.swift` — ActivityKit start/end (+ token Phase 2).
- `ios/Shared/TimerActivityAttributes.swift` — attributs PARTAGÉS (app + widget).
- `ios/ProductivitwoWidget/TimerLiveActivity.swift` — UI (lock screen + Dynamic Island).
- `ios/ProductivitwoWidget/ProductivitwoWidgetBundle.swift` — enregistre `TimerLiveActivity()`.
- `ios/Runner/Info.plist` — `NSSupportsLiveActivities` (+ `remote-notification`).

## À faire dans Xcode (toi)
1. **Ajouter les fichiers au projet** (s'ils n'y sont pas déjà via le pbxproj) :
   - `ios/Runner/LiveActivityManager.swift` → target **Runner**.
   - `ios/ProductivitwoWidget/TimerLiveActivity.swift` → target **ProductivitwoWidget**.
   - `ios/Shared/TimerActivityAttributes.swift` → **Target Membership = Runner ET ProductivitwoWidget** (les deux !). C'est indispensable : le type `ActivityAttributes` doit être identique des deux côtés.
2. **Info.plist du target Runner** : vérifier que `NSSupportsLiveActivities = YES` est bien pris (déjà ajouté dans le fichier).
3. **Capabilities** (onglet Signing & Capabilities du target Runner) : ajouter **Push Notifications** (nécessaire pour la Phase 2 ; sans danger pour la Phase 1).
4. **Build & run sur un iPhone** (ou simulateur iOS 16.2+). Lancer un minuteur depuis l'app (ou le web) → la Live Activity doit apparaître ; arrêter → elle disparaît.

## Phase 2 (à venir — app fermée)
- Apple Developer : activer **Live Activities** + créer une **clé APNs .p8** (Key ID + Team ID).
- Cloud Function `onDocumentCreated(users/{uid}/sessions/{id})` → APNs direct
  (`apns-push-type: liveactivity`, `apns-topic: <bundleId>.push-type.liveactivity`, event `start`/`end`).
- Dart : appeler `LiveActivityService.instance.pushToStartToken()` au lancement et stocker le token
  dans Firestore (`users/{uid}/live_activity/{deviceId}`).

## Phase 2 — mise en service (push‑to‑start, app fermée)

Le **code est déjà livré** mais NON déployé (pour ne pas casser le déploiement des functions
sans secrets). Étapes pour l'activer :

1. **Apple** : sur l'App ID, activer **Push Notifications** + **Live Activities** ; créer une **clé
   APNs (.p8)** → note le **Key ID** et le **Team ID**. Bundle id = celui de l'app.
2. **Secrets Firebase** (depuis `functions/`) :
   ```sh
   firebase functions:secrets:set APNS_KEY        # colle le CONTENU du .p8
   firebase functions:secrets:set APNS_KEY_ID     # ex: ABCD1234EF
   firebase functions:secrets:set APNS_TEAM_ID    # ex: TEAM123456
   firebase functions:secrets:set APNS_BUNDLE_ID  # ex: com.madabinghy.productivitwo
   ```
   *(Build de DEV/TestFlight → APNs **sandbox** : pose aussi `APNS_HOST=https://api.sandbox.push.apple.com`
   en variable d'env de la function ; prod App Store = défaut `api.push.apple.com`.)*
3. **Brancher les triggers** dans `functions/src/index.ts` (1 ligne) :
   ```ts
   export { onSessionStartLiveActivity, onSessionEndLiveActivity } from "./live_activity_triggers";
   ```
4. `npm run build` puis `firebase deploy --only functions:onSessionStartLiveActivity,functions:onSessionEndLiveActivity`.
5. **Côté app** : ouvrir l'app au moins une fois (pose le push‑to‑start token dans
   `users/{uid}/live_activity/main`). Puis, **app fermée**, lancer un minuteur depuis le web → la
   Live Activity doit apparaître ; stop → elle se termine.

Fichiers livrés Phase 2 : `lib/live_activity_service.dart` (+ token handler), `lib/main.dart`
(persistance token), `lib/firestore_sync.dart` (`saveLiveActivityToken`),
`ios/Runner/LiveActivityManager.swift` (+ observation tokens), `ios/Runner/AppDelegate.swift`
(`registerPushToStart`), `functions/src/apns.ts`, `functions/src/live_activity_triggers.ts`.

## Notes techniques
- Le compte au‑dessus est rendu par iOS via `Text(start, style: .timer)` → **pas** de push par seconde.
- Une seule Live Activity « minuteur » à la fois (le manager termine la précédente au démarrage).
- Le pont Dart est **no‑op** hors iOS (`defaultTargetPlatform`), donc le build web/Android n'est pas impacté.
