import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_match.dart';

// ─── MÉTA-CONTEXTES HORAIRES DES ROUTINES ────────────────────────────────────
//
// « On sait que l'hygiène du soir, c'est le soir. On sait que boire de l'eau,
// c'est tout au long de la journée. » Certaines routines portent une
// méta-intention ÉVIDENTE, avec sa fenêtre horaire logique — le catalogue les
// fixe en dur (matché sur le nom, accents/casse repliés), et l'utilisateur
// peut TOUJOURS ajuster à son contexte (Activity.timeContext, fiche routine).
//
// Règles de préséance, du plus fort au plus faible :
//   1. Override utilisateur (Activity.timeContext) — sa réalité à lui ;
//   2. Heure habituelle MESURÉE (typicalMinuteOf) — le réel bat le présumé ;
//   3. Archétype du catalogue — le bon sens par défaut ;
//   4. Rien — la routine est libre.
// Consommé par : renégociation structurelle (jamais « Hygiène du soir à
// midi »), combleurs sans historique, proposition de programme (serveur,
// miroir TS dans functions/src/routine_context.ts).

class TimeContextDef {
  final String key;
  final String label;

  /// Fenêtres en minutes depuis minuit — vide = aucune contrainte.
  final List<(int, int)> windows;

  /// Heure de pose par défaut quand il faut choisir UNE heure.
  final int anchorMin;
  const TimeContextDef(this.key, this.label, this.windows, this.anchorMin);

  bool allows(int minuteOfDay) {
    if (windows.isEmpty) return true;
    for (final (a, b) in windows) {
      if (minuteOfDay >= a && minuteOfDay < b) return true;
    }
    return false;
  }
}

const kTimeContexts = <String, TimeContextDef>{
  'morning': TimeContextDef('morning', 'Matin', [(5 * 60 + 30, 11 * 60)], 7 * 60 + 30),
  'midday': TimeContextDef('midday', 'Midi', [(11 * 60 + 30, 14 * 60)], 12 * 60 + 30),
  'afternoon':
      TimeContextDef('afternoon', 'Après-midi', [(14 * 60, 19 * 60)], 15 * 60 + 30),
  'evening':
      TimeContextDef('evening', 'Soir', [(19 * 60, 23 * 60 + 30)], 21 * 60),
  'meal': TimeContextDef('meal', 'Repas',
      [(11 * 60 + 30, 13 * 60 + 30), (18 * 60 + 30, 20 * 60 + 30)], 12 * 60),
  'day': TimeContextDef('day', 'Journée', [(7 * 60, 20 * 60)], 10 * 60),
  'allday':
      TimeContextDef('allday', 'Toute la journée', [(6 * 60, 23 * 60)], 9 * 60),
  'any': TimeContextDef('any', 'Libre', [], 10 * 60),
};

class RoutineArchetype {
  final List<String> keywords; // repliés (foldName)
  final String contextKey;
  final String metaIntention; // l'intention DE LA ROUTINE, pas du domaine
  const RoutineArchetype(this.keywords, this.contextKey, this.metaIntention);
}

/// Le catalogue : uniquement les évidences — dans le doute, pas d'archétype
/// (la routine reste libre plutôt que mal contrainte).
const kRoutineArchetypes = <RoutineArchetype>[
  RoutineArchetype(
      ['hygiene du soir', 'routine du soir', 'routine soir', 'coucher', 'skincare', 'demaquill'],
      'evening',
      'clore la journée proprement'),
  RoutineArchetype(
      ['hygiene du matin', 'routine du matin', 'routine matin', 'miracle morning', 'vitamine'],
      'morning',
      'lancer la journée du bon pied'),
  RoutineArchetype(
      ['boire', 'eau', 'hydrat'], 'allday', 's\'hydrater tout au long de la journée'),
  RoutineArchetype(
      ['cuisin', 'repas', 'gamelle', 'meal prep', 'batch cooking'],
      'meal',
      'manger équilibré aux heures de repas'),
  RoutineArchetype(
      ['sport', 'muscu', 'pompes', 'traction', 'course', 'running', 'footing', 'velo', 'natation', 'etirement', 'yoga', 'gym', 'entrainement'],
      'day',
      'bouger dans la journée'),
  RoutineArchetype(
      ['menage', 'vaisselle', 'rangement', 'lessive'], 'day', 'tenir l\'espace de vie'),
  RoutineArchetype(['sommeil', 'dormir'], 'evening', 'préserver le sommeil'),
];

/// L'archétype de [name] — null si aucune évidence (jamais deviné dans le doute).
RoutineArchetype? routineArchetype(String name) {
  final n = foldName(name.trim());
  if (n.length < 3) return null;
  for (final a in kRoutineArchetypes) {
    for (final k in a.keywords) {
      if (n.contains(k)) return a;
    }
  }
  return null;
}

/// Contexte effectif : override utilisateur d'abord, archétype sinon, null si
/// rien — voir la préséance en tête de fichier. (L'heure MESURÉE est arbitrée
/// par les consommateurs : le réel bat toujours le catalogue.)
TimeContextDef? effTimeContextOf(Activity a) {
  final overrideKey = a.timeContext;
  if (overrideKey != null && kTimeContexts.containsKey(overrideKey)) {
    return kTimeContexts[overrideKey];
  }
  final arch = routineArchetype(a.name);
  return arch != null ? kTimeContexts[arch.contextKey] : null;
}

/// La méta-intention de la routine (« clore la journée proprement ») — à citer
/// À LA PLACE de l'intention du domaine quand elle existe : l'intention du
/// domaine (« manger équilibré ») n'a rien à faire sur une routine d'hygiène.
String? metaIntentionOf(Activity a) => routineArchetype(a.name)?.metaIntention;

/// Minute représentative d'une tranche de renégociation (matin/midi/aprem/soir)
/// — pour tester si un contexte l'autorise.
int bucketProbeMin(String bucket) => switch (bucket) {
      'matin' => 8 * 60,
      'midi' => 12 * 60 + 30,
      'apres_midi' => 15 * 60 + 30,
      'soir' => 20 * 60 + 30,
      _ => 12 * 60,
    };

/// La tranche est-elle compatible avec le contexte de la routine ?
/// (null = routine libre → tout est permis.)
bool contextAllowsBucket(TimeContextDef? ctx, String bucket) =>
    ctx == null || ctx.allows(bucketProbeMin(bucket));

/// Tranche « naturelle » d'un contexte (pour proposer un essai honnête quand
/// aucun créneau n'est prouvé) : celle qui contient son heure d'ancrage.
String bucketOfContext(TimeContextDef ctx) {
  final m = ctx.anchorMin;
  if (m < 11 * 60 + 30) return 'matin';
  if (m < 14 * 60) return 'midi';
  if (m < 19 * 60) return 'apres_midi';
  return 'soir';
}
