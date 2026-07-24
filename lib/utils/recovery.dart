import 'package:productivitwo_v1/models.dart';

// ─── REMOTIVATION APRÈS 2 JOURS À PLAT (tour 25) — logique pure, 0 LLM ───────
//
// Jamais de morale, jamais de citation motivationnelle : des faits, une
// question, une pente douce. La copy varie SANS LLM : chaque étape a un pool
// de ≥ 3 formulations (mêmes faits, angles différents), sélection déterministe
// seedée (date + étape) ; la dernière variante servie n'est jamais resservie
// sur deux séquences consécutives ; une variante dont un placeholder manque
// est écartée du tirage — jamais de trou rempli.

/// La séquence ne se rejoue jamais avant 72 h.
const Duration kRecoveryCooldown = Duration(hours: 72);

/// Fenêtre de repos après un « Pas maintenant » (reproposée 1×).
const Duration kRecoveryDeclineRest = Duration(hours: 2);

/// Un jour « à plat » : energyState `low` DÉCLARÉ ce jour-là, OU dérivé —
/// < 30 min logguées ET 0 bloc non-routine `done`. Le dérivé exige un
/// programme réel (≥ 1 bloc posé) : un jour sans système (vacances, nouveau
/// compte) n'est pas un jour à plat.
bool isFlatDay(DateTime day, DailySchedule? sched, List<Session> sessions) {
  if (sched?.energyState?.level == 'low') return true;
  final blocks =
      sched?.blocks.where((b) => b.status != 'deleted').toList() ?? const [];
  if (blocks.isEmpty) return false;
  final doneNonRoutine = blocks.any((b) =>
      b.status == 'done' && !b.isPrep && b.category != 'routine' &&
      b.category != 'break');
  if (doneNonRoutine) return false;
  var logged = 0;
  for (final s in sessions) {
    if (!_sameDay(s.startAt, day)) continue;
    logged += (s.endAt ?? s.startAt).difference(s.startAt).inMinutes;
  }
  return logged < 30;
}

/// Entrée du flux : 2 jours consécutifs à plat (J-1 et J-2), au matin du
/// jour 3 (dès 8 h), jamais rejoué avant 72 h.
bool recoveryTriggered(
  DateTime now, {
  required DailySchedule? yesterday,
  required DailySchedule? dayBefore,
  required List<Session> sessions,
  DateTime? lastRecoveryAt,
}) {
  if (now.hour < 8) return false;
  if (lastRecoveryAt != null &&
      now.difference(lastRecoveryAt) < kRecoveryCooldown) {
    return false;
  }
  final d1 = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  final d2 = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 2));
  return isFlatDay(d1, yesterday, sessions) &&
      isFlatDay(d2, dayBefore, sessions);
}

/// « Ce qui a tenu quand même » : uniquement des faits `done` des 2 jours à
/// plat — check-ins faits, routines validées. Rangée omise si vide.
List<String> heldFacts(DateTime now, DailySchedule? yesterday,
    DailySchedule? dayBefore, AppState st) {
  final facts = <String>[];
  final checkins = [yesterday, dayBefore]
      .where((d) => d?.reviewedAt != null)
      .length;
  if (checkins > 0) {
    facts.add(checkins == 2
        ? 'les deux check-ins'
        : 'un check-in sur deux');
  }
  var routineDays = 0;
  for (var i = 1; i <= 2; i++) {
    final d = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: i));
    if (st.habitHits.any((h) => _sameDay(h.ts, d))) routineDays++;
  }
  if (routineDays > 0) {
    facts.add(routineDays == 2
        ? 'des routines les deux jours'
        : 'des routines un jour sur deux');
  }
  return facts;
}

/// Statistique « check-ins tenus » des 2 jours à plat (carte 25a).
int checkinsHeld(DailySchedule? yesterday, DailySchedule? dayBefore) =>
    [yesterday, dayBefore].where((d) => d?.reviewedAt != null).length;

// ── Pools de copy (FR, du handoff — V1 = la maquette) ────────────────────────

class RecoveryCopy {
  final String text;
  final int variant;
  const RecoveryCopy(this.text, this.variant);
}

String _dayFr(DateTime d) => const [
      'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
    ][d.weekday - 1];

/// Sélection déterministe seedée (date + étape), en écartant la dernière
/// variante servie (jamais 2 séquences consécutives avec la même) et les
/// variantes dont un placeholder manque.
RecoveryCopy _pick(List<String?> pool, DateTime seedDate, int step,
    {int? lastVariant}) {
  final valid = <({String text, int idx})>[
    for (var i = 0; i < pool.length; i++)
      if (pool[i] != null) (text: pool[i]!, idx: i),
  ];
  assert(valid.isNotEmpty, 'chaque pool doit garder une variante sans placeholder');
  var candidates = valid;
  if (lastVariant != null && valid.length > 1) {
    candidates = valid.where((v) => v.idx != lastVariant).toList();
  }
  final seed = seedDate.year * 10000 + seedDate.month * 100 + seedDate.day;
  final chosen = candidates[(seed + step) % candidates.length];
  return RecoveryCopy(chosen.text, chosen.idx);
}

