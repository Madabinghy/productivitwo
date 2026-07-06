import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/pro_manager.dart';

class _Entry {
  final String version;
  final String date;
  final List<(IconData, String)> changes;
  const _Entry(this.version, this.date, this.changes);
}

const _changelog = [
  _Entry('6.42', '6 juillet 2026', [
    (Icons.today_outlined, 'Nouvel onglet « Aujourd\'hui » : ton programme horaire du jour, avec une bascule « Demain » pour préparer la journée suivante la veille (ajoute des blocs à la main, ou demande à Claude/ORION de planifier)'),
    (Icons.play_circle_outline, 'L\'onglet « Maintenant » (chrono, focus, programme en cours) prend la place de l\'onglet Manoir — retour à une vraie app de productivité'),
    (Icons.videogame_asset_off_outlined, 'Couche jeu mise en veille : Manoir d\'Ombrelune, compteur de nuisibles et mise du jour sont retirés de l\'interface (tes données sont conservées — rien n\'est perdu)'),
  ]),
  _Entry('6.41', '19 juin 2026', [
    (Icons.bug_report, 'Combat (web + mobile) : on ne tape plus un jour précis du calendrier — les libellés de jours sont retirés et le canon vise la PREMIÈRE araignée (le jour manqué le plus ancien). Tirer la tue et fait avancer la vague'),
    (Icons.cleaning_services, 'Rattrapage : valider une routine rattrape le jour manqué le plus ancien, et tu peux enchaîner pour nettoyer toute la ligne par l\'effort (même mécanique pour les scorpions des activités). Le bandeau de pastilles reste comme repère de régularité'),
    (Icons.local_fire_department, 'Récompense de régularité : une série de N élimine automatiquement les N plus vieilles araignées — plus ta série est longue, moins le retard pèse (reflété aussi dans le compteur de nuisibles)'),
  ]),
  _Entry('6.40', '19 juin 2026', [
    (Icons.pest_control, 'Compteur global de nuisibles (🕷️ routines · 🦂 activités · 🐍 tâches en retard, tous domaines) : sur la carte web « Le Monde » sous la minimap, ET en tête du tableau de bord mobile — pour voir où tu en es d\'un coup d\'œil'),
    (Icons.insights, 'Au clic : un panneau de stats avec le total par type + le comparatif des « jours tenus » de cette semaine vs les 7 jours précédents (ex. routines +5)'),
  ]),
  _Entry('6.39', '19 juin 2026', [
    (Icons.playlist_add_check, 'Une activité-temps peut avoir ses PROPRES actions (sans tâche/projet) : crée-les depuis son dashboard (web « Le Monde » + fiche activité mobile), coche-les, lance un chrono ciblé dessus, supprime-les'),
    (Icons.visibility, 'Ces actions propres apparaissent aussi pendant un chrono (onglet Maintenant) et dans l\'onglet Actions du combat (vise 🎯 + « Faire feu » pour les valider)'),
    (Icons.timer_outlined, 'Dashboards : « Lancer le chrono » (compte) ET « Lancer le minuteur » (décompte, s\'arrête tout seul à zéro) sont désormais deux boutons distincts — fini le « minuteur » qui lançait en fait un chrono'),
    (Icons.hourglass_bottom, 'Sélecteur de durée du minuteur par défaut (0/5/10/15/25 min) ajouté au dashboard des activités, comme celui des routines'),
  ]),
  _Entry('6.38', '19 juin 2026', [
    (Icons.link, 'Lier une action de projet à une activité-temps : depuis la fiche d\'une tâche, « Lier une activité » rattache une action à un scorpion — le chrono lancé depuis l\'action est ciblé (la session pointe sur l\'action) et l\'activité affiche ses actions liées'),
    (Icons.checklist, 'Checklist des routines éditable depuis le dashboard (web « Le Monde » + fiche routine mobile) : ajoute, renomme, coche et supprime tes étapes — synchronisées entre le téléphone et le web'),
    (Icons.timer, '« Le Monde » : un chrono en cours reste visible (pastille ⏱️ avec le nom de l\'activité, le temps qui défile et un bouton Arrêter) même quand tu explores la carte — plus seulement dans l\'arène'),
    (Icons.tune, 'Dashboard d\'une routine (web) enrichi : lie une activité-temps, lance son chrono directement depuis le dashboard, et choisis un minuteur par défaut (5/10/15/25 min) — comme sur la fiche routine mobile'),
  ]),
  _Entry('6.37', '19 juin 2026', [
    (Icons.timelapse, 'Combattre (mobile) : minuteur d\'activité-temps → un tir toutes les 5 min anime la baisse de PV ; une activité lancée depuis le web est reprise sur mobile (décompte synchronisé)'),
    (Icons.replay, 'Combattre (mobile) : les routines complétées hors de l\'app (widget, web) sont rattrapées à l\'ouverture — les canons tirent une à une les flammes en attente (un seul tir si trop nombreuses)'),
    (Icons.rocket_launch_outlined, 'Combattre (mobile) — onglet Actions : vise une action (🎯) et « Faire feu 🚀 » la valide ; coche verte sur les actions faites ; descriptions sur plusieurs lignes'),
    (Icons.format_align_left, 'Combattre (mobile) : le nom d\'une routine est désormais SOUS sa tourelle (plus de confusion avec la routine suivante) ; durée du minuteur prise sur la routine, sinon demandée'),
  ]),
  _Entry('6.36', '19 juin 2026', [
    (Icons.timer_outlined, 'Combattre (mobile) : en mode minuteur, « Faire feu » ne quitte plus le domaine — le viseur de la ligne devient un décompte, et à zéro la tourelle fait feu (routine validée / temps loggé). Un seul minuteur à la fois, mémorisé même si tu fermes l\'écran'),
    (Icons.tune, 'Combattre (mobile) : le type de lancement de chaque routine (minuteur / chrono / coche) est désormais mémorisé'),
    (Icons.format_align_left, 'Combattre (mobile) : le nom d\'une routine est clairement rattaché à sa propre tourelle (espacement + repère couleur) — fini la confusion avec la tourelle du dessus'),
  ]),
  _Entry('6.35', '19 juin 2026', [
    (Icons.edit_note, '« Le Monde » web : gère les actions d\'une tâche directement depuis le dashboard du serpent (ajouter, renommer, cocher, supprimer)'),
    (Icons.timer_outlined, 'Dashboard d\'un serpent : lance le chrono d\'une activité du domaine, lié à la tâche — le téléphone voit l\'activité en cours en parallèle'),
    (Icons.touch_app_outlined, 'Un clic prend la priorité : l\'avatar change de cap aussitôt au lieu de finir son trajet ; pendant une cinématique, un clic te rend la main (un clone fantôme finit la routine) et l\'avatar reprend l\'enchaînement après 10 s d\'inactivité'),
    (Icons.center_focus_strong, 'En entrant dans un domaine, la carte le centre (repère stable) ; les petites araignées se déplacent beaucoup plus lentement ; le canon vise d\'autant plus bas qu\'il y a de nuisibles (haut = prêt, bas = débordé)'),
  ]),
  _Entry('6.34', '19 juin 2026', [
    (Icons.menu_book_outlined, '« Le Monde » web : un parchemin 📜 par domaine (au-dessus de la 1ʳᵉ tourelle) ouvre un grand tableau de bord projets — liste avec avancement à gauche, document de pilotage interactif à droite (coche tes tâches depuis le jeu, bindé au Gantt ; cocher une tâche fait disparaître son serpent)'),
    (Icons.check_circle_outline, 'Terminer un projet depuis l\'arène ou la fiche projet ; supprimer un projet depuis l\'arène (avec confirmation) — un projet terminé/supprimé sort de la liste et retire ses nuisibles'),
    (Icons.snooze, 'Désactiver une action jusqu\'à une date (arène + fiche activité mobile) : plus de scorpion tant que la date n\'est pas atteinte (ex : « plus d\'intervention cette semaine »)'),
    (Icons.pan_tool_outlined, 'Un clic reprend la main pendant une cinématique (un clone fantôme finit le tir tout seul) ; tant qu\'un tableau de bord est ouvert, les cinématiques auto se mettent en attente (flammes provisionnées, déchargées à la fermeture)'),
    (Icons.bug_report_outlined, 'Corrections : le scroll dans un tableau de bord ne déplace plus la carte ; valider une routine depuis l\'arène s\'incrémente bien sur le mobile'),
  ]),
  _Entry('6.33', '19 juin 2026', [
    (Icons.videocam_outlined, '« Le Monde » web : la caméra suit l\'avatar pendant ses déplacements automatiques et les cinématiques, et cadre la trajectoire du tir'),
    (Icons.dashboard_customize_outlined, 'Monter sur une rampe ou cliquer un nuisible ouvre un mini-dashboard ciblé DANS le jardin (stats + appel à l\'action), sans ouvrir de fiche par-dessus : routine → « Valider », activité → minuteur (chrono en cours + « Arrêter » si une session tourne), tâche/serpent → ses actions cochables'),
    (Icons.local_fire_department_outlined, 'Règle des canons : un canon ne tire que s\'il a des flammes en réserve (routines validées / temps loggé). Sans flamme, il reste muet'),
    (Icons.palette_outlined, 'Une case du calendrier n\'est noire que si elle porte un nuisible ; les jours tenus et les activités déjà atteintes prennent la couleur du domaine'),
    (Icons.save_outlined, 'Brouillard de guerre et position de l\'avatar mémorisés d\'une session à l\'autre'),
  ]),
  _Entry('6.32', '18 juin 2026', [
    (Icons.view_column_outlined, '« Le Monde » web en 2 colonnes : les domaines s\'organisent autour d\'une cour centrale (gazon), un domaine sur deux passant en miroir à gauche — carte plus compacte, moins de trajet. En miroir, les nuisibles arrivent de la gauche et la tourelle, à l\'intérieur, vise vers la gauche'),
    (Icons.water_drop_outlined, 'PV des nuisibles lisibles à la couleur : une case pleine est noire, et plus tu blesses le nuisible, plus la couleur du domaine remonte par le bas'),
    (Icons.bolt_outlined, 'Valider une routine (page web ouverte) joue toute la cinématique sur la grande carte : l\'avatar marche jusqu\'à la rampe, la rampe tourne, le canon se lève, tire vers le jour, et le nuisible perd un PV'),
    (Icons.save_outlined, 'Le brouillard de guerre déjà exploré et la position de ton avatar sont mémorisés d\'une session à l\'autre'),
    (Icons.fort_outlined, 'Les cases du calendrier sont infranchissables (tu passes par le centre, plus derrière les routines) et plus rien ne se pose au contact des rampes de tir'),
  ]),
  _Entry('6.31', '18 juin 2026', [
    (Icons.rocket_launch_outlined, '« Le Monde » web : le canon garde ses pieds droits (comme en combat de boss) et seule sa tête se relève quand tu actives la rampe. Petite pause après la rotation de la rampe avant que l\'avatar y monte'),
  ]),
  _Entry('6.30', '18 juin 2026', [
    (Icons.timer_outlined, 'Le bouton ▶ « chrono » du dashboard d\'un domaine démarre désormais vraiment la session côté serveur — elle est synchronisée sur le téléphone (Live Activity iOS si l\'app a été ouverte une fois)'),
    (Icons.straighten, '« Le Monde » web : chaque domaine a une hauteur minimale (mini-app dashboard plus lisible). Les rangées vides du calendrier sont remplies de pierre, avec un coffre à butin dans le jardin'),
  ]),
  _Entry('6.29', '18 juin 2026', [
    (Icons.rocket_launch_outlined, '« Le Monde » web : le canon est baissé au repos et se redresse quand tu actives sa rampe. Séquence en 3 temps — l\'avatar arrive à gauche, la rampe tourne et le canon se lève, puis l\'avatar monte sur la rampe et la cinématique de tir se lance (volée vers le jour)'),
  ]),
  _Entry('6.28', '18 juin 2026', [
    (Icons.dashboard_customize_outlined, '« Le Monde » web : le jardin devient une mini-app interactive — combat scorpion/araignée et dashboard des routines du domaine s\'affichent DANS la map (plus en colonne à droite) ; cliquer une case referme et réaffiche le jardin'),
    (Icons.rocket_launch_outlined, 'Clique sur une rampe de tir ☢️ : l\'avatar s\'y rend, la rampe tourne, le canon se lève et tire (s\'il a des flammes), puis le jardin ouvre le dashboard de la routine'),
    (Icons.inventory_2_outlined, 'Compteur de shurikens 🗡️ affiché par domaine ; aucun nuisible ne se pose sur une case interactive'),
  ]),
  _Entry('6.27', '18 juin 2026', [
    (Icons.hub_outlined, '« Le Monde » web : les petites araignées d\'écart restent désormais dans le village + jardin de LEUR domaine et ne se mélangent plus. Réduire l\'écart d\'un domaine ne nettoie que SES araignées'),
    (Icons.shield_moon_outlined, 'Gardiens de passage : un scorpion 🦂 (activité en retard) et un serpent 🐍 (tâche en retard) bloquent les raccourcis entre deux domaines — tu peux toujours contourner par le pont, ou les affronter'),
    (Icons.visibility_outlined, 'Le décor ne se pose plus sous les noms de routines (lisibilité)'),
  ]),
  _Entry('6.26', '18 juin 2026', [
    (Icons.bug_report_outlined, '« Le Monde » web : les petites araignées d\'écart se déplacent plus lentement (plus faciles à suivre)'),
    (Icons.warning_amber, 'Une rampe de lancement ☢️ marque la case de tir à gauche de chaque tourelle (là où l\'avatar se poste pour tirer)'),
  ]),
  _Entry('6.25', '16 juin 2026', [
    (Icons.bug_report_outlined, '« Le Monde » web : des petites araignées apparaissent dans le monde pour chaque routine en retard sur la semaine dernière — autant d\'araignées que de complétions manquantes vs le même jour S-7. Elles se baladent librement (bloquées par les murs)'),
    (Icons.gps_fixed, 'Quand tu réduis l\'écart entre deux passages, tu arrives avec des shurikens stockés : ton avatar abat automatiquement les araignées qui passent à portée, jusqu\'à refléter l\'écart réellement rattrapé'),
  ]),
  _Entry('6.24', '16 juin 2026', [
    (Icons.local_fire_department_outlined, '« Le Monde » web : les tourelles ne tirent plus en boucle. Elles ne lancent que les boules de feu réellement provisionnées par tes complétions (faites hors-web ou en direct), chacune une seule fois — fini le feu d\'artifice permanent qui ne reflétait rien'),
  ]),
  _Entry('6.23', '16 juin 2026', [
    (Icons.speed_outlined, '« Le Monde » web : navigation plus fluide — la carte ne reconstruit plus ses cases à chaque pixel de scroll et la mini-carte ne se redessine qu\'à l\'essentiel. Le glissé et le défilement restent nets même sur un grand monde'),
  ]),
  _Entry('6.22', '16 juin 2026', [
    (Icons.park_outlined, '« Le Monde » web : décor ambiant — arbres, rochers et buissons sur le terrain extérieur, maisons dans les villages, torches le long des remparts. La carte respire enfin (décor purement visuel, généré de façon stable)'),
  ]),
  _Entry('6.21', '16 juin 2026', [
    (Icons.castle_outlined, '« Le Monde » web : chaque domaine a désormais une structure de murs en pierre, déterministe selon sa taille (piliers, diviseur, bastions, chevrons) — une silhouette de forteresse différente par domaine, avec un accent de la couleur du domaine'),
    (Icons.pest_control_outlined, 'Les serpents et les coffres ne se posent plus jamais sur un mur'),
    (Icons.block_outlined, 'Un serpent posé sur un passage entre deux domaines le bloque (impossible de l\'enjamber) : l\'avatar doit faire le tour par le pont, ou affronter le serpent pour rouvrir la porte'),
  ]),
  _Entry('6.20', '16 juin 2026', [
    (Icons.local_fire_department_outlined, '« Le Monde » web : en exploration automatique, le tir est ralenti et l\'avatar attend que le boulet ait atteint la routine avant d\'enchaîner — la cinématique reste lisible'),
    (Icons.mouse_outlined, 'Navigation desktop : tu peux déplacer la carte du Monde à la molette ou à deux doigts, en plus du glissé au doigt'),
  ]),
  _Entry('6.19', '16 juin 2026', [
    (Icons.fact_check_outlined, 'Revue de la semaine — « À valider » accepte deux nouveaux types de propositions : ajouter une phase à un projet, et ajouter une action (sous-étape) à une tâche existante'),
    (Icons.alternate_email, 'L\'assistant peut désormais déposer des propositions à valider depuis une source externe (ex : tes mails) sans rien modifier sans ton accord'),
  ]),
  _Entry('6.18', '16 juin 2026', [
    (Icons.explore_outlined, '« Le Monde » web : exploration semi-automatique — les routines validées sur mobile pendant que le web était fermé chargent des 🔥 sur les tours ; l\'avatar monte domaine par domaine, se place à gauche de chaque routine et décharge les tirs en révélant la carte'),
    (Icons.touch_app_outlined, 'Tu reprends la main d\'un clic ; après 1 min d\'inactivité l\'avatar reprend son travail ; te poser à gauche d\'une tour en flammes relance l\'exploration'),
    (Icons.check_circle_outline, 'Chaque validation de routine est animée une et une seule fois (mémorisée), et déclenche bien le tir sur le web en direct (corrigé pour les routines, pas que les activités-temps)'),
    (Icons.local_fire_department_outlined, 'Mobile « Faire feu » : la tour se transforme en canon, vise, tire en courbe, 💥 2 s, puis redevient tour ; viseur posé par défaut sur la 1ʳᵉ routine ; sélecteur minuteur/chrono en bout de ligne (le feu lance le minuteur ou le chrono)'),
  ]),
  _Entry('6.17', '16 juin 2026', [
    (Icons.local_fire_department_outlined, 'Carte de combat : la tourelle du calendrier tire une boule de feu sur le nuisible du jour avant chaque coup (mobile + web)'),
    (Icons.public, '« Le Monde » sur le web : une seule grande carte explorable au doigt (drag-pan) — village, jardin de serpents et calendrier de chaque domaine empilés'),
    (Icons.bug_report_outlined, 'Araignée-boss d\'invasion : à 10 jours manqués dans la semaine, une araignée s\'installe ; nettoie ta semaine puis affronte-la pour la déloger (combat aux shurikens)'),
    (Icons.savings_outlined, 'Bataille à l\'araignée : ton stock de shurikens du jour = ton backlog ; consommés à la victoire seulement (défaite = tu peux refarmer et réessayer)'),
  ]),
  _Entry('6.16', '16 juin 2026', [
    (Icons.gps_fixed, 'Combattre : un viseur 🎯 devant chaque routine/activité — tape-le pour choisir la cible de « Faire feu »'),
    (Icons.checklist_outlined, 'Combattre : nouvel onglet « Actions » — tes projets/tâches du domaine (lance-missiles + calendrier des actions validées, fusil devant chaque action)'),
  ]),
  _Entry('6.15', '15 juin 2026', [
    (Icons.gps_fixed, 'Détail d\'un domaine (Combattre) : bouton « Faire feu » — la tour se transforme en canon et attaque le nuisible du jour (boulet en arc, -1, 💥 si l\'araignée tombe)'),
    (Icons.local_fire_department_outlined, 'Cinématique de tir : canon DCA, boulet de feu orienté en arc partant du bout du canon'),
  ]),
  _Entry('6.14', '15 juin 2026', [
    (Icons.gps_fixed, 'Nouvel onglet « Combattre » (remplace ORION dans la barre du bas) : tes domaines en jardin/château, tours de défense et heatmap 12 semaines'),
    (Icons.smart_toy_outlined, 'Orion Stratège déplacé dans la barre du haut ; « À valider » retiré (déjà dans Revue de la semaine)'),
    (Icons.gps_fixed, 'Tours de défense : barre de vie (bleu/jaune/rouge) + chargeur de munitions, canon DCA pour les routines hebdo/mensuelles ; tap sur une tour → lance la routine / l\'activité'),
    (Icons.local_fire_department_outlined, 'Carte de combat enrichie : tourelle qui fait feu, munitions, et la semaine glissante de la routine/activité'),
  ]),
  _Entry('6.13', '14 juin 2026', [
    (Icons.calendar_view_week, '« Le Monde » sur mobile repensé en CALENDRIER par domaine : une ligne par routine (et par activité-temps), 7 derniers jours en colonnes'),
    (Icons.bug_report_outlined, 'Chaque jour manqué = une araignée (PV = ce qu\'il reste à faire) ; jour fait = feuille 🍃 ou flamme 🔥 (2 jours d\'affilée) ; le château se remplit de toiles ou de feuilles selon ton historique'),
    (Icons.touch_app_outlined, 'Clic sur un nuisible → sa carte de combat (fais le vrai travail pour l\'éliminer). Carte pannable/zoomable sur mobile'),
  ]),
  _Entry('6.12', '13 juin 2026', [
    (Icons.public, '« Le Monde » disponible sur mobile (bouton 🌍 dans Mon Or) : farm, territoire et reconquête de grottes'),
    (Icons.castle_outlined, 'Reconquête d\'une grotte de domaine : assaut tower-defense inversé (l\'araignée défend, ton scorpion attaque). Ton deck d\'assaut = tes captures de CE domaine'),
    (Icons.bug_report_outlined, 'La menace d\'invasion reflète tes vrais retards : routines sans série, temps en retard sur objectif, tâches en retard'),
    (Icons.restart_alt, 'Deck d\'invasion repartable de zéro proprement, sans toucher à ton historique réel'),
  ]),
  _Entry('6.11', '11 juin 2026', [
    (Icons.shield_rounded, 'Onglet Arène dans l\'app web : combats, programme du jour et exploration (overworld, donjon, chasse) en 3 colonnes'),
    (Icons.bar_chart_rounded, 'Barre de stats en haut : or, niveau, barre de progression XP et arsenal disponible'),
  ]),
  _Entry('6.10', '11 juin 2026', [
    (Icons.sports_martial_arts_rounded, 'Carte de combat redesignée : style épuré, icônes Flutter pour les pouvoirs (gel, bouclier, boost), liste de cœurs toujours visible'),
    (Icons.event_available_outlined, '« Programmer pour plus tard » masqué si un défi ou un bloc est déjà posé dans ton programme du jour pour cet item'),
    (Icons.star_outline_rounded, 'Étoile FAB sur une routine : durées longues (45, 60, 90 min) disponibles — plus bloqué à 30 min max'),
  ]),
  _Entry('6.09', '11 juin 2026', [
    (Icons.ac_unit, 'Pouvoirs depuis la carte de combat : gèle une routine (1/2/3 jours), bouclier anti-deadline, boost ×2 — tout achetable en un tap. Plus tu as de pouvoirs actifs, plus c\'est cher'),
    (Icons.radio_button_checked, 'Combats en cours redesignés : couleur du domaine, barre de PV, avatar ⚔️ si le combat tourne en direct'),
    (Icons.highlight_off, 'Contour rouge sur les nuisibles déjà engagés dans la carte de chasse'),
    (Icons.flag_outlined, 'Retour vers l\'overworld depuis le nœud de départ du donjon'),
    (Icons.block, 'Tâche en retard = bloquante à la sortie du donjon — résous-la d\'abord'),
    (Icons.star_outline_rounded, 'Durée de planification des routines corrigée (5/10/15 min) ; supprimer un bloc remet l\'étoile à zéro'),
    (Icons.description_outlined, 'Lecture des documents d\'une tâche depuis le mobile (bouton 📄 dans la fiche tâche → WebView)'),
  ]),
  _Entry('6.08', '11 juin 2026', [
    (Icons.sync_alt, 'Programme du jour synchronisé avec tes routines/tâches : cocher un bloc valide la routine (ou ouvre la tâche pour cocher ses actions), et faire la routine/tâche ailleurs coche le bloc tout seul. Taper une ligne ouvre désormais SA fiche (tâche/routine/activité)'),
    (Icons.star_outline_rounded, 'Étoile sur une routine (lanceur) → « planifier aujourd\'hui » (heure + durée) ; elle file dans ton programme. Et tu peux lier une activité à un bloc ajouté à la main (bouton ▶ + auto-coché au temps loggué)'),
    (Icons.vpn_key_rounded, 'Donjon : une routine déjà faite aujourd\'hui devient une CLÉ — bouton « Utiliser » pour franchir un passage sans rien refaire (1 routine = 1 clé, consommée). Fini d\'être bloqué quand on a été productif'),
    (Icons.checklist_rtl_outlined, 'Combat contre une tâche 🐍 : la liste de ses actions s\'ouvre pour les cocher directement (chaque action = −1 ❤️) — tu vois enfin quoi tu valides'),
    (Icons.diamond_outlined, 'Tu peux maintenant VALIDER un jalon de projet depuis le mobile (un tap sur le losange) — plus de blocage pour terminer une phase'),
    (Icons.hourglass_bottom, 'Minuteur de routine terminé → la routine est validée MAIS le chrono continue : tu logues le temps en plus jusqu\'à ce que tu arrêtes'),
    (Icons.history, 'Activités des dernières 24h : swipe pour supprimer, couleur du domaine, et mise à jour en temps réel (plus besoin de quitter pour voir tes modifs)'),
    (Icons.shield_outlined, 'Armes 🗡️🏹🩴 : arsenal plafonné (fini le compteur qui gonflait à l\'infini) — au-delà, c\'est l\'or qui prend le relais. Et lancer « Affronter mon backlog » ne ferme plus « Mon or »'),
  ]),
  _Entry('6.07', '11 juin 2026', [
    (Icons.timer_outlined, 'Routine minutée dans ton programme du jour : au lancement ▶, tu choisis « Chrono » (temps libre) ou « Minuteur » (décompte) — au bout du minuteur, la routine se valide toute seule'),
    (Icons.add_circle_outline, 'Tu peux ajouter À LA MAIN un bloc dans ton programme du jour (bouton + en haut, ou tape la zone vide) : titre, heure, durée, catégorie — sans passer par Claude'),
    (Icons.event_busy, 'Donjon : une routine déjà programmée dans les 30 prochains jours n\'apparaît plus comme nuisible 🕷️ — fini le doublon entre ton planning et le donjon'),
    (Icons.sports_kabaddi, 'Épée 🗡️ plus facile à stocker : 1 action de tâche cochée = 1 épée (avant il fallait des tâches entières). Et cocher une action compte PARTOUT pareil — web, fiche mobile ou écran « Maintenant »'),
    (Icons.devices, 'Or cohérent entre tes appareils : solde, gains du jour, épées et score se recalculent depuis tes vraies données → mêmes valeurs sur mobile ET tablette, sans double-comptage'),
  ]),
  _Entry('6.06', '11 juin 2026', [
    (Icons.edit_outlined, 'Gestion de projets : tu peux maintenant RENOMMER un projet (tap sur son titre) et gérer ses PHASES sur mobile — ajouter, renommer, supprimer (menu ⋯). Supprimer une phase rend ses tâches « sans phase »'),
    (Icons.today, 'Planification : un bouton « Aujourd\'hui » dans le sélecteur de date (défis / programmer) — plus besoin d\'ouvrir le calendrier pour planifier dans la journée'),
    (Icons.event_available_outlined, 'Donjon : « Programmer pour plus tard » sur une routine — pas le temps maintenant ? Tu la planifies (avec rappel) et elle quitte la liste'),
    (Icons.checklist_rtl_outlined, 'Quête du jour plus claire : elle indique ce qui compte (routine validée · action de projet cochée · défi relevé), et disparaît de « Maintenant » une fois le coffre récupéré'),
  ]),
  _Entry('6.05', '11 juin 2026', [
    (Icons.favorite_outline, 'Combat à cœurs ❤️ : les PV d\'un nuisible s\'affichent en cœurs (✅ = déjà éliminés). Une routine MINUTÉE (ex. 25 min) devient 5 cœurs → tu choisis comment frapper : Finir, 25/15/5 min ou Chrono libre. Pareil pour les activités en retard'),
    (Icons.push_pin_outlined, '« Engager » un nuisible (coût en armes 🩴🏹🗡️) l\'épingle dans « Combats en cours » (dans Mon or) → tu le retrouves sans re-fouiller la carte. Pour le vaincre : ouvre sa carte et FAIS le vrai travail'),
    (Icons.event_outlined, '« Programmer pour plus tard » depuis la carte de combat : pas le temps maintenant ? Choisis le jour + l\'heure + rappel, ça réapparaît au bon moment (comme un défi Orion)'),
    (Icons.sports_kabaddi, 'Accès direct « Affronter mon backlog · niveau N » dans Mon or (farm par défaut) ; « Mes cartes » pour les anciennes cartes'),
    (Icons.bug_report_outlined, 'Correction : le lanceur de routines (FAB) affichait un compteur hebdo périmé (0/4 même si faite cette semaine) — corrigé'),
  ]),
  _Entry('6.04', '11 juin 2026', [
    (Icons.bug_report_outlined, 'GROS : les nuisibles sont désormais TON VRAI BACKLOG ! 🕷️ = une routine à faire · 🦂 = une activité en retard · 🐍 = une tâche active. Leurs PV = le travail restant. Tu les frappes en FAISANT le vrai travail (routine +1, 5 min sur l\'activité, cocher une action). PV à 0 = item rattrapé !'),
    (Icons.map_outlined, '« Affronter mon backlog » (dans Mes cartes) : une carte peuplée d\'un max de tes vrais items à abattre — chemin toujours praticable, les plus faciles près de l\'entrée. Chaque case se remplit de la couleur de son domaine selon les PV restants'),
    (Icons.pets_outlined, 'Recettes de chasse : capture X nuisibles d\'un type → débloque une créature de collection (🐭 Souris → 🐲 Dragon). Chaque type d\'ennemi a son arme : 🩴 sandale (routine) · 🏹 arc (temps) · 🗡️ épée (tâche)'),
    (Icons.push_pin_outlined, 'Étoile ⭐ sur une tâche → tu choisis l\'heure + la durée, elle file dans ton programme « Maintenant ». Bouton ▶ pour la lancer (chrono + ses actions affichées)'),
    (Icons.check_circle_outline, 'Tu peux maintenant TERMINER un projet (toutes tâches faites) → il se range dans « Terminé ». Et les routines de « Mon or » sont en cartes plus lisibles'),
  ]),
  _Entry('6.03', '10 juin 2026', [
    (Icons.map_outlined, 'Nouveau : « Mes cartes » (ex-Collection) avec la CHASSE 🏹 ! Re-explore une carte débloquée en instance fraîche pour traquer ses nuisibles et farmer leur butin (or + créatures). Les ennemis y apparaissent à coup sûr ; chaque torche se paie'),
    (Icons.sports_kabaddi, 'Combat : la forge de ton arme démarre quand tu CROISES le nuisible — il faut 3 routines/tâches de plus que ce que tu avais déjà fait. Plus de mise à mort « gratuite » avec le travail du matin'),
    (Icons.looks_one_outlined, 'Ta première carte est enfin nommée « Niveau 1 » (et non 2). L\'affichage et la provenance des butins suivent ton niveau réel'),
    (Icons.visibility_outlined, 'Lisibilité : « Ouvrir le coffre » et les boutons or ont désormais un texte foncé bien contrasté (fini le teal sur jaune illisible)'),
  ]),
  _Entry('6.02', '10 juin 2026', [
    (Icons.schedule, 'Valeur du temps simplifiée : 1 or toutes les 15 min loggées, tout niveau confondu (le sommeil loggué compte aussi, sans pénalité). Une grosse journée plafonne naturellement'),
    (Icons.sports_kabaddi, 'Combat toujours explicite : un ennemi ne meurt plus « tout seul » au tap — tu ouvres l\'écran de combat et tu FRAPPES. Le drain des nuisibles est adouci (plafonné 6h) et tuer rapporte toujours un butin qui couvre au moins ce qu\'il t\'a coûté'),
    (Icons.timer_outlined, 'Mode 5 min du donjon corrigé : tu franchis le passage UNIQUEMENT si tu vas au bout du minuteur. Tu changes d\'avis et tu l\'arrêtes ? Tu restes où tu es. On ne te propose que les routines pas encore faites du jour'),
    (Icons.flag_circle_outlined, 'La Quête du jour passe dans l\'onglet « Maintenant », avec un meilleur contraste (lisible)'),
    (Icons.straighten, 'Barre d\'XP corrigée : elle ne dépasse plus le palier (fini le « 234/30 ») — une fois le palier atteint, elle affiche « à révéler » et le surplus part en or'),
    (Icons.monetization_on_outlined, 'Partout : vraie pièce d\'or dorée au lieu de l\'emoji 🪙 (qui rendait « argent »)'),
  ]),
  _Entry('6.01', '10 juin 2026', [
    (Icons.sports_martial_arts, 'Combat ! Les nuisibles 🕷️🦂🐍 te maudissent (routines ÷2) et te grignotent l\'or à l\'heure. Pour les vaincre, FORGE ton arme par l\'action : 3 routines = 🩴 sandale, terminer des tâches = 🗡️ épée. Combat plein-écran quand tu les affrontes'),
    (Icons.shield_moon_outlined, 'Chaque niveau a son GARDIEN 🛡️ (un mini-boss qui reste tant que tu ne l\'as pas vaincu). Tuer un ennemi rapporte du butin d\'or 💰 (gros butin pour le gardien) !'),
    (Icons.castle_outlined, 'Donjon en carte à nœuds : explore, découvre tes défis en avançant. Nouveaux nœuds « action express » ⏱️ : lance 5 min sur une routine pour franchir un passage (même inachevé, tu auras avancé). Les défis ne comptent qu\'à partir du moment où ils apparaissent'),
    (Icons.face_retouching_natural, 'Avatars : débloque des skins pour ton perso de carte (🧙🥷🦸…) avec ton or, dans la boutique'),
    (Icons.travel_explore, 'Carte : un indice « ✨ Trésors » te dit s\'il reste du butin à trouver ; et chaque collectible garde sa provenance (où/quand obtenu)'),
    (Icons.fact_check_outlined, 'Orion te propose enfin tes idées d\'inbox dans « À valider » ; le classement départage les ex-aequo par or disponible'),
  ]),
  _Entry('6.00', '10 juin 2026', [
    (Icons.emoji_events_outlined, 'Nouveau : la Quête du jour ! Accomplis 3 actions aujourd\'hui (routines, tâches, défis) → ouvre un coffre à récompense surprise (or + chance de butin rare). Visible dès l\'accueil 🎯🎁'),
    (Icons.local_fire_department_outlined, 'Série quotidienne 🔥 : fais ta quête plusieurs jours d\'affilée → le coffre rapporte de plus en plus, avec de gros bonus aux paliers (3, 7, 14, 30 jours)'),
    (Icons.celebration_outlined, 'Plus festif : des confettis 🎉 quand tu ouvres un coffre, valides une routine ou débloques un niveau'),
    (Icons.account_balance_wallet_outlined, 'L\'app bar affiche maintenant ton vrai solde d\'or (au lieu du net projeté) — plus clair'),
    (Icons.ac_unit, '« Mon or » : « -1 or » et « Geler » regroupés en fin de ligne ; lance un chrono/minuteur directement depuis une routine'),
  ]),
  _Entry('5.99', '10 juin 2026', [
    (Icons.castle_outlined, 'Donjon repensé : une carte à nœuds qu\'on explore, les défis se découvrent en avançant (défi en cours + bouton « Défis »). Difficulté progressive : les premiers niveaux se débloquent en une journée. Entrée auto dans le donjon une fois qu\'on y est déjà allé'),
    (Icons.bolt_outlined, 'Or du jour dépensable EN DIRECT (plus d\'attente au lendemain) ; valeur du temps recalibrée (généreuse au début) ; Multiplicateur ×2 dure maintenant 3 jours'),
    (Icons.play_circle_outline, '« Mon or » : lance un chrono ou un minuteur (5 min par défaut) directement depuis une routine ; solde qui se met à jour en direct'),
    (Icons.flag_outlined, '« Priorités du jour » → « Défis du moment » : les défis du donjon s\'y déposent. Onglet « Score » → « XP »'),
    (Icons.fact_check_outlined, 'ORION propose enfin : tes idées de la boîte à idées arrivent dans « À valider » (accepter / refuser) au lieu d\'être transformées en projets d\'office'),
  ]),
  _Entry('5.98', '10 juin 2026', [
    (Icons.castle_outlined, 'L\'Expédition prend tout son sens : une fois le château 🏰 trouvé sur la carte, tu entres dans le DONJON pour débloquer le niveau. Plus de déblocage automatique au château'),
    (Icons.task_alt_outlined, 'Le donjon se franchit en relevant des défis préparés par Orion — de vrais objectifs (faire une routine X jours, terminer une tâche, logger du temps) qui se valident TOUT SEULS dès que tu les accomplis dans l\'app. Tous relevés → niveau débloqué'),
    (Icons.map_outlined, 'Exploration de la carte allégée : se déplacer sur une case déjà éclairée est désormais GRATUIT (on ne paie que pour éclairer le brouillard), une torche éclaire plus large, et la 1ʳᵉ torche du jour est offerte'),
  ]),
  _Entry('5.97', '10 juin 2026', [
    (Icons.bolt_outlined, 'Ton or et ton niveau bougent maintenant EN DIRECT dans la journée : dès qu\'une routine, du temps ou une action est validé, le total et la barre de progression montent (au lieu d\'attendre le lendemain). Le gain du jour reste provisoire et se fige le soir'),
    (Icons.show_chart, 'L\'historique d\'or des 7 derniers jours s\'affiche désormais en courbe lissée (au lieu de barres), avec le jour courant mis en évidence'),
    (Icons.healing_outlined, 'Correction : dans certains cas, l\'or/XP gagné la veille pouvait ne pas être comptabilisé le lendemain — c\'est réparé, et les jours concernés sont récupérés automatiquement au lancement'),
    (Icons.explore_outlined, 'Expédition : on peut de nouveau éclairer les cases voisines sous brouillard (un bug empêchait de les toucher après le 1ᵉʳ pas). La case à éclairer affiche 🔦, et un mur découvert te le signale'),
    (Icons.help_outline, 'Le récap « Comment marche l\'or ? » affiche enfin les vraies règles (gains et pertes en or) au lieu des anciennes valeurs XP'),
  ]),
  _Entry('5.96', '9 juin 2026', [
    (Icons.explore_outlined, 'Nouveau : l\'Expédition est une vraie carte à explorer ! Pour débloquer le prochain niveau, déplace ton perso de case en case (1 or, 1ᵉʳ pas du jour gratuit) à travers le brouillard (torche 5 or pour éclairer une zone) jusqu\'au château 🏰. Au moins 2 chemins → explore pour trouver des collectibles'),
    (Icons.pets_outlined, 'La carte réagit à ta semaine : si ton score baisse vs la semaine passée, des nuisibles 🕷️🦂🐍 apparaissent (ils te drainent de l\'or chaque jour — élimine-les avec une épée/sandale, ou attends qu\'ils partent). Si ta semaine progresse, ce sont des trésors 💰 qui surgissent'),
    (Icons.collections_bookmark_outlined, 'Nouveau : ta Collection ! Animaux et butins ramassés sur les cartes s\'y accumulent (accessible depuis « Mon or »). Explorer une carte à 100 % offre un trésor rare'),
  ]),
  _Entry('5.95', '9 juin 2026', [
    (Icons.map_outlined, 'Nouveau : l\'Expédition ! Atteindre l\'XP d\'un niveau ne suffit plus — son titre reste secret. Pour le débloquer, tu traverses une petite carte sinueuse : chaque pas se franchit avec un outil (🥾 pas, ⛏️ pioche, 🔑 clé, 🪏 pelle) acheté en boutique. Des forks te font arbitrer (route courte chère vs longue bon marché), des trésors récompensent les détours. Le niveau se gagne, il n\'est plus juste « atteint »'),
    (Icons.handyman_outlined, 'Outils d\'expédition en boutique : achète tes pas/pioches/clés/pelles pour avancer sur la carte. Tu continues à gagner XP et or normalement pendant l\'exploration — la carte est l\'objectif que tu finances en bossant tes routines et projets'),
    (Icons.storefront_outlined, 'Boutique par paliers : chaque protection se débloque à un certain niveau (Bouclier niveau 5, Multiplicateur 7…) et son prix augmente à chaque niveau atteint'),
    (Icons.military_tech_outlined, 'La progression va plus loin : 5 nouveaux titres après Élite — Virtuose, Maître d\'œuvre, Sage, Titan, Mythique — puis un prestige Mythique I/II… On n\'arrive plus au bout trop vite (et personne n\'est rétrogradé : ton rang acquis est conservé)'),
    (Icons.insights_outlined, 'Onglet Score : le détail complet (score du jour, niveau, courbe XP 7 jours, semaine, objectif, paliers) est affiché directement — fini le bouton « voir le détail »'),
  ]),
  _Entry('5.94', '9 juin 2026', [
    (Icons.checklist_rtl_outlined, '« Mon or » repensé : tes routines du jour sont listées avec des +/− pour les cocher sur place. Chaque routine affiche l\'or qu\'elle rapporte (le bonus grandit avec ta série), une encoche verte une fois validée, et un bouton « Geler » direct si elle risque de te coûter. Tout se met à jour en direct, sans rouvrir l\'écran'),
    (Icons.flag_outlined, 'Le « Sursis de deadline » sert enfin : depuis une tâche (mobile ou web), « Repousser la deadline » choisit une nouvelle date — ça coûte un peu d\'or par semaine de report, ou rien si tu as un Sursis en stock. La tâche sort alors des retards et arrête de saigner'),
    (Icons.shopping_bag_outlined, 'Achat-à-l\'usage : plus besoin d\'ouvrir la Boutique à l\'avance. Si tu n\'as pas le Joker / Gel / Sursis au moment où il sert (supprimer, geler une routine, repousser une échéance), on te propose de l\'acheter sur-le-champ'),
    (Icons.auto_awesome_outlined, 'Boutique enrichie de 3 protections : 🛡️ Bouclier anti-retard (gèle le −1/j d\'une tâche pendant 7 jours), ✨ Multiplicateur ×2 (double tes gains d\'or du jour) et 🧬 Réparation de série (regèle un jour manqué passé pour sauver une streak cassée)'),
    (Icons.ac_unit, 'Geler une routine retire immédiatement son −1 de ton or net projeté (barre du haut + « Mon or »), sans attendre'),
  ]),
  _Entry('5.93', '9 juin 2026', [
    (Icons.ac_unit, 'Le « Gel de série » protège enfin ta série : un jour gelé ne casse plus ta streak (jour de repos neutre, sans pénalité). Tu peux ainsi sauver une longue série — et les gros bonus XP qui vont avec — pour un jour off.'),
    (Icons.repeat_rounded, 'Lanceur de routines (bouton +) : il affiche désormais toutes tes routines, même quand une activité tourne (plus de filtrage sur le domaine en cours).'),
  ]),
  _Entry('5.92', '9 juin 2026', [
    (Icons.delete_sweep_outlined, 'Suppression de projet repensée : « Mettre en veille » garde ton historique gratuitement ; « Supprimer » (désormais possible directement, sans archiver d\'abord) efface définitivement et coûte de l\'or — sauf pour un brouillon. Tu paies pour faire le ménage, pas pour ranger'),
    (Icons.monetization_on_outlined, 'L\'or s\'affiche maintenant avec une vraie pièce dorée (au lieu de la pièce grise)'),
    (Icons.tips_and_updates_outlined, 'Onglet « Mon or » allégé : les routines/​tâches qui te coûtent sont listées de façon compacte, avec une pastille ⓘ qui explique le principe'),
    (Icons.local_library_outlined, 'Bibliothèque de défis : pour partager un défi, tu choisis désormais l\'un de tes défis actifs au lieu d\'en réécrire un de zéro'),
  ]),
  _Entry('5.91', '9 juin 2026', [
    (Icons.edit_note_outlined, 'Nouveau : mode planification ! Un projet créé (par toi ou par ORION) naît en « brouillon » — tu le retravailles librement, sans rien gagner ni perdre en or, et hors score. Quand il te convient, « Valider le plan » l\'active : il compte alors vraiment. Repère-les au badge « Plan »'),
    (Icons.workspace_premium_outlined, 'Barre du haut simplifiée : un seul indicateur regroupe tes gains du jour ⭐, ton score (l\'anneau) et ton or net projeté pour ce soir (vert si tu finis dans le positif, rouge sinon)'),
    (Icons.dashboard_customize_outlined, 'Nouveau hub gamification : tape l\'indicateur pour ouvrir un seul écran à onglets — Mon or · Score · Classement · Défis (avec accès aux statistiques complètes). Fini les boutons éparpillés'),
  ]),
  _Entry('5.90', '9 juin 2026', [
    (Icons.account_tree_outlined, 'Gestion de projet 100% autonome sur mobile : crée, renomme, édite (dates, phase, jalon) et supprime tes tâches directement depuis la fiche projet — plus besoin de passer par l\'IA ou l\'app web. (Supprimer une tâche coûte un peu d\'or, comme le reste.)'),
    (Icons.add_box_outlined, 'Nouveau projet : tu peux maintenant créer un projet vide « sans IA » (titre + domaine + date cible), en plus de la structuration automatique par ORION'),
  ]),
  _Entry('5.89', '8 juin 2026', [
    (Icons.monetization_on_outlined, 'Nouveau : l\'économie d\'Or ! Tu gagnes des pièces d\'or par l\'effort (routines +2/j, temps, projets) et tu en perds par la procrastination (routine manquée −1/j) ou les retards. Supprimer coûte de l\'or (selon le contenu), déplacer/réorganiser est gratuit. Ton niveau, lui, ne descend jamais. Tout est dans « Mon or » (menu ⋮)'),
    (Icons.shopping_cart_outlined, 'Boutique d\'Or : dépense ton or pour te protéger — gel de série 🧊 (un jour off sans pénalité), sursis de deadline ⏳, joker de suppression 🗑️, et titres à débloquer'),
    (Icons.fact_check_outlined, 'ORION propose, tu valides : les idées de la boîte à idées deviennent des propositions à accepter / refuser / rediriger (file « À valider », badge dans la barre du haut) — fini les projets créés d\'office'),
    (Icons.account_tree_outlined, 'Sous-projets & réorganisation directe : déplace une tâche vers un autre projet, une action vers une autre tâche, ou transforme une action en sous-projet — sans passer par ORION'),
    (Icons.cleaning_services_outlined, 'Revue de la semaine (menu ⋮) : un point clair sur les projets en sommeil, les idées en attente et les tâches à classer ; ORION peut t\'alerter quand une routine qui rapporte va casser'),
  ]),
  _Entry('5.88', '5 juin 2026', [
    (Icons.emoji_events_outlined, 'Classement plus clair : ton rang « 🫵 Toi » (pseudo, niveau, XP) s\'affiche en tête, et un message t\'explique quoi faire quand tu es encore seul — ton XP est déjà compté en attendant les autres'),
  ]),
  _Entry('5.87', '5 juin 2026', [
    (Icons.local_library_outlined, 'Nouveau : Bibliothèque de défis partagée ! Découvre des défis proposés par la communauté (organisés et notés par Orion), abonne-toi, et propose les tiens. Accès via l\'éclair ⚡ → « Bibliothèque »'),
  ]),
  _Entry('5.86', '5 juin 2026', [
    (Icons.schedule, 'Programme du jour trié par heure : les défis programmés apparaissent désormais à leur créneau (ex. 6h, 7h) au lieu d\'être ajoutés en bas de la liste'),
  ]),
  _Entry('5.85', '5 juin 2026', [
    (Icons.person_outline, 'Paramètres → Compte plus clair : une fois connecté, on n\'affiche que ton compte (l\'option de connexion par email disparaît quand tu es déjà connecté)'),
  ]),
  _Entry('5.84', '5 juin 2026', [
    (Icons.emoji_events_outlined, 'Nouveau : Classement XP ! Choisis un pseudo, rejoins le classement (opt-in) et compare ton XP avec les autres — par semaine, par mois ou en total. Tape l\'étoile ⭐ en haut pour l\'ouvrir'),
  ]),
  _Entry('5.83', '5 juin 2026', [
    (Icons.show_chart, 'Gamification : ton bloc niveau affiche maintenant l\'XP gagné aujourd\'hui et une mini-courbe des 7 derniers jours ; le résumé du jour montre « +X XP aujourd\'hui »'),
  ]),
  _Entry('5.82', '5 juin 2026', [
    (Icons.star_rounded, 'XP enrichi : tu gagnes des points en continu — 1 XP / heure loggée, 2 / routine complétée, 5 / défi relevé, 1 / action de projet cochée — qui s\'ajoutent à l\'XP des badges et font monter ton niveau'),
    (Icons.workspace_premium_outlined, 'Niveaux prolongés : au-delà d\'Élite, tu passes Élite I, II, III… (toujours un palier à viser). Total d\'XP affiché discrètement en haut de l\'écran ⭐'),
  ]),
  _Entry('5.81', '5 juin 2026', [
    (Icons.lock_outline, 'Étanchéité des comptes : la déconnexion nettoie désormais les données locales de l\'appareil — elles ne « débordent » plus sur le compte suivant connecté sur le même téléphone (tes données restent sauvegardées sur ton compte et sont restaurées à la reconnexion)'),
  ]),
  _Entry('5.80', '4 juin 2026', [
    (Icons.apple, 'Correction majeure : la connexion avec Apple fonctionne à nouveau (le token Apple est désormais transmis complet à Firebase) — débloque l\'inscription/restauration via Apple'),
  ]),
  _Entry('5.79', '4 juin 2026', [
    (Icons.keyboard_outlined, 'Inbox : modifier une idée ne passe plus sous le clavier — le champ reste visible, et l\'édition est désormais multi-ligne pour les idées longues'),
  ]),
  _Entry('5.78', '4 juin 2026', [
    (Icons.checklist_rtl, 'Onglet Maintenant : les boutons flottants (FAB) ne masquent plus les dernières lignes du programme du jour — tout reste cochable'),
    (Icons.local_fire_department_rounded, 'Défi programmé relevé : un message confirme « Défi relevé ! » avec ta série quand tu logges le temps (le bloc se coche et sort des défis en cours automatiquement)'),
  ]),
  _Entry('5.77', '4 juin 2026', [
    (Icons.apple, 'Correction : la connexion avec Apple aboutit correctement même si la synchronisation des données échoue juste après — plus de message d\'erreur trompeur (et l\'annulation ne montre plus d\'erreur)'),
  ]),
  _Entry('5.76', '4 juin 2026', [
    (Icons.flag_outlined, 'Réglages ORION plus clairs : « instructions permanentes » devient « Ta priorité du moment » avec une explication (ORION la lit chaque matin et à chaque demande pour cadrer ses suggestions) et un exemple'),
  ]),
  _Entry('5.75', '4 juin 2026', [
    (Icons.add_alert_outlined, 'Défis programmés : tu peux maintenant avoir jusqu\'à 2 rappels par défi — depuis « Défis en cours » (bouton ⚡), ajoute un 2ᵉ rappel (la veille, 1h avant ou 15 min avant) à un défi déjà créé'),
  ]),
  _Entry('5.74', '4 juin 2026', [
    (Icons.bolt_rounded, 'Nouveau bouton ⚡ dans la barre du haut : ouvre « Défis en cours » — la liste de tes défis programmés (jour, heure, durée) que tu peux annuler d\'un geste'),
  ]),
  _Entry('5.73', '4 juin 2026', [
    (Icons.local_fire_department_rounded, 'Challenge me ne propose plus une activité qui a déjà un défi programmé — il t\'en propose une autre, pour que tu étales tes défis sur le moment où tu seras dispo'),
  ]),
  _Entry('5.72', '4 juin 2026', [
    (Icons.notifications_active_outlined, 'Sonneries Cloche, Carillon et Digital désormais sélectionnables dans les Paramètres (sons placeholder, remplaçables plus tard) — le minuteur et les défis programmés peuvent enfin changer de son'),
  ]),
  _Entry('5.71', '4 juin 2026', [
    (Icons.play_arrow_rounded, 'Lanceur de routines (FAB) : boutons de lancement direct sur chaque carte — ▶ démarre le chrono sur l\'activité liée, ⏱ démarre le minuteur si réglé (les routines sans activité liée gardent leur pastille de fréquence)'),
  ]),
  _Entry('5.70', '4 juin 2026', [
    (Icons.bug_report_outlined, 'Correction : supprimer une routine depuis sa fiche la retire aussitôt du lanceur (FAB) — elle ne reste plus affichée et ne plante plus'),
    (Icons.bug_report_outlined, 'Correction : supprimer une activité par balayage depuis un domaine ne plante plus — la carte disparaît immédiatement'),
  ]),
  _Entry('5.69', '4 juin 2026', [
    (Icons.repeat_rounded, 'Lanceur de routines (FAB) : toutes les routines sont visibles (quotidiennes, hebdo, mensuelles) avec une pastille de fréquence'),
    (Icons.play_circle_outline, 'Tap sur une routine → mini-menu : démarrer son minuteur (si configuré), marquer fait, ou réglages'),
    (Icons.timer_outlined, 'Routine : minuteur par défaut optionnel (nécessite une activité liée) — à la fin, la routine se coche et le temps est loggué sur l\'activité'),
    (Icons.link, 'Fiche routine : lier, changer ou retirer l\'activité associée'),
  ]),
  _Entry('5.68', '4 juin 2026', [
    (Icons.notifications_active_outlined, 'Paramètres : choix de la sonnerie de l\'alarme (minuteur + défis programmés) parmi plusieurs sons'),
  ]),
  _Entry('5.67', '4 juin 2026', [
    (Icons.delete_outline, 'Supprimer une activité ou une routine directement depuis sa fiche (bouton 🗑 dans l\'en-tête) — plus besoin de chercher où supprimer'),
  ]),
  _Entry('5.66', '4 juin 2026', [
    (Icons.delete_outline, 'Correction : supprimer une activité depuis un domaine est désormais persistant — elle ne réapparaît plus à la réouverture de l\'app'),
  ]),
  _Entry('5.65', '4 juin 2026', [
    (Icons.local_fire_department_rounded, 'Challenge me : tu peux désormais PROGRAMMER un défi pour demain matin (ou plus tard) au lieu de le relever sur le champ — il s\'ajoute à ton plan du jour à l\'heure choisie, te rappelle avant (la veille au soir par défaut, ajustable), et sonne le moment venu'),
    (Icons.check_circle_outline, 'Un défi programmé est gagné automatiquement dès que tu le coches OU que tu logges le temps sur l\'activité ce jour-là'),
  ]),
  _Entry('5.64', '4 juin 2026', [
    (Icons.auto_awesome, 'ORION range ta boîte à idées tout seul à l\'ouverture de l\'app : tes idées se regroupent en nouveaux projets ou rejoignent un projet existant, et il te relance en douceur sur l\'idée qui traîne depuis le plus longtemps'),
  ]),
  _Entry('5.63', '4 juin 2026', [
    (Icons.timelapse_rounded, 'Minuteur en cours : onglet Maintenant en mode focus — un grand anneau de décompte remplace le chrono et le programme du jour se masque ; à la fin tu choisis « Continuer » (en chrono) ou « Terminer »'),
    (Icons.restore_rounded, 'Le minuteur survit si tu quittes et rouvres l\'app : tu retrouves ton décompte là où il en était'),
    (Icons.donut_large_rounded, 'Anneau du temps de l\'accueil : l\'objectif global est plafonné à 24h — fini le pourcentage qui paraissait bas un jour bien rempli'),
  ]),
  _Entry('5.62', '3 juin 2026', [
    (Icons.timer_rounded, 'Minuteur d\'activité = vraie alarme : elle sonne en boucle jusqu\'à ce que tu l\'arrêtes quand l\'app tourne en arrière-plan, et une sonnerie de ~30s prend le relais même si tu as fermé l\'app'),
    (Icons.play_arrow_rounded, 'À la fin du minuteur : « Continuer » pour enchaîner en chrono sur ta lancée, ou « Terminer » → ta fiche d\'activité se rouvre avec ta progression à jour pour t\'inviter à remettre un coup'),
    (Icons.touch_app_outlined, 'Lancer une activité ouvre désormais sa fiche (stats + cible) où tu choisis chrono libre OU minuteur, au lieu de démarrer le chrono à l\'aveugle'),
    (Icons.smart_toy_rounded, 'Nouveau « Challenge me » : ORION te défie sur l\'activité la plus en retard du jour, lance le minuteur, et compte ta série de défis relevés 🔥'),
  ]),
  _Entry('5.61', '3 juin 2026', [
    (Icons.auto_awesome, 'ORION cale tes cibles de temps : au lieu d\'un 30 min par défaut sur chaque activité, il pose une intention réaliste dès le départ et la recalibre selon ton réalisé — tes jauges de temps reflètent enfin quelque chose de juste'),
    (Icons.push_pin_outlined, 'Si tu règles une cible de temps à la main, elle est épinglée : ORION ne la touche plus'),
  ]),
  _Entry('5.60', '3 juin 2026', [
    (Icons.auto_awesome, 'ORION : nouveau « Levier du jour » dans le brief — quand une dimension de ta productivité décroche (routines, temps ou projets), ORION te dit laquelle rattraper en priorité et comment'),
  ]),
  _Entry('5.59', '3 juin 2026', [
    (Icons.balance_outlined, 'Productivité du jour : score d\'équilibre — être bon sur plusieurs dimensions (routines · temps · projets) compte plus que cartonner sur une seule, et négliger une dimension pèse désormais sur ta journée'),
    (Icons.insights_outlined, 'Nouvelle triade « Aujourd\'hui » sous la heatmap : tes jauges routines / temps / projets avec le « levier du jour » mis en avant — tu vois d\'un coup sur quoi te concentrer pour faire monter ton score'),
  ]),
  _Entry('5.58', '2 juin 2026', [
    (Icons.insights_outlined, 'Productivité du jour : compte désormais le temps travaillé et les actions de projet cochées, pas seulement les routines — chaque dimension valorisée selon ton propre standard (meilleur des trois)'),
    (Icons.grid_view_rounded, 'Heatmap productivité : une journée de deep work ou de gros avancement projet n\'est plus pénalisée parce qu\'il manquait des routines'),
  ]),
  _Entry('5.57', '2 juin 2026', [
    (Icons.undo_rounded, 'Widgets : re-tap pour décocher — un bloc du programme repasse à faire, une routine déjà complétée se décrémente'),
    (Icons.repeat_rounded, 'Widget Routines : les routines complétées restent visibles (et décochables) au lieu de disparaître'),
    (Icons.grid_view_rounded, 'Heatmap du temps : chaque domaine et activité est coloré selon son propre standard (jour bien chargé) — les domaines peu chronophages ne sont plus délavés'),
    (Icons.person_outline, 'Paramètres : « Compte Apple » renommé « Compte »'),
  ]),
  _Entry('5.56', '2 juin 2026', [
    (Icons.touch_app_outlined, 'Widgets actionnables (iOS 17+) : coche une routine, un bloc du programme ou une sous-action de tâche directement depuis l\'écran d\'accueil'),
    (Icons.checklist_rtl, 'Nouveau widget « Tâche du jour » : la tâche du haut avec ses actions cochables sans ouvrir l\'app'),
    (Icons.open_in_new, 'Fix : le widget Projets ouvre le bon projet même quand l\'app était fermée'),
  ]),
  _Entry('5.55', '2 juin 2026', [
    (Icons.today_outlined, 'Nouveau widget « Programme du jour » : tes blocs horaires sur l\'écran d\'accueil (Medium / Large)'),
    (Icons.repeat_rounded, 'Nouveau widget « Routines » : anneau de progression + uniquement les routines qu\'il te reste à faire (Small / Medium / Large)'),
    (Icons.folder_open_rounded, 'Nouveau widget « Projets » : tes projets en cours — tap sur un projet pour l\'ouvrir directement dans l\'app'),
    (Icons.auto_awesome, 'ORION : bouton « Enregistrer » pour modifier tes instructions permanentes'),
    (Icons.tune, 'Paramètres : option pour activer / désactiver les « Priorités du jour » (désactivé par défaut)'),
  ]),
  _Entry('5.51', '2 juin 2026', [
    (Icons.repeat_rounded, 'Lancer une routine : la liste est triée par domaine, comme le lanceur d\'activité'),
    (Icons.auto_awesome, 'ORION : sa réponse à ta demande s\'affiche dans l\'onglet, avec un effet machine à écrire rétro'),
    (Icons.grid_view_rounded, 'Accueil : heatmap du temps par domaine + barres des 12 dernières semaines, sous la productivité'),
  ]),
  _Entry('5.50', '2 juin 2026', [
    (Icons.auto_awesome, 'ORION : correction — plus de blocage « token API requis » après une connexion par email sur un nouvel appareil ; l\'accès se rétablit tout seul'),
  ]),
  _Entry('5.49', '2 juin 2026', [
    (Icons.auto_awesome, 'ORION repensé : le brief stratège du jour est dans l\'onglet ORION, et tu lui donnes une demande → il exécute et te répond. Fini les messages qui s\'accumulent.'),
    (Icons.warning_amber_outlined, 'Brief : alerte « À ne pas rater aujourd\'hui » mise en avant quand un élément est urgent'),
  ]),
  _Entry('5.46', '30 mai 2026', [
    (Icons.email_outlined, 'Connexion par email fiabilisée — fonctionne aussi quand ton compte a déjà été créé (web, formation)'),
  ]),
  _Entry('5.45', '27 mai 2026', [
    (Icons.email_outlined, 'Connexion par email (magic link) — se connecter sans mot de passe depuis les paramètres'),
  ]),
  _Entry('5.44', '26 mai 2026', [
    (Icons.today_outlined, 'Programme du jour visible même quand une activité est en cours'),
    (Icons.pie_chart, 'Camembert activités loggées déplacé dans l\'onglet Accueil'),
  ]),
  _Entry('5.43', '26 mai 2026', [
    (Icons.sync_problem_outlined, 'Fix : supprimer un domaine ou une session ne les faisait pas revenir au redémarrage'),
  ]),
  _Entry('5.42', '26 mai 2026', [
    (Icons.widgets_outlined, 'Widget iOS : diagnostic amélioré (bouton "Forcer", nombre de projets chargés) — correction de l\'écriture prématurée avec données vides'),
  ]),
  _Entry('5.41', '26 mai 2026', [
    (Icons.today_outlined, 'Programme du jour : timeline horaire dans l\'onglet Maintenant — généré par Claude ou ORION (swipe pour supprimer, tap pour éditer, long press pour réordonner)'),
  ]),
  _Entry('5.40', '25 mai 2026', [
    (Icons.timer_outlined, 'Minuteur : le bandeau activité affiche le compte à rebours en orange (rouge sous 60 s) quand un minuteur est actif'),
    (Icons.timer_outlined, 'Minuteur : la durée choisie est mémorisée par activité — la fiche se rouvre avec la dernière sélection'),
  ]),
  _Entry('5.39', '25 mai 2026', [
    (Icons.cleaning_services_outlined, 'Nettoyage interne : suppression complète de DayPlanItem — modèle, logique et persistance allégés'),
  ]),
  _Entry('5.38', '25 mai 2026', [
    (Icons.timer_outlined, 'Minuteur de démarrage : pills 5 / 10 / 15 / 25 min sur la fiche activité — auto-stop + notification à la fin'),
    (Icons.lightbulb_outline, 'Inbox : astuce ORION dans l\'état vide — explication du traitement automatique toutes les 6h'),
  ]),
  _Entry('5.37', '25 mai 2026', [
    (Icons.widgets_outlined, 'Widget Medium interactif : cocher une action depuis l\'écran d\'accueil sans ouvrir l\'app (iOS 17+)'),
    (Icons.widgets_outlined, 'Widget Large : tâches Gantt actives groupées par projet'),
  ]),
  _Entry('5.36', '25 mai 2026', [
    (Icons.widgets_outlined, 'Widgets iOS : anneau de routines (Small) et plan du jour (Medium) sur l\'écran d\'accueil'),
  ]),
  _Entry('5.35', '25 mai 2026', [
    (Icons.bar_chart_outlined, 'Heatmap démo : 5 routines + vague sinusoïdale — toute la palette de couleurs visible'),
    (Icons.smart_toy_outlined, 'ORION astuce : précision "sans passer par ORION"'),
  ]),
  _Entry('5.34', '25 mai 2026', [
    (Icons.rocket_launch_outlined, 'Paywall : essai gratuit 7 jours détecté via RevenueCat — CTA, badge carte Annuel et note légale Apple'),
  ]),
  _Entry('5.33', '25 mai 2026', [
    (Icons.smart_toy_outlined, 'ORION : astuce MCP — connexion directe à l\'app web pour des actions stratégiques illimitées'),
    (Icons.bar_chart_outlined, 'Données de démo : heatmap 12 semaines avec routines réalistes (Lecture, Hydratation, Revue)'),
  ]),
  _Entry('5.32', '25 mai 2026', [
    (Icons.language_outlined, 'App web : page blanche Safari corrigée — désactivation du service worker obsolète'),
    (Icons.language_outlined, 'App web : compatible Firefox et Chrome — timeout Firebase 8s'),
  ]),
  _Entry('5.31', '24 mai 2026', [
    (Icons.smart_toy_outlined, 'ORION : 1 activation/jour en gratuit, 5/jour en Pro (barre de progression visible)'),
    (Icons.rocket_launch_outlined, 'Paywall : features mises à jour (ORION, stats, rapport de temps, app web)'),
    (Icons.attach_money_rounded, 'Paywall : prix des cartes maintenant dynamiques depuis RevenueCat (fin des € codés en dur)'),
    (Icons.star_rounded, 'Priorités du jour : déplacées dans l\'onglet Projets (en-tête de la liste)'),
    (Icons.expand_more_rounded, 'Widget Routines : sections fermées par défaut au démarrage'),
    (Icons.show_chart_rounded, 'Score Gantt : dénominateur = toutes les tâches actives — score strictement croissant dans la journée'),
    (Icons.privacy_tip_outlined, 'Confidentialité : page politique de confidentialité accessible depuis le paywall'),
  ]),
  _Entry('5.30', '24 mai 2026', [
    (Icons.bar_chart_outlined, 'Score journalier : intègre la progression des tâches Gantt — les journées deep work sont valorisées'),
    (Icons.task_alt_outlined, 'Sous-actions Gantt : champ createdAt ajouté pour un calcul de progression historique précis'),
    (Icons.rocket_launch_outlined, 'ORION : lien "Passer à Pro" visible directement dans l\'onglet ORION pour les utilisateurs gratuits'),
    (Icons.link_rounded, 'Paywall : liens CGU et Confidentialité plus visibles (soulignés, contraste amélioré)'),
    (Icons.lightbulb_outline, 'Inbox : bouton + dans le header pour capturer une idée directement depuis le sheet'),
  ]),
  _Entry('5.29', '24 mai 2026', [
    (Icons.repeat_rounded, 'Widget Routines : hub CRUD complet — +/- inline, créer depuis le +, modifier/supprimer via appui long'),
    (Icons.remove_circle_outline, 'AppBar : bouton "Nouvelle routine" retiré — création accessible depuis le widget Routines'),
  ]),
  _Entry('5.28', '24 mai 2026', [
    (Icons.delete_forever_outlined, 'Suppression compte : spinner pendant la suppression, fonctionne aussi pour les comptes anonymes, robuste aux erreurs Auth'),
    (Icons.login_rounded, 'Onboarding après suppression : session Firebase Auth créée automatiquement — création de projet ne renvoie plus "Non connecté"'),
  ]),
  _Entry('5.27', '24 mai 2026', [
    (Icons.palette_outlined, 'Bande activité en cours : couleur du domaine (bande, point pulsant, timer, bouton Stop)'),
    (Icons.checklist_rounded, 'Priorités du jour : 3 premières sous-actions de chaque tâche focus, cochables et réorganisables par glisser-déposer'),
    (Icons.filter_list_rounded, 'Lancer une routine : filtre automatique sur le domaine de l\'activité en cours'),
  ]),
  _Entry('5.26', '24 mai 2026', [
    (Icons.star_rounded, 'Priorités du jour : section toujours visible même vide — le + reste accessible pour ajouter manuellement'),
    (Icons.grid_view_rounded, 'Heatmap : labels des lignes corrigés (V=Vendredi, D=Dimanche au lieu de J/S)'),
    (Icons.repeat_rounded, 'Lancer une routine : si une activité est en cours, affiche uniquement les routines de son domaine'),
    (Icons.delete_outline_rounded, 'Suppression de compte : toutes les collections Firestore effacées (projets, documents, assistant, captures…)'),
  ]),
  _Entry('5.25', '24 mai 2026', [
    (Icons.star_rounded, 'Étoile ⭐ routines : stockée sur Activity.todayFlag (Firestore) — plus robuste, survit aux relancements'),
    (Icons.delete_sweep_outlined, 'RecurringAction entièrement supprimé du code — modèle, logique, sync et UI nettoyés'),
    (Icons.bug_report_outlined, 'Projets iOS : tâches sans phase reconnectées à leur phase via groupLabel insensible à la casse'),
  ]),
  _Entry('5.24', '24 mai 2026', [
    (Icons.repeat_rounded, 'FAB routines → "Lancer une routine" (log rapide) — création déplacée dans l\'AppBar et dans le bouton + du sheet'),
  ]),
  _Entry('5.23', '24 mai 2026', [
    (Icons.add_circle_outline, 'Priorités du jour : bouton + pour ajouter une priorité libre "Faire X" sans projet ni routine'),
    (Icons.radio_button_unchecked, 'Items libres cochables (rayés) + bouton × pour supprimer, filtrés par date (reset automatique le lendemain)'),
  ]),
  _Entry('5.22', '24 mai 2026', [
    (Icons.rocket_launch_outlined, 'Onboarding : projet "Prise en main" créé automatiquement — 3 phases, 6 tâches avec sous-actions pour découvrir toutes les fonctionnalités'),
    (Icons.star_rounded, 'Première priorité du jour pré-cochée dans le projet de découverte'),
  ]),
  _Entry('5.21', '24 mai 2026', [
    (Icons.star_rounded, 'Priorités du jour : étoile ⭐ sur les tâches Gantt et routines récurrentes → checklist combinée en haut du dashboard'),
    (Icons.star_outline_rounded, 'Étoile sur les tâches depuis la vue Projets et le sheet projet, étoile sur les routines depuis le sheet Actions récurrentes'),
  ]),
  _Entry('5.20', '24 mai 2026', [
    (Icons.lightbulb_outline, 'Inbox idées : FAB 💡 pour capturer une idée en 2 secondes, bouton appbar avec badge pour gérer (éditer, supprimer) et voir le log de traitement ORION'),
    (Icons.auto_awesome, 'ORION traite automatiquement l\'inbox à chaque cycle : note ponctuelle → reminder, idée projet → tâche ou nouveau projet'),
  ]),
  _Entry('5.19', '24 mai 2026', [
    (Icons.delete_sweep_outlined, 'Actions libres supprimées — FAB "Nouvelle action", carte Courses et données de démo retirés (modèle simplifié : toute action vient d\'un projet ou d\'une routine)'),
  ]),
  _Entry('5.18', '24 mai 2026', [
    (Icons.view_agenda_outlined, 'Projets : tâches avec phaseId désynchronisé retrouvent leur phase via le groupLabel — plus de section "Sans phase" fantôme'),
  ]),
  _Entry('5.17', '24 mai 2026', [
    (Icons.notifications_active_outlined, 'ORION : messages automatiques toutes les 6h maintenant actifs pour les utilisateurs iOS (inscription automatique au cron au démarrage)'),
  ]),
  _Entry('5.16', '24 mai 2026', [
    (Icons.circle_outlined, 'Statistiques : point coloré dans le sélecteur de domaine pour identifier la couleur du graphe'),
    (Icons.check_circle_outline, 'Projets : section "RÉALISÉ" renommée "À JOUR" — évite la confusion avec la fin du projet'),
    (Icons.donut_large_outlined, 'Rapport de temps : donut, barres 12 semaines et heatmap utilisent maintenant la couleur choisie par l\'utilisateur (pas la palette par défaut)'),
  ]),
  _Entry('5.15', '24 mai 2026', [
    (Icons.bar_chart_rounded, 'Statistiques : graphes temps et habitudes colorés selon le domaine sélectionné'),
    (Icons.group_work_outlined, 'Routines "Tous les domaines" : routines groupées par domaine (avec point coloré)'),
    (Icons.check_box_outline_blank, 'Vue projets : sous-actions non cochées uniquement dans les cartes — indicateur "✓ N réalisée(s)" en bas'),
    (Icons.check_circle_outline, 'Détail tâche : doublon "Faits" supprimé de l\'onglet "À faire" — onglet "Fait" conservé'),
  ]),
  _Entry('5.14', '23 mai 2026', [
    (Icons.auto_awesome, 'Nouveau projet iOS : ORION structure tes idées brutes en phases + tâches (1 action stratégique)'),
    (Icons.folder_outlined, 'Projets : FAB "Nouveau projet" → formulaire mobile (titre, domaine, date cible, idées libres)'),
  ]),
  _Entry('5.13', '23 mai 2026', [
    (Icons.local_fire_department, 'Routines : indicateur de série inline 🔥→⭐ (1 étoile par tranche de 5 jours, badge violet au-delà de 25j)'),
  ]),
  _Entry('5.12', '23 mai 2026', [
    (Icons.celebration_outlined, 'Confetti : plus de répétition au démarrage — score 100% max 1 fois/jour'),
    (Icons.emoji_events_outlined, 'Badges streak : fix perte multi-activités (clé composite id+habitId en Firestore)'),
    (Icons.check_circle_outline, 'Projets iOS : tâches done retirées de la liste active'),
    (Icons.label_outlined, 'Projets iOS : tâches avec phase supprimée visibles (sans header) au lieu de disparaître'),
  ]),
  _Entry('5.11', '23 mai 2026', [
    (Icons.settings_outlined, 'Menu : épuré — 6 entrées principales + sous-menu Paramètres (Compte, Tokens API, Confidentialité, Suggestions…)'),
    (Icons.check_circle_outline, 'Projets iOS : liste "Faits" dépliable dans l\'onglet À faire d\'une tâche'),
    (Icons.emoji_events_outlined, 'Résumé du jour : actions Gantt réalisées aujourd\'hui (via doneAt) — masqué si zéro'),
    (Icons.wifi_off_outlined, 'ORION hors ligne : message clair au lieu d\'une SocketException brute'),
    (Icons.view_column_outlined, 'Web Organisation : activités et routines en deux colonnes par domaine, avec icônes et bouton éditer'),
    (Icons.label_outlined, 'Web : onglet "Archives" renommé "Organisation"'),
    (Icons.repeat_rounded, 'Routines : fix persistance du +1 (clé composite activityId_yyyymmdd dans Firestore)'),
    (Icons.notifications_none_outlined, 'iOS : badge de notification réinitialisé à 0 au premier plan'),
  ]),
  _Entry('5.10', '23 mai 2026', [
    (Icons.build_outlined, 'Xcode Cloud : fix CocoaPods PurchasesHybridCommon (désactivation osxkeychain + forçage HTTPS)'),
  ]),
  _Entry('5.9', '23 mai 2026', [
    (Icons.touch_app_outlined, 'Projets iOS : tap action = éditer, appui long = réordonner, tap carte = ouvrir la tâche'),
    (Icons.emoji_events_outlined, 'Gamification : sous-actions projet branchées aux badges (comptage immédiat + persistance)'),
    (Icons.tune_outlined, 'Widget score : paliers basés sur les vraies actions Gantt + label "Actions du jour"'),
    (Icons.play_arrow_rounded, 'FAB restauré : ▶ Lancer activité (groupé par domaine, scrollable) + mini Routine & Action'),
    (Icons.radio_button_unchecked, 'Dashboard : anneaux épurés — chiffres + icône, sans texte'),
    (Icons.smart_toy_outlined, 'ORION : "cycles" → "actions stratégiques aujourd\'hui"'),
  ]),
  _Entry('5.8', '23 mai 2026', [
    (Icons.check_circle_outline, 'Projets iOS : section RÉALISÉ — projets avec toutes leurs tâches ok, au-dessus de Hors scope'),
  ]),
  _Entry('5.7', '23 mai 2026', [
    (Icons.delete_outline, 'Gantt web : suppression d\'un fichier depuis la fiche tâche'),
    (Icons.picture_as_pdf_outlined, 'Gantt web : upload PDF (< 700 Ko) avec aperçu intégré'),
    (Icons.notes_outlined, 'Gantt web : description de tâche éditable (tap sur le champ)'),
    (Icons.drive_file_rename_outline, 'Gantt web : renommer une phase en tapant sur la bande'),
  ]),
  _Entry('5.6', '23 mai 2026', [
    (Icons.touch_app_outlined, 'Focus : tap sur la tâche Gantt liée ouvre la fiche (appui long = délier)'),
    (Icons.upload_file_outlined, 'Gantt web : upload de fichiers dans une tâche (txt, md, html, json, images…)'),
  ]),
  _Entry('5.5', '23 mai 2026', [
    (Icons.add_circle_outline, 'Gantt web : bouton + dans la barre pour ajouter une tâche (titre, phase, dates, jalon)'),
    (Icons.layers_outlined, 'Gantt web : changer la phase d\'une tâche depuis la fiche (déplace visuellement la tâche)'),
    (Icons.palette_outlined, 'Gantt web : color picker sur la barre de chaque tâche (palette + couleur de la phase)'),
    (Icons.search_outlined, 'Archives web : recherche + filtre Tout / Actifs / Archivés'),
  ]),
  _Entry('5.4', '22 mai 2026', [
    (Icons.format_list_bulleted, 'Maintenant : sous-actions scrollables quand la liste est longue'),
    (Icons.bolt_outlined, 'ORION : fix erreur index Firestore sur les messages'),
  ]),
  _Entry('5.3', '22 mai 2026', [
    (Icons.timer_outlined, 'Dashboard : icônes dans les jauges (⏱ ↺ ⬡)'),
    (Icons.account_tree_outlined, 'Projets iOS : tâches correctement groupées par phase (fix groupLabel)'),
    (Icons.archive_outlined, 'Projets iOS : archiver/réactiver un projet depuis la fiche'),
    (Icons.view_agenda_outlined, 'Projets iOS : sections Hors scope et En veille'),
    (Icons.reorder, 'Projets iOS : appui long pour réordonner les sous-actions directement'),
    (Icons.play_arrow_outlined, 'Sheet démarrer : affichage du temps loggué aujourd\'hui par activité'),
    (Icons.link_outlined, 'Web : chemin MCP mis à jour (Paramètres → Personnaliser → Connecteurs)'),
  ]),
  _Entry('5.2', '22 mai 2026', [
    (Icons.dashboard_outlined, 'Dashboard : 3ème jauge Projets (tâches Gantt actives du jour)'),
    (Icons.move_to_inbox_outlined, 'Projets : changer de domaine depuis iOS et le web'),
    (Icons.light_mode_outlined, 'Gantt web : toggle clair/sombre déplacé dans la barre Semaine/Jour'),
    (Icons.star_outlined, 'Badges : 🎯 10/50/100 tâches Gantt validées (remplace les actions)'),
    (Icons.cleaning_services_outlined, 'Purge automatique des anciennes actions au démarrage'),
  ]),
  _Entry('5.1', '22 mai 2026', [
    (Icons.repeat_rounded, 'App bar : bouton Routines — liste du jour avec progression et incrément'),
    (Icons.smart_toy_outlined, 'ORION : intégré comme onglet natif dans la nav principale'),
    (Icons.cloud_outlined, 'Statut sync/Pro déplacé dans le menu ⋮'),
    (Icons.play_circle_outline, 'Maintenant : FAB Démarrer (remplace le bouton), clavier ORION corrigé'),
    (Icons.check_rounded, 'Projets : bouton Valider quand tâche à 100%, bouton + pour ajouter une action'),
    (Icons.task_outlined, 'Fiche projet : tap tâche → sheet détail avec swipe delete + reorder actions'),
    (Icons.close, 'Sheet activité : bouton fermer ajouté'),
  ]),
  _Entry('5.0', '22 mai 2026', [
    (Icons.account_tree_outlined, 'Nouvelle nav : Accueil · Projets · Maintenant · ORION'),
    (Icons.play_circle_outline, 'Maintenant : camembert du jour + flow démarrer (activité → tâche Gantt)'),
    (Icons.checklist_outlined, 'Maintenant actif : timer + tâche Gantt liée + sous-actions cochables'),
    (Icons.account_tree_outlined, 'Projets : bouton ▶ sur chaque tâche pour lancer directement'),
    (Icons.document_scanner_outlined, 'Fiche projet : documents liés au projet visibles en bas'),
    (Icons.today_outlined, 'Projets : phases affichées, tâches filtrées sur aujourd\'hui uniquement'),
  ]),
  _Entry('4.4', '22 mai 2026', [
    (Icons.picture_as_pdf_outlined, 'PDF Gantt : emojis retirés des titres et descriptions'),
  ]),
  _Entry('4.3', '22 mai 2026', [
    (Icons.image_outlined, 'Gantt : export PNG haute résolution (bouton 🖼 dans la barre de la grille)'),
    (Icons.delete_outline, 'Gantt : suppression d\'une tâche depuis la fiche'),
    (Icons.drag_handle, 'Gantt : réorganisation des actions par drag & drop'),
    (Icons.open_in_full, 'Gantt : dialog tâche plus large (720px)'),
    (Icons.light_mode_outlined, 'Gantt : bouton mode clair dans l\'app bar'),
  ]),
  _Entry('4.2', '22 mai 2026', [
    (Icons.account_tree_outlined, 'Objectifs unifiés — les projets Gantt sont désormais la seule source de vérité, accessibles via le bouton ⬡ dans la barre'),
    (Icons.flag_outlined, 'Suppression du système GTD Goals — plus de confusion entre deux systèmes'),
    (Icons.bolt_rounded, 'À faire : directement les actions, sans l\'onglet Objectifs'),
  ]),
  _Entry('4.1', '22 mai 2026', [
    (Icons.delete_outline, 'Web : suppression définitive d\'un projet archivé'),
    (Icons.help_outline_rounded, 'Web : schéma "Comment ça marche ?" dans le tab ORION'),
  ]),
  _Entry('4.0', '22 mai 2026', [
    (Icons.bolt_outlined, 'Web : fix actions rapides ORION (Analyser retards, Deadlines…) — envoyées au bon endpoint'),
  ]),
  _Entry('3.9', '22 mai 2026', [
    (Icons.account_tree_outlined, 'Objectifs : tâches Gantt actives enfin visibles — retards en rouge, tap ouvre la fiche projet'),
    (Icons.flag_outlined, 'Objectifs : fix clavier caché + erreur index Firestore'),
  ]),
  _Entry('3.8', '22 mai 2026', [
    (Icons.notifications_outlined, 'Notifications push ORION — reçois un message dès qu\'ORION génère un conseil (cron 6h, déclenchement manuel iOS ou web)'),
  ]),
  _Entry('3.7', '22 mai 2026', [
    (Icons.smart_toy_outlined, 'ORION : nouvelle page dédiée avec identité visuelle, onboarding et statut de plan (Gratuit ∞ · Pro)'),
    (Icons.message_outlined, 'Messages ORION redesignés : cards hiérarchisées, badge PRÉVU, réponse rapide en bas de page'),
  ]),
  _Entry('3.6', '22 mai 2026', [
    (Icons.sync_outlined, 'iOS : projets, goals et domaines synchronisés en temps réel depuis Firestore'),
    (Icons.account_tree_outlined, 'Fix : projets Gantt affichés même si le domaine n\'est pas encore connu localement'),
  ]),
  _Entry('3.5', '22 mai 2026', [
    (Icons.key_outlined, 'Fix : tokens API affichés correctement (Timestamp Firestore → DateTime)'),
  ]),
  _Entry('3.4', '22 mai 2026', [
    (Icons.smart_toy_outlined, 'ORION autonome : agent IA qui génère des messages contextuels toutes les 6h'),
    (Icons.tune, 'Configuration ORION : instructions persistantes + réponse directe depuis le menu'),
  ]),
  _Entry('3.3', '22 mai 2026', [
    (Icons.sync_outlined, 'iOS : projets Gantt mis à jour en temps réel dans la vue Objectifs'),
  ]),
  _Entry('3.2', '21 mai 2026', [
    (Icons.account_tree_outlined, 'Objectifs unifiés : tâches Gantt actives visibles dans la vue Objectifs iOS'),
    (Icons.check_box_outlined, 'Sous-actions des tâches Gantt cochables directement depuis les Objectifs'),
    (Icons.open_in_new, 'Tap sur une tâche → fiche projet complète avec scroll vers la tâche'),
  ]),
  _Entry('3.1', '21 mai 2026', [
    (Icons.account_tree_outlined, 'iOS : fiche projet Gantt — tâches, phases, retards, statuts modifiables'),
    (Icons.open_in_new, 'ORION : bouton "Voir la tâche" ouvre directement la fiche Gantt concernée'),
    (Icons.delete_outline, 'Suppression de documents depuis l\'app web et iOS'),
    (Icons.history, 'Fix : messages ORION fallback visibles dans l\'historique'),
  ]),
  _Entry('3.0', '21 mai 2026', [
    (Icons.smart_toy_outlined, 'Assistant ORION : messages contextuels avec effet typewriter, planifiés par Claude'),
    (Icons.notifications_outlined, 'Fallbacks autonomes : deadlines proches, jalons, retards — sans connexion Claude'),
    (Icons.history, 'Historique ORION : accès aux messages passés et à venir via le bouton robot 🤖'),
  ]),
  _Entry('2.9', '21 mai 2026', [
    (Icons.tune, 'Cibles de temps 100% manuelles — la progression automatique a été retirée'),
    (Icons.timer_outlined, 'Fiche activité : saisie directe de la cible quotidienne (en minutes)'),
  ]),
  _Entry('2.8', '21 mai 2026', [
    (Icons.delete_outline, 'Fix : supprimer une action en swipe est maintenant persistant après redémarrage'),
    (Icons.download_outlined, 'Bouton téléchargement (.html) dans la visionneuse de programmes depuis la liste des projets'),
  ]),
  _Entry('2.7', '19 mai 2026', [
    (Icons.smart_toy_outlined, 'Claude peut supprimer activités, actions et routines du plan'),
    (Icons.folder_outlined, 'Claude peut créer et supprimer des domaines de vie'),
    (Icons.sync_outlined, 'Sync : suppressions faites par Claude résistantes à la synchronisation'),
  ]),
  _Entry('2.6', '19 mai 2026', [
    (Icons.archive_outlined, 'Projets Gantt : mettre en veille et réactiver depuis le web app'),
    (Icons.add_circle_outline, 'Claude peut créer et modifier des activités directement'),
  ]),
  _Entry('2.5', '19 mai 2026', [
    (Icons.apple, 'Compte Apple : affichage clair de l\'état connecté + messages d\'erreur'),
    (Icons.key_outlined, 'Tokens API : UID Apple visible et copiable pour lier au web app'),
  ]),
  _Entry('2.4', '19 mai 2026', [
    (Icons.link_outlined, 'Liaison compte iOS ↔ web app : connecte-toi avec ton UID + token iOS sur productivitwo-app.web.app'),
    (Icons.smart_toy_outlined, 'Claude peut lire et modifier tes activités, routines et plan du jour via MCP'),
  ]),
  _Entry('2.3', '19 mai 2026', [
    (Icons.schedule_outlined, 'Routines temporelles : définis une période de début/fin sur chaque action récurrente'),
    (Icons.account_tree_outlined, 'Actions de tâche Gantt : ajoute le détail opérationnel à chaque tâche, planifiable au quotidien'),
  ]),
  _Entry('2.2', '19 mai 2026', [
    (Icons.key_outlined, 'Tokens API : génère des tokens pour envoyer des projets Gantt depuis Claude ou un coach'),
    (Icons.account_tree_outlined, 'Web app : visualise tes projets Gantt sur productivitwo-app.web.app'),
  ]),
  _Entry('2.1', '18 mai 2026', [
    (Icons.show_chart, 'Pro : heatmap 12 semaines + graphe couleur domaine dans la liste des activités'),
    (Icons.bar_chart, 'Fiche activité : graphe moyenne mobile ajouté au-dessus de la heatmap'),
    (Icons.rocket_launch_outlined, 'Onboarding : packs prêts-à-l\'emploi (Sport & Santé, Entrepreneur, Développement personnel)'),
    (Icons.apple, 'Compte Apple accessible directement depuis le menu'),
    (Icons.flag_outlined, 'Création d\'objectif : nouveau sheet fluide (même style que les actions)'),
    (Icons.grid_view_outlined, 'Heatmap activité : référence adaptée au max de l\'activité (min 5h)'),
  ]),
  _Entry('2.0', '18 mai 2026', [
    (Icons.flag_outlined, 'Objectifs : carte colorée par domaine, barre de progression et % visibles'),
    (Icons.library_add_outlined, 'Catalogue post-onboarding : ajouter domaines, activités et routines à tout moment'),
    (Icons.mail_outline, '"Suggérer une feature" dans le menu'),
    (Icons.grid_view_outlined, 'Heatmap activité : bug corrigé les lundis, référence fixe 5h'),
    (Icons.apple, 'Connexion Apple : sauvegarde et restauration sur plusieurs appareils'),
  ]),
  _Entry('1.9', '15 mai 2026', [
    (Icons.color_lens_outlined, 'Couleur personnalisée par domaine'),
    (Icons.cloud_outlined, 'Sync Firestore : données sauvegardées et synchronisées automatiquement'),
  ]),
  _Entry('1.8', '15 mai 2026', [
    (Icons.bar_chart_outlined, 'Barres 24h colorées par domaine dans l\'AppBar'),
    (Icons.repeat_outlined, 'Dashboard : widget Routines avec 3 barres par fréquence'),
    (Icons.tune, 'Création de routine : choix de la fréquence et de la cible'),
    (Icons.history, 'Actions reportées tracées en vue Semaine + score historique plus juste'),
  ]),
  _Entry('1.7', '15 mai 2026', [
    (Icons.grid_view_outlined, 'Heatmap : référence fixe 5h, tous les domaines visibles'),
    (Icons.folder_outlined, 'Activités : déplacer vers un autre domaine'),
    (Icons.trending_up_outlined, 'Notification "Objectif ajusté : +Xmin" à l\'arrêt d\'une activité'),
    (Icons.more_vert, 'AppBar allégée : stats, filtres et nouveautés dans le menu ⋮'),
  ]),
  _Entry('1.6', '15 mai 2026', [
    (Icons.layers_outlined, 'Routines multi-blocs : une même routine peut apparaître dans plusieurs blocs'),
    (Icons.water_drop_outlined, '"Boire de l\'eau" pré-configurée dans tous les blocs à l\'installation'),
    (Icons.compress, 'Blocs repliés par défaut à l\'ouverture de À faire'),
    (Icons.circle, 'Couleur de domaine sur les routines dans les blocs'),
    (Icons.play_circle_outlined, 'Toggle "Tout afficher" sans arrêter la session en cours'),
    (Icons.calendar_view_week_outlined, 'Vue Semaine : tap pour sheet d\'action (renommer, déplacer, bloc, activité, supprimer)'),
    (Icons.arrow_forward_outlined, 'Suppression du bouton "À demain" sur les routines'),
  ]),
  _Entry('1.5', 'mai 2026', [
    (Icons.view_day_outlined, 'Blocs journaliers : organiser les routines et actions par moment de la journée'),
    (Icons.report_outlined, 'Rapport temps : donut, barres 12 semaines, heatmap par domaine'),
    (Icons.rocket_launch_outlined, 'FAB lancement rapide d\'activité'),
  ]),
];

void showChangelogSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ChangelogSheet(),
  );
}

class _ChangelogSheet extends StatefulWidget {
  const _ChangelogSheet();

  @override
  State<_ChangelogSheet> createState() => _ChangelogSheetState();
}

class _ChangelogSheetState extends State<_ChangelogSheet> {
  int _tapCount = 0;
  Timer? _resetTimer;

  void _onTitleTap() {
    _resetTimer?.cancel();
    _tapCount++;
    if (_tapCount >= 7) {
      _tapCount = 0;
      final nowPro = ProManager.isPro;
      if (nowPro) {
        ProManager.deactivate();
      } else {
        ProManager.notifier.value = true;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nowPro ? '🔓 Mode Non-Pro activé' : '⭐ Mode Pro activé'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      _resetTimer = Timer(const Duration(seconds: 2), () => _tapCount = 0);
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          GestureDetector(
            onTap: _onTitleTap,
            child: Text(
              'Nouveautés',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final entry in _changelog) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v${entry.version}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  entry.date,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final (icon, text) in entry.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
