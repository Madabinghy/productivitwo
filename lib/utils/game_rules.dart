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

const kRuleActivityPace = GameRule('Lire une activité', [
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
]);

const kRuleModes = GameRule('Les modes', [
  RuleCard('🌙', 'Flemme', 'Petits pas : « 10 min, malgré tout ». Ce qui est fait malgré la flemme est compté à part.'),
  RuleCard('☀️', 'Normal', 'Le programme tel quel. Le mode repart en Normal chaque matin.'),
  RuleCard('⚡', 'En forme', 'Les gros morceaux d’abord, deep work proposé.'),
  RuleCard('📈', 'Ton élan', 'Chaque changement de mode est noté : c’est ce qui trace ton élan dans le temps.'),
]);

const kRuleObjectivesToday = GameRule('Objectifs aujourd’hui', [
  RuleCard('🔢', 'Le chiffre du jour', 'Ce que tes objectifs demandent aujourd’hui : temps du jour, routines, blocs, relevés. Le trait = l’heure qu’il est.'),
  RuleCard('🧭', 'Où j’en suis', 'Une ligne par objectif : son rythme de la semaine et ce qui reste aujourd’hui. Touche-la pour la fiche.'),
  RuleCard('👉', 'À faire', 'Une seule liste, le plus utile d’abord : l’objectif le plus en retard passe devant. Un bouton par geste.'),
]);
