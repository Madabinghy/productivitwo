# Productivitwo sur Mac — mode « Conçue pour iPhone » (Apple Silicon)

## Pourquoi

Le widget Productivitwo affiché sur le bureau du Mac est aujourd'hui le **widget de l'iPhone**,
relayé par Continuité (macOS Sonoma+). Depuis macOS Sequoia, cliquer dessus ouvre l'app via
**Recopie de l'iPhone** (iPhone Mirroring), qu'Apple ne propose pas dans l'Union européenne
(DMA). En France, le clic échoue donc avec « La recopie de l'iPhone n'est pas disponible dans
votre pays ou région », et les boutons interactifs du widget ne s'exécutent pas depuis le Mac.

Solution retenue : rendre l'app iPhone **installable sur Mac Apple Silicon** (mode « Conçue pour
iPhone »). Le widget devient alors un widget **natif Mac** : le clic ouvre l'app localement
(URL scheme `com.madabinghy.productivitwo`), les boutons (cocher une routine, etc.) appellent
`mcpHandler` directement depuis le Mac.

Aucune compilation séparée : c'est le **même binaire iOS** (`SUPPORTED_PLATFORMS = iphoneos`,
`TARGETED_DEVICE_FAMILY = 1`), Xcode Cloud ne change pas. L'activation est un réglage
**App Store Connect**.

## Activer (toi, dans App Store Connect)

1. App Store Connect → **Productivitwo** → **Tarifs et disponibilité** (Pricing and Availability).
2. Section **Mac** (ou « Disponibilité des apps iPhone et iPad sur Mac ») → cocher
   **« Rendre cette app disponible sur Mac »** (Make this app available on Mac) → Enregistrer.
3. La prochaine build déjà approuvée devient téléchargeable sur le Mac App Store
   (Apple Silicon, macOS 12+), étiquetée « Conçue pour iPhone ». Pas de nouvelle soumission
   nécessaire ; si la case est grisée, le Review a jugé l'app incompatible : il faut alors
   soumettre une build avec une note Review.
4. Sur le Mac : App Store → Mon compte → onglet **iPhone et iPad** → installer Productivitwo.

Tester avant d'ouvrir au public :
- **TestFlight pour Mac** : l'app TestFlight macOS liste les builds iOS si la case ci-dessus est
  cochée. C'est le chemin le plus simple.
- **Xcode local** : ouvrir `ios/Runner.xcworkspace`, destination **My Mac (Designed for
  iPhone)**, Run. (`flutter run` ne connaît pas cette destination, passer par Xcode.)

Retour arrière : décocher la case. Les Mac qui ont déjà l'app la gardent mais ne reçoivent plus
de mises à jour.

## Le widget côté Mac

Une fois l'app installée, la galerie de widgets du Mac liste **deux** Productivitwo : celui
« de l'iPhone » (Continuité, à retirer) et celui de l'app Mac (à ajouter). Seul le second ouvre
l'app et exécute les boutons. Les données passent par le même App Group
(`group.com.madabinghy.productivitwo`) et la même auth MCP (`mcp_uid` + `mcp_token` posés par
`WidgetService.provisionAuth`) : rien à reconfigurer, se connecter une fois dans l'app Mac.

## Audit de compatibilité (2026-10)

| Brique | Mac « Conçue pour iPhone » | Note |
|---|---|---|
| Flutter (Metal, clavier, souris) | ✅ | `UIApplicationSupportsIndirectInputEvents` déjà posé. Fenêtre taille iPhone, non redimensionnable ; landscape possible via menu Fenêtre (orientations déclarées). |
| Firebase Auth / Firestore / Messaging | ✅ | APNs fonctionne pour les apps iOS sur Mac (macOS 11+), même clé APNs. |
| Sign in with Apple | ✅ | Pris en charge nativement. |
| RevenueCat (`purchases_flutter`) | ✅ | Supporté pour les apps iOS sur Mac. Sans effet aujourd'hui (`kFreeForAll = true`). |
| Widget WidgetKit + boutons App Intents | ✅ | C'est le but. App Group partagé. |
| Siri / App Shortcuts | ⚠️ | Les raccourcis apparaissent dans l'app **Raccourcis** du Mac ; Siri Mac les expose de façon inégale. |
| Live Activities (minuteur) | ❌ | Inexistantes sur Mac. `areActivitiesEnabled` renvoie false → `start` renvoie nil, le Dart ignore. Garde-fou ajouté sur `pushToStartToken` (sinon aucune réponse jamais renvoyée). |
| Alarme minuteur (`alarm`) | ⚠️ | Audio + notification OK ; pas de vibration ; le mode « plein écran » est Android. À vérifier en TestFlight Mac : la sonnerie en app fermée. |
| Notifications locales | ✅ | UNUserNotificationCenter, demande d'autorisation macOS au premier lancement. |
| Partage, impression, sélection de fichier (`share_plus`, `printing`, `file_selector`) | ✅ | Idiome iPhone sur Mac → pas d'ancrage popover requis. |
| WebView, `url_launcher`, `app_links`, `connectivity_plus`, `google_fonts` | ✅ | Rien de spécifique. |

Détection côté natif si besoin d'adapter un comportement : `ProcessInfo.processInfo.isiOSAppOnMac`
(iOS 14+). Côté Dart, `Platform.isIOS` reste **vrai** sur Mac dans ce mode.

## Ce qu'on ne fait pas

- Pas de cible **Mac Catalyst** ni de build `flutter build macos` : double maintenance, plugins
  (`alarm`, `home_widget`, `purchases_flutter`) non alignés. L'app web reste l'interface
  « grand écran » du Mac ; l'app « Conçue pour iPhone » sert au widget et aux notifications.
