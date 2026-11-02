/// Matière des badges (2026-10) : à quoi correspond chaque badge et comment
/// l'obtenir, en français, au présent, sans jugement. Textes du système de
/// design « Badges Productivitwo » (section Catalogue). `name` = nom de la
/// routine ou de l'objectif porteur pour les familles à un badge par objet.
({String what, String how}) badgeTexts(String id, {String name = ''}) {
  if (id.startsWith('serie-')) {
    return (
      what: 'Les jours d’affilée où « $name » atteint sa cible du jour.',
      how: 'Coche « $name » jusqu’à sa cible chaque jour vécu (la journée bascule à l’heure réglée dans Paramètres, pas à minuit). '
          'Un jour manqué remet la série à zéro ; le palier atteint reste acquis. Paliers : 3, 7, 21, 66 et 100 jours.',
    );
  }
  if (id == 'heures-total') {
    return (
      what: 'Toutes les heures que tu as chronométrées, toutes activités confondues : le chemin des 10 000 heures.',
      how: 'Chaque minute de chrono compte, même une fois tes enjeux du jour gagnés : rien ne se perd, rien ne se remet à zéro. '
          'Paliers : 1 000, 5 000, 10 000, 25 000 et 50 000 heures.',
    );
  }
  if (id == 'heures-annee') {
    return (
      what: 'Toutes les heures chronométrées depuis le 1er janvier, toutes activités confondues.',
      how: 'Chaque minute de chrono compte ; la carte repart chaque 1er janvier, les paliers atteints restent dans ta récolte. '
          'Paliers : 100, 500, 1 000, 1 500, 2 000 et 2 500 heures.',
    );
  }
  if (id.startsWith('heures-')) {
    return (
      what: 'Les heures de chrono passées sur « $name », depuis toujours.',
      how: 'Lance le chrono sur « $name ». Le temps en plus de ton minimum compte aussi : c’est de l’avance pour la suite. '
          'Paliers : 5, 20, 50, 100, 250, 500, 1 000 et 10 000 heures.',
    );
  }
  if (id.startsWith('fois-')) {
    return (
      what: 'Le nombre de fois où tu as fait « $name », depuis toujours.',
      how: 'Chaque +1 compte, y compris au-delà de la cible du jour : la deuxième vaisselle du soir fait avancer la carte. '
          'Paliers : 10, 50, 100, 250, 500 et 1 000 fois.',
    );
  }
  if (id.startsWith('temps-')) {
    return (
      what: 'Les heures de chrono passées sur les activités engagées de l’objectif « $name », depuis son début.',
      how: 'Lance le chrono sur une activité engagée de cet objectif (depuis MAINTENANT, un bloc du programme ou le segment Objectifs). '
          'Les minutes s’additionnent, rien ne se perd. Paliers : 100, 500 et 1 000 heures.',
    );
  }
  return switch (id) {
    'premiere-cible' => (
        what: 'Ton premier objectif marqué atteint.',
        how: 'Dans la fiche d’un objectif, touche « Atteint » quand il l’est. Un seul suffit, une fois pour toutes.',
      ),
    'trajectoire' => (
        what: 'Des semaines d’affilée où un objectif suit son plan : les moyens (temps engagé) et le résultat (dernier relevé) sont sur la trajectoire ou en avance.',
        how: 'Chaque lundi, la trajectoire de chaque objectif est relue à cette date. Tiens le temps engagé et note tes relevés : 4, 8 puis 12 semaines consécutives sur le plan. '
            'Une semaine en retard remet la suite à zéro, le palier atteint reste.',
      ),
    'releve-fidele' => (
        what: 'Des relevés de métrique notés sans en manquer un.',
        how: 'Note le relevé de ton objectif au rythme réglé (tous les 3, 7 ou 14 jours), avec un jour de marge. 8 relevés d’affilée, puis 20.',
      ),
    'cible-atteinte' => (
        what: 'Un objectif terminé avec sa métrique à la cible.',
        how: 'Donne une métrique chiffrée à l’objectif, note tes relevés, et marque-le « Atteint » quand le dernier relevé touche la cible.',
      ),
    'journee-parfaite' => (
        what: 'Une journée où toutes les routines dues sont atteintes et tous les blocs du programme sont faits.',
        how: 'Une journée vécue avec au moins une routine ou un bloc, où rien ne manque : 100 % des routines quotidiennes atteintes et 100 % des blocs faits '
            '(hors miroirs d’agenda, sautés et annulés). Une seule journée suffit.',
      ),
    'montre-suisse' => (
        what: 'Une journée où chaque activité est au rythme : toutes les activités avec un minimum vital ont fait l’attendu à ce jour.',
        how: 'L’attendu, c’est le minimum vital × les jours écoulés de ta fenêtre de budget (semaine ou quinzaine), le repère des barres de Domaines. '
            'Comptée à la bascule de journée. Domaines en veille hors compte ; un jour sans activité à tenir ne compte ni pour ni contre. '
            'Paliers : 5, 20, 50, 100 journées.',
      ),
    'metronome' => (
        what: 'Une journée où toutes les routines du jour sont atteintes : la moitié routines de la Journée parfaite, sans les blocs.',
        how: 'Toutes les routines quotidiennes dues atteintes avant la bascule. Routines acquises et domaines en veille hors compte ; '
            'un jour sans routine due ne compte ni pour ni contre. Paliers : 5, 20, 50, 100 journées.',
      ),
    'semaine-solide' => (
        what: '7 journées d’affilée à 80 % au moins sur les routines et sur les blocs.',
        how: 'Chaque jour, atteins au moins 80 % de tes routines quotidiennes et termine au moins 80 % de tes blocs. Une journée sans rien à tenir ne compte ni pour ni contre. '
            'Une journée sous 80 % remet la suite à zéro.',
      ),
    'mois-solide' => (
        what: '30 journées d’affilée à 80 % au moins sur les routines et sur les blocs.',
        how: 'La même règle que Semaine solide, tenue 30 jours de suite. Les journées neutres sont enjambées.',
      ),
    'malgre-tout' => (
        what: 'Les fois où tu as fait quand même, alors que tu étais en mode Flemme (ou pointé « Flemme » / « Mou »).',
        how: 'En mode Flemme, chacun de ces gestes vaut une victoire : un chrono lancé et tenu 10 min (« 10 min, malgré tout » comme « Tout le bloc »), une action cochée, un bloc fait, une routine atteinte. Les besoins de base (sommeil, sieste, repas) ne comptent pas ; cuisiner, si. '
            'Paliers : 10, 50 et 200 victoires.',
      ),
    'vent-contraire' => (
        what: 'Une semaine solide traversée en mode Flemme.',
        how: '7 journées d’affilée à 80 % (la règle de Semaine solide) pendant lesquelles ton élan moyen est à 2,5 ou moins. Le mode Flemme vaut 2, Normal 3, En forme 4 : déclare-toi Flemme au moins 3 fois sur la semaine, sans jamais passer En forme. '
            'Un jour en Normal sans rien poser ne compte ni pour ni contre.',
      ),
    'maree-haute' => (
        what: '7 jours d’affilée en mode En forme (élan moyen 4 ou plus).',
        how: 'Déclare-toi En forme (pilule de MAINTENANT) 7 jours d’affilée : chaque mode posé est un pointage d’élan (Flemme 2, Normal 3, En forme 4). Les jours sans rien de posé sont enjambés ; '
            'un jour dont la moyenne tombe sous 4 (En forme le matin puis Flemme le soir, par exemple) remet la suite à zéro.',
      ),
    'barometre' => (
        what: 'Le nombre de fois où tu as pointé ton élan, par la question ou par le mode.',
        how: 'Réponds à « Ton élan, là ? » ou pose un mode (Flemme · Normal · En forme) : un pointage par créneau (matin, après-midi, soir), le dernier posé remplace. Paliers : 30, 100 et 365 pointages.',
      ),
    'deep-work' => (
        what: 'Des blocs de deep work choisis et menés au bout.',
        how: 'En mode En forme, lance « Deep work 90 min » (carte MAINTENANT ou « Bloc de 90 min » d’un objectif) et tiens le chrono au moins 60 min d’affilée '
            'sur cette source : le bloc compte. Un chrono long sans bloc de deep work (sommeil, séance, activité libre) ne compte pas. Paliers : 3, 10 et 30 blocs.',
      ),
    'saisons' => (
        what: 'Des saisons de six semaines où au moins deux des trois chasses ont été attrapées.',
        how: 'Ouvre une saison depuis l’onglet Objectifs : choisis trois chasses, figées pour six semaines (tu peux en lâcher une, pas la remplacer). '
            'Attrape au moins deux paliers visés avant la fin : la saison est réussie. Paliers : 1, 4 et 8 saisons.',
      ),
    'semaines-tenues' => (
        what: 'Les semaines d’affilée où le contrat est tenu : au moins 80 % des routines engagées, du lundi au dimanche.',
        how: 'Tiens les routines rattachées à tes objectifs (toutes les routines s’il n’y en a aucune) : une semaine compte quand la moyenne de leurs parts faites atteint 80 %. '
            'Les jours en veille réduisent la cible ; une semaine sans rien à tenir est enjambée. Chaque semaine tenue forge une braise. Paliers : 4, 12, 26 et 52 semaines.',
      ),
    'reprise' => (
        what: 'Une routine coupée deux jours ou plus, puis tenue trois jours d’affilée.',
        how: 'Après au moins deux jours sans atteindre une routine, atteins-la trois jours de suite : la reprise compte. Un seul jour manqué se rattrape avec une braise, '
            'pas par une reprise ; les jours gelés par une veille ne comptent pas comme manqués. Paliers : 1, 5 et 15 reprises.',
      ),
    'enchaineur' => (
        what: 'Des sessions du mode Enchaîner où tu as fait au moins trois choses d’affilée.',
        how: 'Lance « Enchaîner » depuis MAINTENANT et fais au moins 3 choses dans la même session : elle compte, que tu la mènes au bout ou que tu sortes avant. '
            'Sortir pour un détour ne la perd pas : « Reprendre l’enchaînement » sur MAINTENANT pendant 45 min. Paliers : 5, 20 et 50 sessions.',
      ),
    'plein-jour' => (
        what: 'Une session d’Enchaîner du premier au dernier bloc du programme du jour.',
        how: 'Commence Enchaîner avant le premier bloc du programme, et mène la file jusqu’à ce que le dernier bloc soit épuisé. Une seule fois suffit.',
      ),
    'actions' => (
        what: 'Le nombre d’actions marquées faites, dans tes projets et tes activités.',
        how: 'Coche des actions : dans Actions, dans un bloc, dans Enchaîner, dans Réalisation. Une action décochée puis recochée ne compte qu’une fois. '
            'Paliers : 10, 50, 100, 250, 500, 1 000, 5 000 et 10 000.',
      ),
    _ => (what: '', how: ''),
  };
}
