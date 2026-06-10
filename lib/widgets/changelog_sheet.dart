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
