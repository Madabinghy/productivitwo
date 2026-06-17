# Intégration Siri (App Intents)

Raccourcis Siri vocaux pour Productivitwo, basés sur **App Intents** (iOS 16+).
Aucune ré-authentification : les intents réutilisent le token déjà écrit dans
l'App Group au sign-in (`WidgetService.provisionAuth`).

## Ce qui est livré

| Intent | Type | Phrase Siri | Backend |
|--------|------|-------------|---------|
| `TodayScheduleIntent` | lecture | « Quel est mon programme dans Productivitwo » | App Group `schedule_json` |
| `FocusTaskIntent` | lecture | « Quelle est ma tâche du jour dans Productivitwo » | App Group `focus_task_json` |
| `LogRoutineSiriIntent` | écriture | « Coche ma routine dans Productivitwo » | MCP `log_routine_hit` |

- **Lectures** : servies depuis l'App Group → fonctionnent **hors-ligne**, sans ouvrir l'app.
- **Écriture** : `LogRoutineSiriIntent` met à jour l'App Group de façon optimiste, recharge
  les widgets, puis appelle `mcpHandler` (même endpoint/format que les boutons de widget).
- **Résolution par nom** : `RoutineAppEntity` + `RoutineEntityQuery` lisent `routines_json`,
  donc Siri propose les routines par leur libellé (« Méditation »…), pas par ID.

## Fichiers

| Fichier | Rôle |
|---------|------|
| `ios/Runner/SiriIntents.swift` | Intents + `RoutineAppEntity` + `ProductivitwoShortcuts` (AppShortcutsProvider) |
| `ios/Runner/AppDelegate.swift` | Method channel `updateSiriShortcuts` → refresh des options |
| `ios/Runner/Info.plist` | `NSSiriUsageDescription` |
| `lib/siri_service.dart` | `SiriService.refreshShortcuts()` (pont Flutter) |
| `lib/main.dart` | Bouton « Siri & Raccourcis » dans Paramètres (iOS only) |

Les 3 intents existants du **widget** (`MarkRoutineDoneIntent`…) restent inchangés :
ils servent de boutons de widget. Les intents Siri sont **séparés** (target Runner) car
un `AppShortcutsProvider` doit vivre dans le target app principal.

## Build

`SiriIntents.swift` est déjà référencé dans `Runner.xcodeproj/project.pbxproj`
(PBXBuildFile + PBXFileReference + groupe Runner + Sources build phase).
→ **Compile sans étape Xcode manuelle.** Build normal : `flutter build ios`.

## Étapes manuelles éventuelles (selon besoin)

1. **Capability Siri** : *non requise* pour les App Intents (les App Shortcuts sont indexés
   automatiquement à l'installation). À n'activer que pour du SiriKit avancé.
   Si activée : Xcode → Signing & Capabilities → + Siri, et le profil de provisioning
   doit porter la capability côté Apple Developer.
2. **Test** : installer sur device iOS 16+, dire « Dis Siri, quel est mon programme dans
   Productivitwo ». Les raccourcis apparaissent aussi dans l'app **Raccourcis**.
3. Le bouton in-app (Paramètres → Siri & Raccourcis) rafraîchit les options et ouvre
   l'app Raccourcis (`shortcuts://`).

## Limites

- iOS 16+ uniquement (tout est gardé par `@available(iOS 16.0, *)`). Deployment target
  reste 15.0 ; sur iOS 15 les raccourcis ne s'affichent simplement pas.
- Pas de SiriKit `.intentdefinition` legacy (approche moderne App Intents).
- L'écriture nécessite réseau + token provisionné (sign-in fait au moins une fois dans l'app).
