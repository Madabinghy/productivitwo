# Productivitwo — Vision business (résumé du business plan v1.0, juillet 2026)

Document de contexte pour le développement. Le business plan complet
(Word, 17 pages) est la référence ; ce fichier en extrait ce qui oriente
les décisions produit/dev.

## Le pari

Le problème n°1 des apps de productivité n'est pas le manque de features,
c'est l'abandon : ~72 % des abonnements annuels B2C sont résiliés avant un
an, rétention à 12 mois ~27 % (RevenueCat 2025-2026). Le levier anti-churn
prouvé est la redevabilité humaine (Noom : 1 Md$ ARR, Second Nature,
CoachHub). Productivitwo applique ce modèle hybride à la productivité :
l'app est l'outil quotidien du coaché, le coach est la raison de s'y tenir.

## Le trou de marché

- Les plateformes coach-client (CoachAccountable, Quenza, Paperbell,
  Simply.Coach, Nudge Coach, UpCoach) digitalisent la relation (devoirs,
  métriques, messages) mais n'offrent AUCUN outil de productivité
  quotidienne au client.
- Les apps de productivité (Sunsama 17-22 $, Motion 13-19 $, Akiflow 19-34 $,
  Todoist 5-7 $, TickTick ~3 $) n'ont aucune redevabilité humaine, et le
  segment premium n'est pas traduit en français.
- Aucune app francophone identifiée au croisement des deux. C'est le
  positionnement de Productivitwo.

## Le modèle économique (3 phases autofinancées)

| Phase | Quand | Offre | Prix cible |
|---|---|---|---|
| 1. Coaching augmenté | maintenant → oct. 2026 | 3 mois, 6 séances + app + suivi | 390-450 € le parcours |
| 2. Cohortes | 6-18 mois | programme de groupe 8-12 semaines | 200-250 €/participant |
| 3a. Abonnement B2C | 12-36 mois | app seule, essai 14 j (pas de freemium) | 9,90 €/mois ou 79 €/an |
| 3b. B2C accompagné | 12-36 mois | app + check-in coach asynchrone mensuel | 49-69 €/mois |
| 3c. Licence B2B coachs | an 3 | cockpit coach pour d'autres coachs | 29-39 €/mois (≤10 coachés) |

Prévisionnel 36 mois (MRR équivalent) : prudent ≈ 1 650 €,
médian ≈ 4 240 €, ambitieux ≈ 12 110 €.
Hypothèses : churn 8-10 %/mois, ARPU app 8-15 €, essai→payant 25-40 %
(vs ~2 % en freemium — d'où le choix essai payant, pas de plan gratuit).

## Implications directes pour le développement

1. La rétention se joue sur la boucle coach-coaché, pas sur l'ajout de
   features. Prioriser tout ce qui renforce cette boucle.
2. L'historique de données (temps, habitudes, progression) est le coût de
   sortie qui soutient l'abonnement autonome : soigner la durabilité et la
   restitution des données longitudinales (tendances, bilans).
3. Le futur paywall = essai 14 jours puis abonnement : l'onboarding des
   14 premiers jours devra faire vivre la boucle complète
   (planifier → exécuter → mesurer → bilan hebdo).
4. RGPD par conception sur tout le partage coach-coaché : consentement
   granulaire et révocable — c'est aussi un argument de vente.
5. Français d'abord ; marché de lancement : Martinique/Antilles, puis
   francophonie.

## Jalons

- **17/08/2026** : sortie V1 (périmètre gelé).
- **Sept.-oct. 2026** : Espace Coach V1.1 (`docs/specs/espace-coach-v1.1.md`) ;
  5 coachés actifs au 01/10.
- **T1 2027** : parcours de cohorte dans l'app ; 1ère cohorte pilote.
- **T2-T3 2027** : onboarding self-service, Stripe, essai 14 j, bêta publique.
- **2028** : multi-coachs (licence B2B).
