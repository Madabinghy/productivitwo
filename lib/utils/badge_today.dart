import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/half_days.dart' show ActivityPace;
import 'package:productivitwo_v1/utils/elan_logic.dart' show FlemmeWin;
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/chain_session.dart' show PendingChain, kChainCountedMin;
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/objective_day.dart' show ObjectiveDay;
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;

/// « Ce qu'il manque aujourd'hui » par badge (2026-10) : à partir des données
/// du jour vécu (routines quotidiennes dues, blocs du programme, pointage
/// d'élan, session Enchaîner, temps des objectifs), ce qu'il reste à faire
/// pour tenir une suite en cours ou décrocher un palier aujourd'hui. Logique
/// pure, sans jugement : les compteurs des badges restent sur les jours clos,
/// ceci ne dit que l'état « pour l'instant ».

/// Une routine quotidienne due aujourd'hui.
class RoutineToday {
  final Activity activity;
  final int done;
  final int target;
  const RoutineToday(this.activity, this.done, this.target);
  bool get reached => done >= target;
  double get ratio => target <= 0 ? 1 : (done / target).clamp(0.0, 1.0);
}

/// Les faits du jour vécu, construits par l'app (`BadgeCenter.todayFacts`).
class TodayFacts {
  final String ymd;
  final DateTime now;
  final List<RoutineToday> routines;
  /// Blocs du programme du jour (tous ; seuls ceux de [countsForBadges] comptent).
  final List<ScheduleBlock> blocks;
  final List<MoodMark> elanMarks; // pointages d'élan du jour vécu
  final PendingChain? pendingChain; // session Enchaîner reprenable, si vivante
  final List<ObjectiveDay> objectiveDays;
  final List<StrategicObjective> objectives;
  final int disciplineWinsToday;
  /// Les victoires sur la flemme du jour, en détail (quoi, comment, quand).
  final List<FlemmeWin> flemmeWins;
  /// Activités-temps face à l'attendu de leur fenêtre, maintenant (Montre suisse).
  final List<ActivityPace> pace;
  /// Domaines en veille aujourd'hui (hors Montre suisse / Métronome).
  final Set<String> restingDomainIds;
  const TodayFacts({
    required this.ymd,
    required this.now,
    this.routines = const [],
    this.blocks = const [],
    this.elanMarks = const [],
    this.pendingChain,
    this.objectiveDays = const [],
    this.objectives = const [],
    this.disciplineWinsToday = 0,
    this.flemmeWins = const [],
    this.pace = const [],
    this.restingDomainIds = const {},
  });

  /// Routines qui comptent pour Métronome aujourd'hui (hors domaines en veille).
  List<RoutineToday> get metronomeRoutines => routines.where((r) => !restingDomainIds.contains(r.activity.domainId)).toList();

  List<ScheduleBlock> get countedBlocks => blocks.where(countsForBadges).toList();
  List<ScheduleBlock> get pendingBlocks => countedBlocks.where((b) => b.status == 'pending').toList();
  int get blocksDone => countedBlocks.where((b) => b.status == 'done').length;
  int get routinesReached => routines.where((r) => r.reached).length;
  bool get elanPointed => elanMarks.isNotEmpty;
  double? get elanMean => elanMarks.isEmpty ? null : elanMarks.fold<int>(0, (s, m) => s + m.value) / elanMarks.length;
}

enum GapKind { routine, block, elan, time, chain, reading, deepwork, action }

/// Un geste concret du jour.
class GapItem {
  final GapKind kind;
  final String title;
  final String detail;
  final String? activityId;
  final ScheduleBlock? block;
  final int? minutes;
  const GapItem(this.kind, this.title, {this.detail = '', this.activityId, this.block, this.minutes});
}

/// Enjeu du jour : une suite se perd (atRisk), le palier ou la journée est
/// possible (reachable), déjà acquis pour aujourd'hui (saved), perdu pour
/// aujourd'hui (lostToday), rien à faire aujourd'hui (none).
enum TodayStake { atRisk, reachable, saved, lostToday, none }

