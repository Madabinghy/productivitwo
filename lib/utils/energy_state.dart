import 'package:productivitwo_v1/models.dart';

// ─── MAINTENANT ADAPTATIF (tour 24) — logique pure, 0 LLM ────────────────────
//
// L'état déclaré (À fond / Correct / À plat) est un FAIT qui change la FORME
// de l'onglet Maintenant, jamais le fond : filtres d'affichage et glissements
// réversibles, aucun re-planning. Tout est déterministe et testable — la
// question, les modes et leurs propositions sont des templates avec les
// chiffres réels du jour.

/// TTL de l'état déclaré : jamais redemandé avant expiration.
const Duration kEnergyTtl = Duration(hours: 3);

/// L'état est-il encore actif ? 3 h OU jusqu'au prochain check-in — un point
/// du soir fait APRÈS la déclaration referme la parenthèse.
bool energyStateActive(EnergyState? s, DateTime now, {DateTime? reviewedAt}) {
  if (s == null) return false;
  if (now.difference(s.at) >= kEnergyTtl) return false;
  if (reviewedAt != null && reviewedAt.isAfter(s.at)) return false;
  return true;
}

/// Dernière ACTION réelle du jour : début/fin de session, bloc coché, routine
/// validée. Sert à compter les « ouvertures sans action » (déclencheur n° 1).
DateTime? lastActionAt(
    DateTime now, AppState st, List<ScheduleBlock> blocks) {
  DateTime? last;
  void keep(DateTime? t) {
    if (t == null || !_sameDay(t, now)) return;
    if (last == null || t.isAfter(last!)) last = t;
  }

  for (final s in st.sessions) {
    keep(s.startAt);
    keep(s.endAt);
  }
  for (final h in st.habitHits) {
    keep(h.ts);
  }
  for (final b in blocks) {
    keep(b.doneAt);
  }
  return last;
}

/// Ouvertures de l'onglet SANS action depuis : dans la fenêtre de 90 min et
/// postérieures à la dernière action réelle.
int idleOpenCount(DateTime now, List<DateTime> opens, DateTime? lastAction) {
  return opens
      .where((o) =>
          now.difference(o).inMinutes <= 90 &&
          !o.isAfter(now) &&
          (lastAction == null || o.isAfter(lastAction)))
      .length;
}

/// Pourquoi la question d'état s'affiche — null = pas de question.
enum EnergyAskTrigger { idle, drift, manual }

/// La question d'état (24a) doit-elle remplacer la carte coach ?
/// Déclencheurs (l'un des trois suffit) :
///  1. ≥ 3 ouvertures de Maintenant sans action en 90 min ;
///  2. bloc pending à +45 min avec 0 min logguée (même signal que la dérive —
///     la question remplace alors la carte dérive) ;
///  3. tap volontaire sur le tag d'état.
/// Jamais si un état est actif (répondu il y a < 3 h) : « je ne redemande pas
/// avant 3 h ». Fenêtre de jour uniquement (9 h – 21 h) — sauf tap volontaire.
EnergyAskTrigger? energyAskTrigger(
  DateTime now, {
  required EnergyState? state,
  DateTime? reviewedAt,
  int idleOpens = 0,
  ScheduleBlock? drifting,
  bool requested = false,
}) {
  // Le tap volontaire passe AVANT le TTL : « je ne redemande pas avant 3 h »
  // vaut pour l'app — le user, lui, peut toujours changer d'état à la main.
  if (requested) return EnergyAskTrigger.manual;
  if (energyStateActive(state, now, reviewedAt: reviewedAt)) return null;
  final minutes = now.hour * 60 + now.minute;
  if (minutes < 9 * 60 || minutes >= 21 * 60) return null;
  if (idleOpens >= 3) return EnergyAskTrigger.idle;
  if (drifting != null) return EnergyAskTrigger.drift;
  return null;
}

// ── Mode à plat (24b) : une chose à la fois ──────────────────────────────────

/// Une proposition du mode à plat : UNE chose, petite (≤ 25 min), routines
/// d'abord. [reduced] = version 25 min d'un bloc long (le bloc n'est pas
/// modifié — c'est un filtre d'affichage).
class LowModeItem {
  final String title;
  final String subtitle;
  final Activity? routine; // routine → chronos 5/10/15 sur elle
  final ScheduleBlock? block; // bloc du programme (≤ 25 min ou version 25)
  final bool reduced;
  const LowModeItem(
      {required this.title,
      required this.subtitle,
      this.routine,
      this.block,
      this.reduced = false});
}