/// Étape 1 — le constat (25a). [held] = faits « qui ont tenu » (vide = les
/// variantes qui les citent sont écartées).
RecoveryCopy recoveryCopyStep1(DateTime now, List<String> held,
    {int? lastVariant}) {
  final d1 = _dayFr(DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 2)));
  final d2 = _dayFr(DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1)));
  final cap = d1[0].toUpperCase() + d1.substring(1);
  final heldStr = held.join(', ');
  return _pick([
    held.isEmpty
        ? null
        : '$cap et $d2 à plat — noté, pas jugé. Ce qui a tenu quand même : '
            '$heldStr. Le système n\'est pas cassé, il tourne au ralenti — '
            'c\'est son travail. On repart par la plus petite marche.',
    held.isEmpty
        ? null
        : 'Deux jours au ralenti. Pendant ce temps : $heldStr. C\'est pas '
            'rien — c\'est la base qui a tenu toute seule. Aujourd\'hui on '
            'ne rattrape rien, on relance : une marche, une seule.',
    'J\'ai compté : 2 jours à plat, 0 sauté — parce qu\'on avait tout mis '
        'en attente, comme prévu. La machine repart comme elle s\'est '
        'arrêtée : par le plus petit geste.',
  ], now, 1, lastVariant: lastVariant);
}

/// Étape 2 — la question qui route (25b). Aucun placeholder : tout le pool
/// est toujours valide.
RecoveryCopy recoveryCopyStep2(DateTime now, {int? lastVariant}) => _pick([
      'La marche de ce matin n\'est pas passée — pas grave, j\'arrête de la '
          'proposer. Deux jours à plat, ce n\'est pas un échec, c\'est une '
          'information. Dis-moi laquelle, et on adapte la réponse, pas ta '
          'valeur :',
      'OK, pas ce matin — je range la marche. Une question, une seule, et je '
          'te laisse tranquille : c\'est le corps qui dit stop, ou le '
          'programme qui ne te ressemble plus ?',
      'Troisième proposition refusée — c\'est un signal, pas une faute. '
          'Avant d\'insister bêtement, je préfère savoir contre quoi on '
          'est :',
    ], now, 2, lastVariant: lastVariant);

/// Étape 3 — la remontée (25c). [j3] = jour du programme normal.
RecoveryCopy recoveryCopyStep3(DateTime now, {int? lastVariant}) {
  final j3 = _dayFr(DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 2)));
  return _pick([
    'Physique, noté — on ne rame pas contre. On ne repart pas au programme '
        'complet dès aujourd\'hui, c\'est comme ça qu\'on replonge. Trois '
        'jours, trois marches. Les blocs des deux jours à plat sont morts, '
        'rien à rattraper.',
    'Le corps décide, on suit. Trois jours pour remonter la pente — petit, '
        'moyen, normal. Rien des deux derniers jours n\'est à rattraper : '
        'c\'est mort, et c\'est très bien comme ça.',
    'Repos acté. La reprise, c\'est un escalier, pas un saut : routines '
        'aujourd\'hui, une vraie brique demain, la totale $j3 — seulement si '
        'les deux premières marches tiennent.',
  ], now, 3, lastVariant: lastVariant);
}

/// Étape 4 — le rappel du cap (25d). [aggregates] = agrégats réels formatés
/// (« 23 h sur Business ») — vide = les variantes chiffrées sont écartées ;
/// [hasIntention] = la phrase du user existe (V2 la cite).
RecoveryCopy recoveryCopyStep4(DateTime now,
    {String? aggregates, bool hasIntention = false, int? lastVariant}) {
  final d1 = _dayFr(DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 2)));
  final d2 = _dayFr(DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1)));
  return _pick([
    aggregates == null || aggregates.isEmpty
        ? null
        : 'Je ne te remotive pas avec des citations — voilà où tu en es, '
            'factuellement : $aggregates. Deux jours à plat n\'ont rien '
            'effacé de ça. Une marche aujourd\'hui suffit.',
    !hasIntention
        ? null
        : 'Relis ta phrase là-haut : c\'est toi qui l\'as écrite. Les '
            'chiffres en dessous, c\'est toi qui les as faits. Deux jours de '
            'creux ne changent ni l\'une ni les autres.',
    aggregates == null || aggregates.isEmpty
        ? null
        : '$aggregates. Le creux de $d1-$d2 pèse zéro là-dedans. On repart '
            'd\'où on est — pas de plus loin.',
    // Filet sans placeholder : toujours tirable, jamais de trou rempli.
    'Deux jours à plat n\'ont rien effacé. Une marche aujourd\'hui suffit — '
        'on repart d\'où on est, pas de plus loin.',
  ], now, 4, lastVariant: lastVariant);
}

/// Agrégats réels du domaine n° 1 pour l'étape 4 : heures logguées sur ses
/// activités (30 derniers jours). Null si rien à dire — la ligne saute.
String? recoveryAggregates(DateTime now, AppState st, Domain domain) {
  final cutoff = now.subtract(const Duration(days: 30));
  var minutes = 0;
  for (final s in st.sessions) {
    if (s.startAt.isBefore(cutoff)) continue;
    final act = st.activities.where((a) => a.id == s.activityId).firstOrNull;
    if (act == null || act.domainId != domain.id) continue;
    minutes += (s.endAt ?? now).difference(s.startAt).inMinutes;
  }
  if (minutes < 60) return null;
  final h = minutes ~/ 60;
  return '$h h sur ${domain.name} en 30 jours';
}

/// La note de 24a la plus récente des 3 derniers jours (« Et lundi, dans ta
/// note : … ») — null si aucune.
({String note, String day})? recentEnergyNote(
    DateTime now, List<DailySchedule?> docs) {
  for (final d in docs) {
    final note = d?.energyState?.note;
    if (note != null && note.trim().isNotEmpty) {
      return (note: note.trim(), day: _dayFr(d!.energyState!.at));
    }
  }
  return null;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