class BadgeToday {
  final TodayStake stake;
  final String chip; // « en jeu · il manque 2 choses »
  final List<GapItem> items;
  final List<String> notes; // phrases d'explication (marge, « comptera demain »…)
  /// Jauges à montrer : (libellé, fait, suffisant, total).
  final List<({String label, int done, int need, int total})> gauges;
  /// « Faisable du jour » : ce qui est fait sur ce que la journée peut
  /// apporter au badge (gestes, minutes). Mini-barre des lignes À portée.
  final int dayDone;
  final int dayTotal;
  /// Ce que la journée ajoutera à la mesure du badge une fois close, si elle
  /// tient (badges dont le compteur ne voit que les jours clos : journées
  /// solides). 0 quand le compteur inclut déjà aujourd'hui.
  final num gain;
  const BadgeToday({
    required this.stake,
    required this.chip,
    this.items = const [],
    this.notes = const [],
    this.gauges = const [],
    this.dayDone = 0,
    this.dayTotal = 0,
    this.gain = 0,
  });

  bool get inPlay => stake == TodayStake.atRisk;
  int get missing => items.length;
  /// Le gain du jour est acquis « pour l'instant » (journée tenue).
  bool get gainSecured => gain > 0 && stake == TodayStake.saved;
  /// Part du faisable du jour (0..1), null sans faisable.
  double? get dayRatio => dayTotal <= 0 ? null : (dayDone / dayTotal).clamp(0.0, 1.0);
  static const none = BadgeToday(stake: TodayStake.none, chip: '');
}

/// Seuil « solide » d'une journée (Semaine / Mois solide, Vent contraire).
const kSolidRatio = 0.8;

/// Combien il en faut sur [total] pour atteindre [kSolidRatio] (0 si rien n'est dû).
int solidNeed(int total) => total <= 0 ? 0 : (total * kSolidRatio).ceil();

String _things(int n) => n == 1 ? '1 chose' : '$n choses';

String _blockTime(ScheduleBlock b) => '${b.startTime} · ${fmtMin(b.durationMin)}';

/// Routines non atteintes, les plus avancées d'abord (elles se bouclent vite).
List<RoutineToday> _missingRoutines(TodayFacts f) {
  final out = f.routines.where((r) => !r.reached).toList()
    ..sort((a, b) {
      final c = b.ratio.compareTo(a.ratio);
      return c != 0 ? c : a.activity.name.toLowerCase().compareTo(b.activity.name.toLowerCase());
    });
  return out;
}

GapItem _routineItem(RoutineToday r, {String? extra}) => GapItem(
      GapKind.routine,
      r.activity.name,
      detail: [
        '${r.done} / ${r.target} aujourd’hui',
        if (extra != null) extra,
      ].join(' · '),
      activityId: r.activity.id,
    );

GapItem _blockItem(ScheduleBlock b) => GapItem(GapKind.block, b.title, detail: _blockTime(b), block: b);

/// Ce qu'il manque aujourd'hui pour [b], d'après [f]. Jamais null : un badge
/// sans levier du jour renvoie [BadgeToday.none].
BadgeToday badgeToday(BadgeState b, TodayFacts f) {
  final id = b.def.id;
  if (id.startsWith('serie-')) return _serie(b, f);
  if (id.startsWith('temps-')) return _temps(b, f);
  switch (id) {
    case 'journee-parfaite':
      return _parfaite(b, f);
    case 'montre-suisse':
      return _montre(b, f);
    case 'metronome':
      return _metronome(b, f);
    case 'semaine-solide':
    case 'mois-solide':
    case 'vent-contraire':
      return _solide(b, f);
    case 'maree-haute':
      return _maree(b, f);
    case 'barometre':
      return _barometre(f);
    case 'malgre-tout':
      return _malgreTout(f);
    case 'enchaineur':
    case 'plein-jour':
      return _enchainer(b, f);
    case 'releve-fidele':
    case 'trajectoire':
      return _releves(f);
    case 'deep-work':
      return b.complete
          ? BadgeToday.none
          : const BadgeToday(stake: TodayStake.reachable, chip: 'à portée', items: [
              GapItem(GapKind.deepwork, 'Pose un Deep work 90 min', detail: 'depuis MAINTENANT en mode En forme · 60 min de chrono dessus')
            ]);
    case 'actions':
      return b.complete
          ? BadgeToday.none
          : BadgeToday(stake: TodayStake.reachable, chip: 'encore ${fmtInt(b.nextTarget! - b.value)}', items: const [
              GapItem(GapKind.action, 'Coche des actions', detail: 'Actions, un bloc du programme, Enchaîner')
            ]);
    default:
      return BadgeToday.none;
  }
}

