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
        what: 'Les fois où tu as fait quand même, alors que tu avais pointé « Flemme » ou « Mou ».',
        how: 'Pointe ton élan quand il est bas (carte MAINTENANT, Enchaîner), puis termine un bloc ou atteins une routine avant le pointage suivant : chaque chose faite compte une victoire. '
            'Paliers : 10, 50 et 200 victoires.',
      ),
    'vent-contraire' => (
        what: 'Une semaine solide traversée avec un élan bas.',
        how: '7 journées d’affilée à 80 % (la règle de Semaine solide) pendant lesquelles ton élan moyen pointé est à 2,5 ou moins. Au moins 3 pointages sur la semaine.',
      ),
    'maree-haute' => (
        what: '7 jours d’affilée avec un élan moyen « En forme » ou mieux.',
        how: 'Pointe ton élan chaque jour ; 7 jours pointés d’affilée à une moyenne de 4 ou plus. Les jours sans pointage sont enjambés, un jour sous 4 remet la suite à zéro.',
      ),
    'barometre' => (
        what: 'Le nombre de fois où tu as pointé ton élan.',
        how: 'Réponds à « Ton élan, là ? » : au plus trois fois par jour (matin, après-midi, soir). Paliers : 30, 100 et 365 pointages.',
      ),
    'deep-work' => (
        what: 'Des blocs de deep work choisis et menés au bout.',
        how: 'En mode En forme, lance « Deep work 90 min » (carte MAINTENANT ou « Bloc de 90 min » d’un objectif) et tiens le chrono au moins 60 min d’affilée '
            'sur cette source : le bloc compte. Un chrono long sans bloc de deep work (sommeil, séance, activité libre) ne compte pas. Paliers : 3, 10 et 30 blocs.',
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
