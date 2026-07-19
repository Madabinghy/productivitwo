# Spec — Espace Coach V1.1 (fonctionnalité prioritaire)

> Source : Business Plan Productivitwo v1.0 (juillet 2026), section 10.1.
> Objectif business : permettre la Phase 1 « coaching augmenté » —
> 5 coachés actifs au 01/10/2026. Cette spec est le périmètre MINIMAL :
> résister à toute extension avant d'avoir 2-3 coachés réels dessus.

## Le concept en une phrase

Le coach voit, entre les séances, si les engagements pris en séance sont
réellement tenus — à partir des données que l'app collecte déjà — et peut
intervenir au bon moment.

## Ce qui existe déjà et sur quoi on s'appuie (ne PAS reconstruire)

- Objectifs avec engagements hebdomadaires chiffrés (temps d'activités,
  routines) et statut `onTrack` calculé par semaine.
- Temps réel mesuré par activité et par domaine de vie.
- Rapports hebdomadaires générés (`generate_weekly_report`).
- Canal de messages de l'assistant ORION (`push_assistant_message`).
- Blocs de journée planifiés/réalisés.

L'Espace Coach est essentiellement une **couche de partage + une vue
agrégée** au-dessus de l'existant.

## User stories par priorité (MoSCoW)

### MUST — sans ça, pas de Phase 1

**US-1 · Invitation et lien coach-coaché**
En tant que coach, j'invite un coaché par e-mail/lien (ou l'inverse).
Critères d'acceptation :
- Le lien n'est actif qu'après acceptation explicite du coaché.
- À l'acceptation, le coaché choisit ce qu'il partage :
  - quels domaines de vie sont visibles (par défaut : aucun — opt-in) ;
  - la granularité : « statuts seulement » (engagements tenus / en retard)
    ou « détail » (temps par activité, blocs de journée) ;
- Le coaché peut modifier ou révoquer le partage à tout moment, seul,
  en deux taps maximum. La révocation est immédiate.
- Un utilisateur peut avoir au plus un coach (V1.1) ; un coach peut avoir
  N coachés.

**US-2 · Cockpit multi-coachés**
En tant que coach, je vois une liste de mes coachés avec, pour chacun :
- les engagements de la semaine en cours et leur statut (tenu / en retard),
- la tendance sur les 4 dernières semaines (simple : % d'engagements tenus),
- la date de dernière activité dans l'app.
Critères : lecture seule ; ne montre que ce que le coaché a partagé ;
chargement < 2 s pour 20 coachés.

**US-3 · Rapport de pré-séance**
En tant que coach, je reçois (ou consulte) une synthèse hebdo par coaché :
temps par domaine partagé, engagements tenus/manqués, points de décrochage.
Critères : réutilise le rapport hebdo existant filtré par le périmètre de
partage ; disponible depuis le cockpit ; envoi optionnel par e-mail.

### SHOULD — forte valeur, juste après les MUST

**US-4 · Message du coach via ORION**
En tant que coach, j'envoie un message contextualisé qui apparaît dans le
fil ORION du coaché (encouragement, recadrage, proposition de séance).
Critères : le message est clairement attribué au coach (pas à l'IA) ;
le coaché peut couper ce canal sans révoquer tout le partage.

**US-5 · Alerte décrochage**
En tant que coach, je suis notifié quand un coaché est « en retard » sur
ses engagements 2 semaines consécutives, ou n'a pas ouvert l'app depuis
N jours (N configurable, défaut 5).
Critères : max 1 alerte par coaché par semaine (pas de spam) ; l'alerte
pointe vers la fiche du coaché dans le cockpit.

### COULD — seulement si le reste est stable

- Note privée du coach par coaché (invisible du coaché).
- Marquage d'un engagement comme « défini en séance » (traçabilité du
  contrat coach-coaché).

### WON'T (V1.1) — explicitement hors périmètre

- Multi-coachs par coaché, marque blanche, facturation intégrée,
  visio, chat temps réel, cockpit pour d'autres coachs que le porteur
  (ça, c'est la licence B2B, an 3).

## Contraintes transverses

**RGPD / confidentialité (bloquant, pas cosmétique)**
- Base légale : consentement explicite du coaché, recueilli dans l'app,
  horodaté, révocable. Journaliser consentements et révocations.
- Minimisation : le coach ne voit jamais rien hors du périmètre partagé ;
  les domaines non partagés n'apparaissent nulle part (même pas agrégés).
- Les données de temps/habitudes sont intimes : pas d'export côté coach
  en V1.1 ; suppression du lien = le coach perd tout accès à l'historique.

**Produit**
- Zéro double saisie pour le coaché : tout vient de l'usage normal.
- Interface en français.
- Le mode hors-ligne ne doit pas casser la collecte (les données saisies
  hors connexion doivent remonter au cockpit à la synchro).

## Ordre de développement suggéré

1. Modèle de données du lien coach-coaché + consentement/périmètre (US-1).
2. Cockpit lecture seule (US-2) — testable dès 1 coaché réel.
3. Rapport de pré-séance (US-3).
4. Message via ORION (US-4), puis alertes (US-5).

Jalon de validation : 2-3 coachés réels utilisent le partage pendant
2 semaines et le coach prépare ses séances uniquement avec le rapport.