BadgeToday _serie(BadgeState b, TodayFacts f) {
  final r = f.routines.where((x) => x.activity.id == b.def.subjectId).firstOrNull;
  if (r == null) return BadgeToday.none; // routine supprimée ou plus quotidienne
  if (r.reached) {
    final next = b.nextTarget;
    final tomorrow = next != null && b.value + 1 >= next;
    return BadgeToday(
      stake: TodayStake.saved,
      chip: 'atteinte aujourd’hui',
      notes: [
        if (b.value > 0) 'La série continue : ${b.value + 1} j demain matin.',
        if (tomorrow) 'Le palier ${fmtInt(next)} j tombe demain à la bascule.',
      ],
    );
  }
  final blocks = f.pendingBlocks.where((x) => x.activityId == r.activity.id).toList();
  final next = b.nextTarget;
  final todayHitsTier = next != null && b.value + 1 >= next;
  return BadgeToday(
    stake: b.value > 0 ? TodayStake.atRisk : TodayStake.reachable,
    chip: b.value > 0 ? 'en jeu · pas encore cochée' : 'à portée · pas encore cochée',
    dayDone: r.done,
    dayTotal: r.target,
    items: [
      _routineItem(r, extra: b.value > 0 ? 'série ${b.value} j' : null),
      for (final x in blocks) GapItem(GapKind.block, 'Bloc « ${x.title} »', detail: '${_blockTime(x)} · le bloc coche la routine à la fin', block: x),
    ],
    notes: [
      if (b.value > 0) 'Sans coche avant la bascule de journée, la série repart à 0.',
      if (todayHitsTier) 'Cochée aujourd’hui, le palier ${fmtInt(next)} j est acquis ce soir.',
    ],
  );
}

BadgeToday _parfaite(BadgeState b, TodayFacts f) {
  final due = f.routines.length;
  final total = f.countedBlocks.length;
  if (due + total == 0) return const BadgeToday(stake: TodayStake.none, chip: 'journée neutre', notes: ['Rien à tenir aujourd’hui : la journée ne compte ni pour ni contre.']);
  final missing = _missingRoutines(f);
  final pending = f.pendingBlocks;
  final n = missing.length + pending.length;
  final dayDone = f.routinesReached + f.blocksDone;
  final gauges = [
    (label: 'Routines', done: f.routinesReached, need: due, total: due),
    (label: 'Blocs', done: f.blocksDone, need: total, total: total),
  ];
  if (n == 0) {
    return BadgeToday(
      stake: TodayStake.saved,
      chip: 'journée parfaite · pour l’instant',
      gauges: gauges,
      dayDone: dayDone,
      dayTotal: due + total,
      gain: b.acquired ? 0 : 1,
      notes: ['Tout est fait. Un bloc ajouté au programme devra l’être aussi ; la journée est comptée demain à la bascule.'],
    );
  }
  return BadgeToday(
    stake: TodayStake.reachable,
    chip: 'possible aujourd’hui · il manque ${_things(n)}',
    gauges: gauges,
    dayDone: dayDone,
    dayTotal: due + total,
    gain: b.acquired ? 0 : 1,
    items: [
      for (final r in missing) _routineItem(r),
      for (final x in pending) _blockItem(x),
    ],
    notes: ['Comptée demain à la bascule, une fois la journée close.'],
  );
}

/// Montre suisse : chaque activité couverte sur ses 7 derniers jours ce soir.
BadgeToday _montre(BadgeState b, TodayFacts f) {
  final all = f.pace;
  if (all.isEmpty) return const BadgeToday(stake: TodayStake.none, chip: 'journée neutre', notes: ['Aucune activité avec un minimum vital aujourd’hui.']);
  final behind = all.where((p) => !p.onPace).toList()..sort((x, y) => x.missingMin.compareTo(y.missingMin));
  final ok = all.length - behind.length;
  final gauges = [(label: 'Activités couvertes sur 7 jours', done: ok, need: all.length, total: all.length)];
  final tomorrow = [for (final p in all) if (p.tomorrowNeedMin > 0) p]..sort((x, y) => y.tomorrowNeedMin.compareTo(x.tomorrowNeedMin));
  final notes = [
    if (tomorrow.isNotEmpty)
      'Demain : ${tomorrow.take(3).map((p) => '${p.activity.name} ${fmtMin(p.tomorrowNeedMin)}').join(' · ')} pour rester couvertes.',
    'Comptée demain à la bascule, une fois la journée close.',
  ];
  if (behind.isEmpty) {
    return BadgeToday(
        stake: TodayStake.saved,
        chip: 'toutes couvertes · pour l’instant',
        gauges: gauges,
        dayDone: ok,
        dayTotal: all.length,
        gain: 1,
        notes: notes);
  }
  return BadgeToday(
    stake: TodayStake.reachable,
    chip: '$ok / ${all.length} couvertes · reste ${behind.length}',
    gauges: gauges,
    dayDone: ok,
    dayTotal: all.length,
    gain: 1,
    items: [
      for (final p in behind)
        GapItem(GapKind.time, 'Encore ${fmtMin(p.missingMin)} de ${p.activity.name}',
            detail: '${fmtMin(p.doneMin)} / ${fmtMin(p.expectedMin)} sur 7 jours', activityId: p.activity.id, minutes: p.missingMin),
    ],
    notes: notes,
  );
}

