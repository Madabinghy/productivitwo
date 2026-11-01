/// Règles du jeu expliquées là où elles servent (2026-10-30, retour user :
/// « pas un tuto au fond des paramètres »). Chaque règle = quelques cartes
/// courtes ouvertes par un ⓘ (`InfoDot`, `widgets/info_dot.dart`).
class RuleCard {
  final String emoji;
  final String title;
  final String text;
  const RuleCard(this.emoji, this.title, this.text);
}

class GameRule {
  final String title;
  final List<RuleCard> cards;
  const GameRule(this.title, this.cards);
}

const kRuleBlockVsFocus = GameRule('Bloc ou jour visé ?', [
  RuleCard('📅', 'Un bloc est un engagement',
      'Tu réserves une heure. Le bloc compte pour la journée parfaite et pour les badges.'),
  RuleCard('⚖️', 'Il pèse tant qu’il est là',
      'Non fait, il compte contre ta journée jusqu’à ce que tu le fasses, le déplaces ou le supprimes.'),
  RuleCard('☀️', 'Viser un jour est une intention',
      'L’action est proposée ce jour-là, en tête d’Actions et des blocs de son activité. Aucune heure réservée.'),
  RuleCard('🌱', 'Pas faite ? Pas grave',
      'Elle passe « à re-viser », jamais en retard, et ne coûte rien à ta journée.'),
]);

const kRulePerfectDay = GameRule('Journée parfaite', [
  RuleCard('✅', 'Tout ce que tu as posé',
      'Une journée est parfaite quand chaque routine quotidienne est atteinte et chaque bloc du programme fait.'),
  RuleCard('🧹', 'Ce qui ne compte pas',
      'Les actions visées et les miroirs de ton agenda. Un bloc supprimé ou déplacé ne compte plus.'),
  RuleCard('🔥', 'Elle forge une braise',
      'Chaque journée parfaite met une braise de côté, trois au plus.'),
]);

const kRuleLetGo = GameRule('Retirer un bloc', [
  RuleCard('✋', 'Lâcher n’est pas tricher', 'Tu avais décidé, tu changes d’avis. Tu le dis, et le bloc compte comme non fait. Honnête, et terminé.'),
  RuleCard('⛔', 'Empêché ne compte pas',
      'Malade, imprévu, annulé : comme si le bloc n’avait jamais été prévu. À toi d’être honnête.'),
  RuleCard('📊', 'Ce que ça change',
      'Un bloc lâché fait perdre la journée parfaite et pèse sur Cap tenu. Montre suisse, Métronome et séries ne bougent pas.'),
  RuleCard('➡️', 'Une case perdue, pas la journée', 'Ce qui suit compte autant qu’avant. C’est maintenant que ça se joue.'),
]);

const kRuleEmbers = GameRule('Braises', [
  RuleCard('🔥', 'Gagner une braise', 'Une journée parfaite forge une braise. Ta réserve en garde trois.'),
  RuleCard('🕯️', 'Rallumer une série',
      'Une série de routine cassée hier peut être rallumée avec une braise, le lendemain seulement.'),
  RuleCard('🎯', 'À une condition',
      'Atteindre la routine aujourd’hui. Sinon la braise n’est pas dépensée.'),
  RuleCard('⏳', 'Une fois par mois',
      'Une même série ne se rallume qu’une fois tous les 30 jours. Le jour comblé compte pour la série, pas pour la journée parfaite.'),
]);

const kRuleSeries = GameRule('Séries et flammes', [
  RuleCard('🔥', 'Une série', 'Une routine quotidienne atteinte chaque jour, sans trou, jusqu’à hier.'),
  RuleCard('🌙', 'La journée en cours',
      'Elle ne compte qu’une fois close. Manquer un jour casse la série.'),
  RuleCard('🛡️', 'L’écusson',
      'Chaque routine a son badge de série : paliers 3 · 7 · 21 · 66 · 100 jours. Touche-le pour le voir.'),
]);