/// File des propositions du mode à plat, par ordre de facilité :
/// routine (la plus courte d'abord) > bloc court (≤ 25 min, horizon 60 min)
/// > version 25 min d'un bloc long. « Autre chose ↻ » avance dans cette file —
/// nexter n'est jamais compté sauté ni journalisé comme refus.
List<LowModeItem> lowModeQueue(
    DateTime now, AppState st, List<ScheduleBlock> blocks) {
  final items = <LowModeItem>[];

  // Routines quotidiennes pas encore tenues, la plus courte d'abord (à plat,
  // « zéro réflexion » bat tout) ; sans minuteur = la plus facile de toutes.
  final routines = st.activities
      .where((a) => !a.deleted && a.isHabit && a.effHabitFreq == HabitFreq.daily)
      .where((a) =>
          !st.habitHits.any((h) => h.habitId == a.id && _sameDay(h.ts, now)))
      .toList()
    ..sort((a, b) {
      final da = a.timerMin ?? 0;
      final db = b.timerMin ?? 0;
      if (da != db) return da.compareTo(db);
      return a.order.compareTo(b.order);
    });
  for (final r in routines) {
    items.add(LowModeItem(
      title: r.name,
      subtitle: 'routine · zéro réflexion',
      routine: r,
    ));
  }

  // Blocs du programme dans l'heure qui vient (horizon 60 min) — les courts
  // tels quels, les longs en version 25 min. On ne replanifie rien.
  final pending = blocks
      .where((b) =>
          b.status == 'pending' && !b.isPrep && b.category != 'break')
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  for (final b in pending) {
    final start = _blockStart(b, now);
    final delta = start.difference(now).inMinutes;
    if (delta > 60) continue; // l'heure qui vient, pas l'après-midi
    if (b.durationMin <= 25) {
      items.add(LowModeItem(
          title: b.title, subtitle: '${b.durationMin} min · du programme',
          block: b));
    } else {
      items.add(LowModeItem(
          title: b.title,
          subtitle: 'version 25 min — le reste attendra',
          block: b,
          reduced: true));
    }
  }
  return items;
}

/// « Ensuite, si ça va » : UN seul bloc suivant, en pointillé, jamais lancé
/// d'office. Le premier engagement pending qui n'est pas déjà la proposition.
ScheduleBlock? lowModeNext(
    DateTime now, List<ScheduleBlock> blocks, LowModeItem? current) {
  final pending = blocks
      .where((b) =>
          b.status == 'pending' && !b.isPrep && b.category != 'break')
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  for (final b in pending) {
    if (b.id == current?.block?.id) continue;
    return b;
  }
  return null;
}

/// Blocs mis « en attente » par le mode à plat : tout le pending du jour hors
/// la proposition courante — rien n'est sauté, on recase au check-in
/// (mécanique 23c, affichage seulement : les blocs ne sont jamais modifiés).
int lowModeWaitingCount(List<ScheduleBlock> blocks, LowModeItem? current) =>
    blocks
        .where((b) =>
            b.status == 'pending' && !b.isPrep && b.category != 'break')
        .where((b) => b.id != current?.block?.id)
        .length;

// ── Mode à fond (24c) : deep work protégé ────────────────────────────────────

/// Une cible de deep work : un bloc du jour raccordé à un domaine, l'intention
/// de rang n° 1 en premier. [intention] = les mots du user (jamais reformulés),
/// null si le domaine de la cible n'est pas défini.
class FullTarget {
  final ScheduleBlock block;
  final String? domainName;
  final String? intention;
  final int rank; // rang du domaine (1 = premier de la liste), 99 = sans
  const FullTarget(
      {required this.block, this.domainName, this.intention, this.rank = 99});
}

/// Cibles du mode à fond, par rang de domaine (l'ordre de `st.domains` EST le
/// rang posé au nommage), projets avant le reste à rang égal. Sans domaine
/// défini, les blocs projet restent des cibles valables (rang 99).
/// « Autre cible ↻ » avance dans cette liste — sans jugement.
List<FullTarget> fullModeTargets(DateTime now, AppState st,
    List<ScheduleBlock> blocks, List<Project> projects) {
  final defined = <String, ({int rank, Domain d})>{};
  var rank = 1;
  for (final d in st.domains) {
    if (d.deleted || !d.isDefined) continue;
    defined[d.id] = (rank: rank, d: d);
    rank++;
  }

  ({int rank, Domain d})? domainOf(ScheduleBlock b) {
    if (b.activityId != null) {
      final act =
          st.activities.where((a) => a.id == b.activityId).firstOrNull;
      if (act?.domainId != null) return defined[act!.domainId];
    }
    if (b.projectId != null) {
      final p = projects.where((p) => p.id == b.projectId).firstOrNull;
      final domainId = p?.domainId;
      if (domainId != null) return defined[domainId];
    }
    return null;
  }

  final launchable = blocks
      .where((b) =>
          b.status == 'pending' &&
          !b.isPrep &&
          b.category != 'break' &&
          (b.projectId != null || b.activityId != null))
      .toList();
  final targets = <FullTarget>[];
  for (final b in launchable) {
    final dom = domainOf(b);
    targets.add(FullTarget(
      block: b,
      domainName: dom?.d.name,
      intention: dom?.d.intention,
      rank: dom?.rank ?? 99,
    ));
  }
  targets.sort((a, b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    final pa = a.block.category == 'project' ? 0 : 1;
    final pb = b.block.category == 'project' ? 0 : 1;
    if (pa != pb) return pa.compareTo(pb);
    return a.block.startTime.compareTo(b.block.startTime);
  });
  return targets;
}