/// Métronome : toutes les routines du jour (hors acquises, hors veille).
BadgeToday _metronome(BadgeState b, TodayFacts f) {
  final rs = f.metronomeRoutines;
  if (rs.isEmpty) return const BadgeToday(stake: TodayStake.none, chip: 'journée neutre', notes: ['Aucune routine due aujourd’hui.']);
  final reached = rs.where((r) => r.reached).length;
  final missing = rs.where((r) => !r.reached).toList()..sort((x, y) => y.ratio.compareTo(x.ratio));
  final gauges = [(label: 'Routines', done: reached, need: rs.length, total: rs.length)];
  if (missing.isEmpty) {
    return BadgeToday(
        stake: TodayStake.saved,
        chip: 'toutes atteintes · pour l’instant',
        gauges: gauges,
        dayDone: reached,
        dayTotal: rs.length,
        gain: 1,
        notes: const ['Comptée demain à la bascule.']);
  }
  return BadgeToday(
    stake: TodayStake.reachable,
    chip: '$reached / ${rs.length} routines',
    gauges: gauges,
    dayDone: reached,
    dayTotal: rs.length,
    gain: 1,
    items: [for (final r in missing) _routineItem(r)],
    notes: const ['Comptée demain à la bascule, une fois la journée close.'],
  );
}

BadgeToday _solide(BadgeState b, TodayFacts f) {
  final due = f.routines.length;
  final total = f.countedBlocks.length;
  if (due + total == 0) return const BadgeToday(stake: TodayStake.none, chip: 'journée neutre', notes: ['Rien à tenir aujourd’hui : la suite n’est ni cassée ni allongée.']);
  final needR = solidNeed(due);
  final needB = solidNeed(total);
  final reached = f.routinesReached;
  final done = f.blocksDone;
  final pending = f.pendingBlocks;
  final missingR = (needR - reached).clamp(0, due);
  final missingB = (needB - done).clamp(0, total);
  final gauges = [
    if (due > 0) (label: 'Routines', done: reached, need: needR, total: due),
    if (total > 0) (label: 'Blocs', done: done, need: needB, total: total),
  ];
  final running = b.value > 0;
  final dayDone = (reached > needR ? needR : reached) + (done > needB ? needB : done);
  final dayTotal = needR + needB;
  if (missingR == 0 && missingB == 0) {
    return BadgeToday(
      stake: TodayStake.saved,
      dayDone: dayDone,
      dayTotal: dayTotal,
      gain: 1,
      chip: 'journée solide · pour l’instant',
      gauges: gauges,
      notes: ['≥ 80 % des deux côtés : la journée est tenue, elle comptera demain à la bascule${running ? ' (${b.value + 1} j d’affilée)' : ''}.'],
    );
  }
  if (missingB > pending.length) {
    return BadgeToday(
      stake: TodayStake.lostToday,
      chip: 'sous 80 % aujourd’hui',
      gauges: gauges,
      dayDone: dayDone,
      dayTotal: dayTotal,
      notes: ['Trop de blocs sautés ou supprimés : la journée ne sera pas solide${running ? ', la suite de ${b.value} j repart demain' : ''}.'],
    );
  }
  final missing = _missingRoutines(f);
  final slackB = pending.length - missingB;
  final parts = <String>[
    if (missingR > 0) '$missingR routine${missingR > 1 ? 's' : ''}',
    if (missingB > 0) '$missingB bloc${missingB > 1 ? 's' : ''} sur ${pending.length}',
  ];
  return BadgeToday(
    stake: running ? TodayStake.atRisk : TodayStake.reachable,
    chip: '${running ? 'en jeu' : 'à portée'} · ${parts.join(', ')}',
    gauges: gauges,
    dayDone: dayDone,
    dayTotal: dayTotal,
    gain: 1,
    items: [
      for (final r in missing.take(missingR)) _routineItem(r, extra: 'la plus avancée'),
      for (final x in pending) _blockItem(x),
    ],
    notes: [
      'Pour tenir la journée : ${parts.join(' et ')}.'
          '${missingB > 0 && slackB > 0 ? ' Tu peux encore en manquer $slackB.' : (missingB > 0 ? ' Plus aucune marge sur les blocs.' : '')}',
      'Comptée demain à la bascule${running ? ' : ${b.value + 1} j d’affilée si elle tient' : ''}.',
      if (b.def.id == 'vent-contraire') 'Vent contraire demande aussi un élan moyen ≤ 2,5 sur la suite.',
    ],
  );
}

