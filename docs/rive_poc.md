# POC Rive — héros animé piloté par les données

Objectif : remplacer le héros « fluo » dessiné au CustomPainter par un personnage
**Rive** dont l'humeur et l'animation sont pilotées par la **régularité réelle** de
l'utilisateur, pour juger le saut de charme (cf. Duolingo).

> Rive **n'est pas** un moteur de jeu (pas de boucle, physique ni collisions).
> C'est un runtime d'animation vectorielle interactive (State Machines + inputs +
> data binding). **Le moteur reste en code** (Dart / nos `CustomPainter`/`Ticker`) ;
> Rive ne fournit que la **couche visuelle** du perso.

---

## Ce que livre ce POC

1. **Intégration câblée** : package `rive: ^0.13.20` ajouté à `pubspec.yaml`,
   `flutter pub get` OK (web + mobile).
2. **Route de test** `?proto=rive` → `lib/prototypes/rive_poc_screen.dart`
   (sans auth). Charge une anim Rive **depuis le réseau** (`RiveAnimation.network`)
   pour valider le rendu dans l'app, sur web ET mobile.
3. **Ce cahier des charges** du `hero.riv` sur-mesure (ci-dessous).

> ⚠️ L'éditeur Claude est bloqué par son proxy sur le CDN Rive (403), il ne peut
> donc pas produire le binaire `.riv` lui-même. L'échantillon affiché est une démo
> publique générique : il prouve le **rendu**, pas le perso final. Le `hero.riv`
> doit être créé dans l'éditeur Rive (rive.app) selon la spec ci-dessous.

---

## Spec `hero.riv`

### Artboard
- `Hero` — un seul artboard, ~200×200, fond transparent.

### State Machine : `HeroMachine`
Inputs (pilotés par notre code Dart) :

| Input | Type | Sémantique côté app |
|-------|------|---------------------|
| `walking` | bool | `true` quand le héros se déplace (joystick/tap-to-move) |
| `mood` | number (0..4) | humeur dérivée de la régularité (voir mapping) |
| `celebrate` | trigger | one-shot quand une action est validée / un combat gagné |

### États (animations)
- `idle` — respiration douce (mood neutre, immobile)
- `walk` — cycle de marche (déclenché par `walking == true`)
- `happy` — mood élevé (sourire, petits sauts)
- `sad` — mood bas (épaules tombantes, lent)
- `asleep` — inactivité prolongée (yeux fermés, « Zzz »)

### Transitions
- `idle → walk` quand `walking` devient `true` ; `walk → idle` sinon.
- couche **mood** (layer séparé ou blend) :
  `mood <= 1 → sad`, `mood == 2 → idle/neutre`, `mood >= 3 → happy`,
  `mood == 0 && inactif → asleep`.
- `celebrate` (trigger) joue `happy` une fois puis revient à l'état courant.

---

## Mapping données → inputs (côté Dart)

La régularité est déjà calculée par `buildFluoData()` (énergie par activité,
streaks, soleil 24h glissant). Pour le héros global on dérive un `mood` 0..4 :

```
energieJour = soleil 24h / record        // 0..1, déjà calculé (_computeSun)
streak      = max des streaks d'activités // jours
mood =
  energieJour <= 0.05            -> 0  (asleep si aussi inactif)
  energieJour <  0.25            -> 1  (sad)
  energieJour <  0.55            -> 2  (neutre)
  energieJour <  0.85            -> 3  (happy)
  sinon                          -> 4  (happy +)
walking  = le héros bouge (joystick actif ou trajet tap-to-move en cours)
celebrate-> à chaque logic.markActionDone / victoire combat
```

Câblage runtime :
```dart
StateMachineController? _ctrl;
SMIBool? _walking;
SMINumber? _mood;
SMITrigger? _celebrate;

void _onRiveInit(Artboard art) {
  _ctrl = StateMachineController.fromArtboard(art, 'HeroMachine');
  art.addController(_ctrl!);
  _walking = _ctrl!.findInput<bool>('walking') as SMIBool?;
  _mood = _ctrl!.findInput<double>('mood') as SMINumber?;
  _celebrate = _ctrl!.findSMI('celebrate') as SMITrigger?;
}
// puis dans le tick : _walking?.value = moving; _mood?.value = mood.toDouble();
```

---

## Fallback (si pas de `hero.riv`)
Le héros CustomPainter actuel (`fluo_prototype.dart`) reste la couche par défaut.
Le swap Rive est purement visuel : la logique de déplacement/collision/combat ne
change pas. On peut donc livrer le `.riv` plus tard sans rien casser.

---

## Tester
Ouvrir sur mobile ou web : `app.productivitwo.com/?proto=rive`.
Si l'animation bouge → Rive tourne bien dans l'app, le POC est validé.
