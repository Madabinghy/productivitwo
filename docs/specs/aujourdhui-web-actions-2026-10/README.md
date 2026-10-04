# Aujourd'hui web, orienté action (2026-10)

**Demande** : rendre l'onglet Aujourd'hui de l'app web plus orienté action : voir *concrètement* ce
qu'il y a à faire dans les blocs du programme (comme la carte MAINTENANT du mobile) et voir quelques
routines disponibles (comme « Le meilleur à faire » du mobile).

## Ce qui change (`lib/web/views/today_view.dart`)

1. **Carte « Au programme · concrètement »** — sous MAINTENANT (disposition repos, colonne de gauche de
   340 px), dans la colonne de droite quand la bande Focus est affichée, en tête de page en étroit.
   - Liste les blocs `pending` non terminés (6 au plus, lien « Voir les n autres blocs »).
   - Ligne repliée : case « bloc fait » (`_toggleDone`), heure, titre, **indice concret**
     (`_blockHint`), ▶ chrono sur le bloc (si une activité est joignable et que le chrono n'y est pas déjà).
   - Dépliée (par défaut, le premier bloc qui a un contenu) :
     - **action visée** (`_blockSteps`) : action cochable (`setActionDone`) + étapes `ChecklistEditor`
       (cocher, ajouter) — mêmes règles que Réalisation (dernier item coché = action faite) ;
     - **bloc d'activité sans action ciblée** : « Possible dans ce bloc » = actions propres ouvertes de
       l'activité (5 au plus) ; un tap = faite, annulable ;
     - **bloc de routine** : avancement + bouton **+1** ;
     - **bloc projet sans action** : « Définir la prochaine action » (ouvre la fiche projet).
   - Bloc sans contenu : un tap ouvre l'éditeur du bloc.
2. **Frise** : les blocs assez hauts (> 84 px) affichent la même ligne concrète
   (« → prochaine étape · 2/5 », « 3 actions possibles · … », « Routine · 1 / 2 aujourd'hui »,
   « Aucune action définie »).
3. **Carte « Routines du jour »** (colonne de droite, au-dessus de Cette semaine) : routines
   quotidiennes et hebdomadaires non atteintes (5 au plus, « Voir toutes »), compteur « x / n
   atteintes », point de couleur du domaine, **+1** persistant (`HabitProgress` + `HabitHit`) avec
   « Annuler » (décrément unifié `incHabit(-1)`, qui supprime le hit).

## Logique pure

`lib/utils/routines_today.dart` — `routinesForToday(activities, hits, now)` : exclut supprimées,
non-routines et mensuelles ; quotidienne = hits depuis minuit vs `habitTarget` ; hebdo =
`rollingStatFor` (7 j glissants). Tri : non atteintes d'abord (les plus avancées en tête), puis
atteintes ; à égalité, alphabétique. Tests : `test/routines_today_test.dart`.

## Hors périmètre

Pas de changement de modèle ni de serveur. Mobile inchangé.