BadgeToday _maree(BadgeState b, TodayFacts f) {
  final mean = f.elanMean;
  if (mean == null) {
    final tomorrow = b.nextTarget != null && b.value + 1 >= b.nextTarget!;
    return BadgeToday(
      stake: b.value > 0 ? TodayStake.atRisk : TodayStake.reachable,
      chip: b.value > 0 ? 'en jeu · pas encore pointé' : 'à portée · pointe ton élan',
      dayTotal: 1,
      items: const [GapItem(GapKind.elan, 'Pointe ton élan', detail: 'Flemme · Normal · En forme, depuis la pilule du mode')],
      notes: [
        'Compte si l’élan moyen du jour est ≥ 4 (En forme ou Lancé).',
        if (tomorrow) 'Un pointage ≥ 4 aujourd’hui et le badge est obtenu : 7ᵉ jour d’affilée.',
      ],
    );
  }
  if (mean >= 4) {
    return BadgeToday(stake: TodayStake.saved, chip: 'élan ${_mean(mean)} · tenu', dayDone: 1, dayTotal: 1, notes: ['Journée à élan haut : la suite continue (${b.value + 1} j).']);
  }
  return BadgeToday(
    stake: TodayStake.lostToday,
    chip: 'élan ${_mean(mean)} · sous 4',
    notes: ['L’élan moyen du jour est sous 4${b.value > 0 ? ' : la suite de ${b.value} j repart' : ''}. Un pointage plus haut remonte la moyenne.'],
  );
}

String _mean(double m) => m == m.roundToDouble() ? '${m.round()}' : m.toStringAsFixed(1).replaceAll('.', ',');

BadgeToday _barometre(TodayFacts f) {
  if (f.elanPointed) return const BadgeToday(stake: TodayStake.saved, chip: 'pointé aujourd’hui', dayDone: 1, dayTotal: 1);
  return const BadgeToday(
    stake: TodayStake.reachable,
    chip: 'à portée · +1 pointage',
    dayTotal: 1,
    items: [GapItem(GapKind.elan, 'Pointe ton élan', detail: 'un pointage par créneau compte')],
  );
}

BadgeToday _malgreTout(TodayFacts f) {
  final mean = f.elanMean;
  if (mean == null || mean > 2) {
    return const BadgeToday(stake: TodayStake.none, chip: '', notes: ['Se gagne en mode Flemme : un chrono tenu 10 min, une action cochée, un bloc fait ou une routine atteinte.']);
  }
  if (f.disciplineWinsToday > 0) {
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return BadgeToday(
      stake: TodayStake.saved,
      chip: '${f.disciplineWinsToday} victoire${f.disciplineWinsToday > 1 ? 's' : ''} aujourd’hui',
      notes: [
        for (final w in f.flemmeWins) '${hm(w.at)} · ${w.what} · ${w.how}',
        'Comptent en Flemme : un chrono tenu 10 min, une action cochée, un bloc fait, une routine atteinte. Pas les besoins de base (sommeil, sieste, repas).',
      ],
    );
  }
  final missing = _missingRoutines(f);
  return BadgeToday(
    stake: TodayStake.reachable,
    chip: 'jour de flemme · une chose = une victoire',
    dayTotal: 1,
    items: [
      for (final r in missing.take(2)) _routineItem(r),
      for (final x in f.pendingBlocks.take(1)) _blockItem(x),
    ],
  );
}

