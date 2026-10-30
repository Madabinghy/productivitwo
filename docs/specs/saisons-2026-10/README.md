# Saisons (lot 3 de la gamification moyen terme, 2026-10-30)

Maquette validée : canvas « Saisons » (3 écrans mobiles). But : un horizon de six semaines qui se renouvelle,
contre les deux pièges du long terme (le plateau quand tout est acquis, le découragement quand une longue
série casse) ; cadre naturel des cohortes de 8-12 semaines (phase 2).

## Règles

- Une saison s'ouvre à la main (onglet Objectifs), dure jusqu'au dimanche de la 6ᵉ semaine pleine
  (`seasonEndFor`), numérotée.
- **Trois chasses au plus, figées** : choisies parmi les propositions (`seasonPicks` : prochain palier de chaque
  badge à paliers qui peut tomber en six semaines, groupes De tes objectifs · À portée · Pour repartir). Elles
  REMPLACENT les chasses en cours (`badgeHunts`, date visée = fin de saison) : enjeux du jour et « Badges en jeu »
  les montrent sans rien de plus.
- **Lâcher** une chasse est possible (comptée non réussie), la remplacer non.
- Une chasse est **attrapée** quand son palier tombe pendant la saison (date de palier dans la fenêtre) ; en bonne
  voie si l'avancée ≥ 85 % du temps écoulé, sinon à pousser.
- **Bilan** à la fin : s'ouvre de lui-même une fois (au premier affichage de l'onglet Objectifs après la fin),
  reste accessible depuis la carte tant qu'aucune saison n'est rouverte : chasses, semaines tenues, braises
  forgées / dépensées, paliers obtenus, « Préparer la saison suivante ».
- **Badge « Saisons »** (Objectifs, symbole `season`, paliers 1 / 4 / 8) : saisons closes avec au moins deux
  chasses attrapées.

## Données

`data/meta.seasons` = `[{n, start, end, hunts[{badgeId, tier, name}], dropped[], bilanSeen}]` (40 gardées).
Aucun résultat stocké : tout se relit sur les dates des paliers du deck. Logique pure `lib/utils/seasons.dart`,
écrans `lib/widgets/season_view.dart` (`SeasonCard`, `showSeasonOpenSheet` : TOUS les candidats, quatre par groupe puis « Afficher les n autres », bouton de palier « 7 j ▾ » pour viser plus haut tant que ça tient en six semaines, `SeasonPick.tiers` ; `showSeasonBilan`), `AppLogic.openSeason`
/ `dropSeasonHunt` / `markSeasonBilanSeen`. Web : badge seulement (pas d'ouverture de saison sur le web).
