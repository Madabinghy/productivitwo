# Handoff — Export / import des donnees (lot « Coffre »)

Feature : **Mes donnees** — export d'une sauvegarde complete + restauration.
Cible : Productivitwo (Flutter iOS/Android/Web, Firebase). UI en francais.
Repo source : `Madabinghy/productivitwo`, branche `main`.

---

## 1. Contexte

`CLAUDE.md` porte au backlog : « Export / import des donnees (note 2026-07-19) : demande par
l'utilisateur, reporte volontairement — a cadrer avant d'implementer ». Ce handoff est ce cadrage,
tranche avec le designer :

- **Retenu** : la sauvegarde JSON complete + la restauration (« le coffre »).
- **Ecarte pour l'instant** : export CSV analytique et import de migration (mapping de colonnes).
  Ne pas les implementer, ne pas laisser d'entree UI qui y renvoie.
- **Calendrier** : apres la V1 (perimetre gele jusqu'au 17/08/2026), avant l'Espace Coach V1.1.
- **Lotissement** : lot 1 = export seul (livrable independant) ; lot 2 = restauration.

Justification produit : la portabilite RGPD est couverte immediatement, l'historique long
(le cout de sortie de l'abonnement) devient restituable, et on obtient un filet avant toute
migration de schema.

---

## 2. A propos des fichiers de design

`Export-import cadrage.dc.html` est une **reference de design en HTML** : une maquette
qui montre l'intention visuelle, la copie exacte et les etats a couvrir. Ce n'est pas du code
a porter tel quel. Le travail consiste a **recreer ces ecrans en Flutter**, avec les patterns
deja en place dans le repo (Material 3, `ThemeData` de `main.dart`, sheets modales
`showModalBottomSheet`, `ListTile`, `FilledButton`), pas a traduire du HTML.

**Fidelite : haute (hifi)** pour la mise en page, la hierarchie et la copie ; les valeurs de
couleur/rayon donnees ci-dessous sont indicatives et doivent **ceder la priorite au theme reel de
l'app** (`_buildTheme` dans `lib/main.dart`) : utiliser `Theme.of(context).colorScheme` plutot que
des constantes. La maquette a ete dessinee sur la palette verte de l'app
(`_kPrimary = #1D9E75`, `_kDark = #155F47`, cf. `lib/web/web_app.dart`).

---

## 3. Ecrans

### 3.1 Parametres → Mes donnees (ecran de liste)

**But** : un seul endroit pour sortir ses donnees, les faire rentrer, ou tout effacer.

**Entree** : menu ⋮ → Parametres → nouvelle entree « Mes donnees »
(`lib/main.dart`, sous-menu Parametres qui contient deja Compte, Tokens API, Confidentialite).
`Icons.inventory_2_outlined` ou `Icons.save_alt`.

**Structure (haut → bas)**

1. **Carte « Derniere sauvegarde »** — fond teinte primaire clair (`#E7F5EF`), rayon 16, padding 16.
   - Sur-titre : `DERNIERE SAUVEGARDE`, 12px, w600, lettrage +0.07em, couleur `#155F47`.
   - Ligne principale : `12 aout 2026 · 08:14 — 1,4 Mo`, 15px w500.
   - Explication : `Enregistree dans Fichiers. Elle contient tout ton historique depuis le 3 janvier.`
     13px, `#3E5249`.
   - CTA plein largeur : **Sauvegarder maintenant** — `FilledButton`, pilule, hauteur ~48,
     fond primaire, texte blanc 15px w600.
   - Etat sans sauvegarde : masquer la carte, garder les lignes de liste.
2. **Lignes de liste** (`ListTile`, separateur 1px `#EDF2EF`, icone dans un carre 34x34 rayon 11) :
   - `↓` **Exporter une sauvegarde** — sous-titre « Fichier .json — tout, lisible, reimportable ».
   - `↑` **Restaurer une sauvegarde** — sous-titre « Depuis un fichier .json de Productivitwo ».
   - `⌫` **Supprimer mes donnees** — titre et icone en rouge (`#B33A2B`, fond `#FBEAE7`),
     sous-titre « Propose d'abord une sauvegarde ». Reutiliser le flux de suppression existant
     (`FileStore.wipe()` / suppression de compte) en y inserant la proposition d'export.
   - **Ne pas** ajouter d'entree « Exporter pour un tableur » (hors perimetre).
3. **Note de bas d'ecran**, 12px `#6B7F76` : « Parametres → Mes donnees. Un seul endroit : sortir, rentrer, effacer. »

### 3.2 Exporter une sauvegarde (sheet modale)

**But** : rassurer sur ce qui part, en un geste. Aucun choix de format, aucune selection de contenu.

- Titre 20px w600 : `Exporter une sauvegarde` · sous-titre 14px : `Tout est inclus. Rien a choisir.`
- **Inventaire** : une ligne par jeu de donnees, libelle a gauche (14px, `#3E5249`), compteur a
  droite en police monospace. Lignes reelles a brancher sur l'`AppState` charge :
  Domaines & intentions · Activites & routines · Sessions de temps · Coches de routines ·
  Projets, tâches, objectifs · Programmes horaires (en jours) · Blocs, inbox, reglages (`✓`).
- **Option unique** (`CheckboxListTile`, cochee par defaut) : « Inclure les documents et livrables »
  — « Briefs et programmes HTML — le fichier devient un .zip ».
- **CTA** : `Exporter — 1,4 Mo` (taille estimee calculee avant l'ecriture, pas apres).
- Mention 12px centree : « Le fichier ne contient aucun mot de passe. Il porte la date et le numero de schema. »
- Action : ecriture du fichier puis `share_plus` / `file_saver` (web : telechargement direct).

**Nom de fichier** : `productivitwo-YYYY-MM-DD.json` (ou `.zip` avec documents).

**Format du fichier**

```
{
  "schemaVersion": 7,
  "exportedAt": "2026-08-12T08:14:03Z",
  "buildTag": "<build_info.dart>",
  "uid": "<firebase uid>",
  "counts": { "domains": 7, "activities": 48, "sessions": 1240, ... },
  "appState": { ...AppState.toJson()... },
  "dailySchedules": [ { "date": "2026-08-12", ... }, ... ]
}
```

- `appState` = exactement `AppState.toJson()` (`lib/models/app_state.dart`) — ne pas modifier
  ce format existant, c'est aussi celui de la persistance locale.
- `dailySchedules` en section separee : en Firestore c'est un doc par jour
  (`users/{uid}/daily_schedules/{YYYY-MM-DD}`), donc absent de `AppState`.
- **Jamais dans le fichier** : `api_tokens`, secrets, consentements coach. La sauvegarde est un
  document utilisateur, pas un etat d'authentification.

### 3.3 Restaurer (sheet modale)

**But** : lire le fichier et le decrire **avant** de toucher a quoi que ce soit.

1. **Carte fichier** (fond `#F5F9F7`, bordure `#DCE5E0`, rayon 16) :
   nom en monospace · `7 domaines · 48 activites · 1 240 sessions · 12 projets` ·
   `Du 03/01/2026 au 12/08/2026` · pastille verte `Schema compatible`.
2. **Deux modes**, cartes radio (selection = bordure 2px primaire) :
   - **Fusionner — recommande** : « Ajoute ce qui manque, met a jour ce qui est plus ancien.
     Rien n'est supprime. »
   - **Remplacer tout** : « Repartir exactement de cette sauvegarde. Pour changer d'appareil. »
3. **Avertissement** (fond `#FFF6E6`, texte `#6B4A00`) : « Une sauvegarde de ton etat actuel est
   creee avant l'operation. Tu peux annuler pendant 7 jours. »
4. **CTA** : `Fusionner ce fichier` / `Remplacer par ce fichier` selon le mode.

### 3.4 Etats a couvrir

| Etat | Copie |
|---|---|
| Restauration terminee | « 312 elements ajoutes · 18 mis a jour · 0 supprime » + lien **Annuler la restauration** |
| Fichier illisible | « Ce n'est pas une sauvegarde Productivitwo, ou le fichier est incomplet. Rien n'a ete modifie. » |
| Schema trop recent | « Elle vient d'une version plus recente (schema 9, l'app lit jusqu'a 7). Mets a jour Productivitwo puis reessaie. » |
| Export volumineux | > ~10 Mo (documents inclus) : preparation en arriere-plan, notification quand le fichier est pret |
| Rien a exporter | Entree visible mais desactivee : « Tes donnees apparaitront ici des ta premiere journee suivie. » |

---

## 4. Comportement & etat

- `_loading` pendant la serialisation (CTA en `CircularProgressIndicator`, sheet non fermable).
- Restauration = machine a etats explicite : `idle → parsing → preview → applying → done|error`.
  Aucune ecriture avant `preview` valide.
- **Fusionner** s'appuie sur le merge par ID deja implemente dans `FirestoreSync` : un element
  absent du fichier ne supprime rien. Conflit sur un meme ID → garder la version la plus recente.
- **Remplacer** : creer d'abord un export automatique de l'etat courant (stocke localement,
  purge apres 7 jours) qui alimente « Annuler la restauration ».
- Les migrations one-shot (`_migrateLinkedActivities`, `_migrateVoitureActivity`,
  `_migrateGanttHidden`, flags `…MigratedOnce`) doivent etre **rejouees apres** une restauration.
- Idempotence : reimporter deux fois le meme fichier ne doit rien dupliquer.
- Soft-delete uniquement — jamais de `delete()` direct (convention du repo).

---

## 5. Tokens utilises dans la maquette

| Role | Valeur |
|---|---|
| Primaire | `#1D9E75` (`_kPrimary`) |
| Primaire fonce | `#155F47` |
| Primaire teinte (fonds) | `#E7F5EF` |
| Encre | `#12211B` · secondaire `#3E5249` · atenuee `#6B7F76` · desactivee `#9DB0A8` |
| Separateurs / fonds neutres | `#EDF2EF`, `#F5F9F7`, bordures `#DCE5E0` |
| Alerte | fond `#FFF6E6`, texte `#6B4A00` |
| Danger | texte `#B33A2B`, fond `#FBEAE7` |
| Rayons | pilule 999 · carte 26 · bloc 16 · icone 11 |
| Espacements | 6 / 10 / 14 / 16 / 20 (echelle 4) |
| Typo | police systeme de l'app · 20/600 titres de sheet · 15/500 titres de ligne · 13-14/400 corps · monospace pour compteurs et noms de fichiers |

Aucun asset a produire : les icones sont des `Icons.*` Material.

---

## 6. Specs de tâches (format `CLAUDE.md`, 4 lignes)

```
Lot 1 — Export sauvegarde
actions: [
  "Objectif : exporter tout l'etat de l'utilisateur dans un fichier .json date, partageable depuis Parametres → Mes donnees",
  "Fichiers : lib/models/app_state.dart, lib/storage.dart, lib/widgets/data_settings_sheet.dart (nouveau), lib/main.dart (entree menu Parametres), lib/web/web_home_screen.dart",
  "Criteres : en-tete {schemaVersion, exportedAt, buildTag, uid} + compteurs par collection · daily_schedules serialises en section dediee · option « inclure les documents » → .zip · aucun token/secret dans le fichier · > 10 Mo = preparation en arriere-plan puis notification · etat vide = entree desactivee avec message · meme fichier produit sur mobile et web",
  "Contraintes : reutiliser AppState.encode() sans en changer le format existant · pas de nouvelle dependance hors share_plus/file_saver · aucune ecriture Firestore · post-V1 (apres 17/08), ne pas toucher aux ecrans geles"
]

Lot 2 — Restauration
actions: [
  "Objectif : restaurer une sauvegarde .json en mode Fusionner ou Remplacer, avec apercu avant et annulation possible 7 jours",
  "Fichiers : lib/storage.dart, lib/firestore_sync.dart, lib/models/app_state.dart, lib/widgets/data_settings_sheet.dart",
  "Criteres : apercu (compteurs + plage de dates + compatibilite de schema) avant toute ecriture · Fusionner = merge par ID, ne supprime rien, garde la version la plus recente · Remplacer = sauvegarde automatique de l'etat courant puis remplacement · migrations …MigratedOnce rejouees apres import · schemaVersion superieur = refus explicite sans decodage partiel · fichier invalide = aucun changement · ecran de bilan (ajoutes / mis a jour / supprimes) + « Annuler la restauration »",
  "Contraintes : jamais de delete() direct — soft-delete uniquement · operation idempotente si relancee sur le meme fichier · pas de restauration partielle laissant un etat incoherent · reutiliser les helpers de merge existants de FirestoreSync"
]
```

---

## 7. Fichiers de reference du repo

| Sujet | Fichier |
|---|---|
| Serialisation complete de l'etat | `lib/models/app_state.dart` (`toJson`, `encode`, `decode`) |
| Persistance locale, migrations one-shot, `wipe()` | `lib/storage.dart` |
| Merge par ID, soft-delete, ecritures Firestore | `lib/firestore_sync.dart` |
| Menu et sous-menu Parametres | `lib/main.dart` (~l. 5244 : Confidentialite, Supprimer mon compte) |
| Palette | `lib/web/web_app.dart`, `lib/utils/domain_colors.dart` |
| Contraintes produit et conventions | `CLAUDE.md`, `docs/VISION.md` |

## 8. Fichiers de ce bundle

- `README.md` — ce document.
- `Export-import cadrage.dc.html` — maquette de reference (ouvrir dans un navigateur).
- `support.js` — runtime necessaire a l'ouverture de la maquette.
- `screens/` — captures des ecrans, 2x :
  - `01-parametres-mes-donnees.png` → section 3.1
  - `02-exporter-une-sauvegarde.png` → section 3.2
  - `03-restaurer.png` → section 3.3
  - `04-etats.png` → section 3.4