BadgeToday _enchainer(BadgeState b, TodayFacts f) {
  final p = f.pendingChain;
  if (p != null && p.doneCount < kChainCountedMin) {
    final left = kChainCountedMin - p.doneCount;
    return BadgeToday(
      stake: TodayStake.reachable,
      chip: 'session en attente · encore ${_things(left)}',
      dayDone: p.doneCount,
      dayTotal: kChainCountedMin,
      items: [GapItem(GapKind.chain, 'Reprends l’enchaînement', detail: '${p.doneCount} faite${p.doneCount > 1 ? 's' : ''} · encore $left pour qu’elle compte')],
    );
  }
  if (p != null) {
    return BadgeToday(stake: TodayStake.saved, chip: 'session comptée · ${p.doneCount} choses', dayDone: kChainCountedMin, dayTotal: kChainCountedMin);
  }
  if (b.complete) return BadgeToday.none;
  final n = f.pendingBlocks.length;
  return BadgeToday(
    stake: n >= kChainCountedMin ? TodayStake.reachable : TodayStake.none,
    chip: n >= kChainCountedMin ? 'à portée · $n blocs à enchaîner' : 'moins de 3 blocs à venir',
    dayTotal: n >= kChainCountedMin ? kChainCountedMin : 0,
    items: [
      if (n >= kChainCountedMin) GapItem(GapKind.chain, 'Lance Enchaîner', detail: b.def.id == 'plein-jour' ? 'avant le premier bloc, jusqu’au dernier' : '3 choses faites d’affilée et la session compte'),
    ],
  );
}

BadgeToday _releves(TodayFacts f) {
  final due = f.objectives.where((o) => o.status == 'active' && o.metric != null && isReadingDue(o, f.now)).toList();
  if (due.isEmpty) return const BadgeToday(stake: TodayStake.none, chip: 'aucun relevé dû', notes: ['Le prochain relevé compte à son échéance, sans en manquer.']);
  return BadgeToday(
    stake: TodayStake.reachable,
    chip: '${due.length} relevé${due.length > 1 ? 's' : ''} à noter',
    dayTotal: due.length,
    items: [for (final o in due) GapItem(GapKind.reading, 'Note le relevé « ${o.title} »', detail: o.metric!.label)],
  );
}

BadgeToday _temps(BadgeState b, TodayFacts f) {
  final day = f.objectiveDays.where((d) => d.objective.id == b.def.subjectId).firstOrNull;
  if (day == null || day.times.isEmpty) return BadgeToday.none;
  final expected = day.times.fold<int>(0, (s, t) => s + t.expectedTodayMin);
  final done = day.times.fold<int>(0, (s, t) => s + t.doneTodayMin);
  final gauges = [(label: 'Rythme du jour', done: done, need: expected, total: expected)];
  if (done >= expected) {
    return BadgeToday(stake: TodayStake.saved, chip: 'rythme du jour tenu · ${fmtMin(done)}', gauges: gauges, dayDone: expected, dayTotal: expected);
  }
  final behind = [...day.times]..sort((x, y) => (y.expectedTodayMin - y.doneTodayMin).compareTo(x.expectedTodayMin - x.doneTodayMin));
  final t = behind.first;
  final left = (t.expectedTodayMin - t.doneTodayMin).clamp(1, 1 << 20);
  final block = f.pendingBlocks.where((x) => x.activityId == t.activityId).firstOrNull;
  return BadgeToday(
    stake: TodayStake.reachable,
    chip: 'encore ${fmtMin(expected - done)} aujourd’hui',
    gauges: gauges,
    dayDone: done,
    dayTotal: expected,
    items: [
      GapItem(GapKind.time, 'Encore ${fmtMin(left)} de ${t.name}', detail: block == null ? 'chrono sur l’activité' : 'bloc « ${block.title} » à ${block.startTime}', activityId: t.activityId, minutes: left, block: block),
    ],
  );
}

/// Badges dont une suite en cours est en jeu aujourd'hui, puis ceux à portée.
List<(BadgeState, BadgeToday)> badgesInPlay(BadgeDeck deck, TodayFacts f) {
  final out = <(BadgeState, BadgeToday)>[];
  for (final b in deck.badges) {
    final t = badgeToday(b, f);
    if (t.stake == TodayStake.atRisk) out.add((b, t));
  }
  return out;
}