/// Le glissement induit par la réservation d'un créneau deep work de
/// [durationMin] à partir de [now] : les blocs pending qui tombent dans le
/// créneau glissent APRÈS, en chaîne. La soirée off ne bouge pas : un bloc
/// qui atterrirait à 19 h ou plus reste à sa place (recasé au check-in).
/// Retourne les déplacements (bloc → nouvelle heure) SANS rien écrire — la
/// conséquence est affichée avant de valider.
List<({ScheduleBlock block, String newStart})> deepWorkShifts(
    DateTime now, List<ScheduleBlock> blocks, ScheduleBlock target,
    int durationMin) {
  final slotEnd = now.add(Duration(minutes: durationMin));
  var cursor = slotEnd;
  final shifts = <({ScheduleBlock block, String newStart})>[];
  final pending = blocks
      .where((b) =>
          b.status == 'pending' &&
          !b.isPrep &&
          b.category != 'break' &&
          b.id != target.id)
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  for (final b in pending) {
    final start = _blockStart(b, now);
    final end = start.add(Duration(minutes: b.durationMin));
    // Hors du créneau (fini avant, ou commence après la fin du créneau ET
    // après le curseur des déjà-glissés) : rien ne bouge.
    if (end.isBefore(now) || !start.isBefore(cursor)) continue;
    final landing = cursor;
    // La soirée off ne bouge pas : pas de glissement vers ≥ 19 h.
    if (landing.hour >= 19) continue;
    shifts.add((block: b, newStart: _hm(landing)));
    cursor = landing.add(Duration(minutes: b.durationMin));
  }
  return shifts;
}

// ── Templates (chiffres réels, jamais inventés) ──────────────────────────────

/// Message de la question d'état (24a) selon le déclencheur.
String energyAskMessage(EnergyAskTrigger trigger,
    {int idleOpens = 0, DateTime? firstOpen, ScheduleBlock? drifting}) {
  switch (trigger) {
    case EnergyAskTrigger.idle:
      final since = firstOpen != null
          ? ' depuis ${firstOpen.minute == 0 ? '${firstOpen.hour} h' : '${firstOpen.hour} h ${firstOpen.minute.toString().padLeft(2, '0')}'}'
          : '';
      final nth = idleOpens + 1;
      return '$idleOpens passages ici$since, rien de lancé. Je ne repropose '
          'pas les blocs une ${nth}ᵉ fois — dis-moi juste comment tu es, '
          'et j\'adapte la forme.';
    case EnergyAskTrigger.drift:
      final title = drifting?.title;
      final at = drifting != null
          ? drifting.startTime.replaceFirst(':', ' h ').replaceFirst(' h 00', ' h ')
          : null;
      return title != null
          ? '« $title » est posé depuis $at — rien de lancé. Plutôt que '
              'd\'insister, dis-moi juste comment tu es, et j\'adapte la forme.'
          : 'Rien de lancé depuis un moment. Dis-moi juste comment tu es, '
              'et j\'adapte la forme.';
    case EnergyAskTrigger.manual:
      return 'Dis-moi comment tu es — j\'adapte la forme, pas le fond.';
  }
}

/// Message du mode à plat (24b) : le gros bloc du jour attendra, nommé quand
/// il existe — une donnée absente est omise, jamais remplie.
String lowModeMessage(List<ScheduleBlock> blocks) {
  ScheduleBlock? biggest;
  for (final b in blocks) {
    if (b.status != 'pending' || b.isPrep || b.category == 'break') continue;
    if (b.durationMin <= 25) continue;
    if (biggest == null || b.durationMin > biggest.durationMin) biggest = b;
  }
  final waiting = biggest != null
      ? ' : ${biggest.title.toLowerCase().startsWith('la ') || biggest.title.toLowerCase().startsWith('le ') ? biggest.title : '« ${biggest.title} »'} attendra que tu remontes'
      : '';
  return 'Noté. On ne planifie pas l\'après-midi — juste l\'heure qui vient, '
      'une chose, petite. À plat, les routines tiennent mieux que le deep '
      'work$waiting. C\'est du séquencement, pas de la paresse.';
}

// ── Helpers locaux ───────────────────────────────────────────────────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _blockStart(ScheduleBlock b, DateTime now) {
  final parts = b.startTime.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(now.year, now.month, now.day, h, m);
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