const kRuleStakes = GameRule('Ta journée en enjeux', [
  RuleCard('🎲', 'En jeu', 'Chaque ligne est un geste et ce qu’il rapporte : une série, un palier, un objectif au rythme, une prépa.'),
  RuleCard('🌙', 'Se perd ce soir', 'En tête, ce qui sera perdu si rien n’est fait avant la fin de la journée.'),
  RuleCard('✔️', 'Gagné · perdu', 'Le tableau compte ce que la journée a déjà gagné ou laissé filer.'),
]);

const kRuleActivityPace = GameRule('Lire une activité · vue Tout', [
  RuleCard('⭕', 'L’anneau = aujourd’hui', 'Le temps fait aujourd’hui face à ton objectif du jour. Plein vert : atteint.'),
  RuleCard('📏', 'La barre = la semaine', 'Le temps fait depuis lundi. Le bout de la barre est le minimum de toute la semaine.'),
  RuleCard('│', 'Le trait = attendu à ce jour',
      'Objectif du jour × jours écoulés, aujourd’hui compris. Au-delà du trait : vert. En deçà : ambre.'),
]);

const kRuleWatch = GameRule('Montre suisse', [
  RuleCard('⌚', 'Sept jours glissants',
      'Chaque soir, chaque activité à minimum doit avoir fait 7 fois son minimum sur les 7 derniers jours.'),
  RuleCard('📏', 'La barre', 'Gris : les 6 jours passés. Vert : aujourd’hui. Le bout de la barre : 7 × le minimum.'),
  RuleCard('🗓', 'Pas de mur le lundi', 'Le week-end compte encore le lundi, et une grosse séance couvre les jours d’après.'),
  RuleCard('🌅', 'Demain', 'Ce soir, le jour le plus ancien sort de la fenêtre : la fiche annonce ce qu’il faudra demain.'),
  RuleCard('🎚', 'Tes minimums',
      'Un minimum, c’est ce que tu veux tenir chaque semaine. Une activité occasionnelle n’en a pas besoin : retire-le ou cale-le sur ce que tu fais vraiment.'),
]);

const kRuleModes = GameRule('Les modes', [
  RuleCard('🌙', 'Flemme', 'Petits pas : « 10 min, malgré tout ». Démarrer et tenir 10 min, cocher une action, finir un bloc ou une routine : chaque geste est une victoire sur la flemme.'),
  RuleCard('☀️', 'Normal', 'Le programme tel quel. Le mode repart en Normal chaque matin.'),
  RuleCard('⚡', 'En forme', 'Les gros morceaux d’abord, deep work proposé.'),
  RuleCard('📈', 'Ton élan', 'Chaque changement de mode est noté : c’est ce qui trace ton élan dans le temps.'),
]);

const kRuleGuerilla = GameRule('La guérilla', [
  RuleCard('⚡', 'La flemme ou moi', 'Pas bien, mais debout. L’app choisit, tu enchaînes des coups de 5 min au plus : une routine, 5 min sur une action. Pas ça ? On passe, sans question.'),
  RuleCard('💧', 'Un point d’étape', 'Tous les 3 coups : un verre d’eau, trois respirations. Moins bien ? On s’arrête, rien n’est perdu.'),
  RuleCard('📈', 'Avant, après', 'Tu notes ton corps de 1 à 5 au début et à la fin. Au fil des guérillas, tu vois si ça te fait remonter.'),
  RuleCard('🏅', 'Le badge', 'Une guérilla compte dès 3 coups faits. Fièvre, vertiges, douleur forte : repos, ça compte aussi.'),
]);

const kRuleOffensive = GameRule('L’offensive', [
  RuleCard('🎯', 'Tu choisis le front', 'Un projet, ou « tout mélanger » : la prochaine action de chaque projet, la plus en retard d’abord. L’app enchaîne les actions, une étape en avant.'),
  RuleCard('⏱️', 'Des coups de 10 ou 15 min', 'Au bout du minuteur, le coup est gagné, même sans finir l’action. Le chrono tourne sur l’activité liée.'),
  RuleCard('☕', 'Tous les 3 coups', 'Trois minutes debout. Puis : à fond, je ralentis (coups de 10 min) ou c’est bon pour aujourd’hui.'),
  RuleCard('🏅', 'Le badge', 'Une offensive compte dès 3 coups gagnés. Le deep work 90 min reste à part : un seul gros bloc.'),
]);

const kRuleSniper = GameRule('Le Sniper', [
  RuleCard('◎', 'Le temps exact', 'L’app calcule ce qui fait tomber chaque enjeu du jour : 37 min de Lecture si c’est pile ce qui couvre la Montre suisse, +1 pour la dernière routine du Métronome.'),
  RuleCard('🎯', 'L’ordre', 'Ce qui se perd ce soir d’abord, puis les paliers de ce soir, puis ce qui rapporte le plus par minute. Seulement ce qui tient avant ton prochain rendez-vous.'),
  RuleCard('🌊', 'Sans décision', 'Un tir à la fois, minuteur pile et alarme. Touché : deux minutes de pause, puis le tir suivant part tout seul. Dépasser ne sert à rien.'),
  RuleCard('🏅', 'Le badge', 'Une session compte quand toutes les cibles visées tombent, au moins 3. Écarte une cible au départ plutôt que de la passer en route.'),
]);

const kRuleObjectivesToday = GameRule('Objectifs aujourd’hui', [
  RuleCard('🔢', 'Le chiffre du jour', 'Ce que tes objectifs demandent aujourd’hui : temps du jour, routines, blocs, relevés. Le trait = l’heure qu’il est.'),
  RuleCard('🧭', 'Où j’en suis', 'Une ligne par objectif : son rythme de la semaine et ce qui reste aujourd’hui. Touche-la pour la fiche.'),
  RuleCard('👉', 'À faire', 'Une seule liste, le plus utile d’abord : l’objectif le plus en retard passe devant. Un bouton par geste.'),
]);

const kRuleRecharge = GameRule('La recharge', [
  RuleCard('🌙', 'La nuit sort des modes', 'Pendant la recharge, ni Flemme, ni Normal, ni En forme : ce temps ne compte ni dans ton élan, ni comme de la flemme.'),
  RuleCard('⏰', 'Quand elle démarre', 'Quand tu lances le chrono Sommeil, jamais toute seule. Une heure avant ton bloc Sommeil, la carte te propose de poser demain puis « Je vais me coucher ».'),
  RuleCard('🚶', 'Pas encore couché ?', 'Le bouton te remet dans ton mode. Si c’est le chrono Sommeil qui tourne, il l’arrête aussi (moins de 5 min = lancé par erreur, retiré).'),
  RuleCard('☀️', 'Au réveil', 'La carte te demande comment tu démarres : Flemme, Normal ou En forme. Sans choix, ton premier geste (+1, chrono) te met en Normal.'),
]);

const kRuleParole = GameRule('Parole tenue', [
  RuleCard('🤝', 'Donner sa parole', 'La veille, au moins 3 actions que tu t’engages à finir le lendemain. Le plus simple : l’étape « Ta parole pour demain » de Planifier demain.'),
  RuleCard('✅', 'La tenir', 'Toutes faites avant la fin de la journée = une journée de Parole tenue. Le badge compte les journées tenues : un jour raté ne remet rien à zéro.'),
  RuleCard('➕', 'Ajoutées le jour même', 'Une action visée dans la journée reste utile, mais ne compte pas pour la parole : seule la parole donnée la veille compte.'),
  RuleCard('↪️', 'Pas possible ?', 'Vise-la un autre jour : elle reste dans la parole d’aujourd’hui et la journée ne compte pas. Tes journées déjà gagnées restent acquises.'),
]);

const kRuleCoachSharing = GameRule('Ce que voit ton coach', [
  RuleCard('🔒', 'Rien sans toi', 'Accepter le lien ne partage rien. Tu choisis les domaines, puis chaque type d’information.'),
  RuleCard('👁', 'Ce qu’il voit', 'Des faits mesurés par l’app : engagements, temps, badges, et ce que tu actives en plus (état, jeux, sommeil).'),
  RuleCard('🌙', 'Le sommeil, à part', 'C’est intime : il reste privé tant que tu ne l’actives pas, même si tout le reste est partagé.'),
  RuleCard('🧱', 'Les domaines fermés', 'Un domaine non partagé n’apparaît nulle part : pas de nom d’activité, pas de total, pas de série.'),
  RuleCard('↩️', 'Révocable', 'Tu modifies ou coupes le partage quand tu veux. Ton coach perd l’accès tout de suite, historique compris.'),
]);
