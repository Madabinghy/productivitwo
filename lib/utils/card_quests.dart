import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badge_today.dart' show TodayFacts;
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

/// Les cartes à aller chercher (maquette validée 2026-11-03, « Cartes à aller
/// chercher ») : les cartes que la journée peut faire avancer, ce qu'il manque
/// pour leur prochain cadre, la stratégie, et les tirs d'un Sniper ciblé sur
/// elles. Logique pure.

/// Sorte de quête, d'après le badge.
enum QuestKind {
  /// Compteur d'heures d'une activité : du chrono.
  time,
  /// Compteur de coches d'une routine.
  reps,
  /// Série de routine : le +1 de chaque jour.
  series,
  /// Métronome / Montre suisse : la journée à tenir.
  days,
  /// Guérilla / Offensive / Sniper : une session du mode.
  mode,
}

/// Un tir du Sniper ciblé : du temps sur une activité ou des coches d'une routine.
class QuestStep {
  /// Même clé que les enjeux (`activity:<id>`, `routine:<id>`).
  final String key;
  final Activity activity;
  /// Minutes (activité) ou coches (routine).
  final int amount;
  final bool minutes;
  const QuestStep(this.key, this.activity, this.amount, {required this.minutes});
  String get label => minutes ? _dur(amount) : '+$amount';
}

class CardQuest {
  final BadgeState badge;
  final QuestKind kind;
  /// Le cadre que donnerait le prochain palier.
  final CardRarity nextRarity;
  /// « Il manque 1 passage · ≈ 20 min ».
  final String need;
  /// Jours encore nécessaires (1 = peut tomber aujourd'hui).
  final int days;
  /// Effort estimé aujourd'hui, en minutes (pour le classement).
  final int effortMin;
  /// Lignes de stratégie (« 52 min de chrono sur Cuisiner »…).
  final List<String> strategy;
  /// Tirs du Sniper ciblé (vide pour un mode ou une journée déjà tenue).
  final List<QuestStep> steps;
  /// Mode à lancer (Guérilla, Offensive, Sniper) pour une quête de mode.
  final String? modeKind;
  /// Le palier peut tomber aujourd'hui en tirant tous les [steps] en entier.
  final bool fallsToday;
  const CardQuest({
    required this.badge,
    required this.kind,
    required this.nextRarity,
    required this.need,
    required this.days,
    required this.effortMin,
    this.strategy = const [],
    this.steps = const [],
    this.modeKind,
    this.fallsToday = false,
  });

  bool get sniperable => steps.isNotEmpty;
  int get stepsMin => steps.fold(0, (s, x) => s + (x.minutes ? x.amount : (x.activity.timerMin ?? 0) > 0 ? x.activity.timerMin! : 2));
}

/// Plafonds de « à portée » : au-delà, la carte n'est pas proposée.
const kQuestMaxMin = 120;
const kQuestMaxReps = 10;
const kQuestMaxDays = 3;
const kQuestMaxSessions = 2;
/// Un tir du Sniper ne dépasse pas une heure (`kSniperMaxMin`).
const kQuestStepMaxMin = 60;

String _dur(int min) {
  if (min < 60) return '$min min';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

String _plural(int n, String one, String many) => n > 1 ? many : one;

CardRarity _nextRarity(BadgeState b) {
  final ladder = rarityLadder(b.def);
  return b.level < ladder.length ? ladder[b.level] : rarityOf(b);
}

/// La quête d'une carte, ou null quand la journée ne peut pas la faire avancer
/// (palier trop loin, badge complet, objectif lointain).
CardQuest? cardQuestOf(BadgeState b, {required List<Activity> activities, TodayFacts? facts}) {
  final next = b.nextTarget;
  if (b.complete || next == null) return null;
  final gap = next - b.value;
  if (gap <= 0) return null;
  final id = b.def.id;
  final rarity = _nextRarity(b);
  Activity? act() => activities.where((a) => a.id == b.def.subjectId && !a.deleted).firstOrNull;

  if (id.startsWith('heures-') && id != 'heures-annee' && id != 'heures-total') {
    final a = act();
    if (a == null) return null;
    final m = (gap * 60).ceil();
    if (m > kQuestMaxMin) return null;
    final step = m > kQuestStepMaxMin ? kQuestStepMaxMin : m;
    return CardQuest(
      badge: b,
      kind: QuestKind.time,
      nextRarity: rarity,
      need: 'Il manque ${_dur(m)} de chrono sur ${a.name}',
      days: 1,
      effortMin: m,
      strategy: [
        m > step ? '${_dur(step)} aujourd’hui, le reste demain' : '${_dur(m)} de chrono sur ${a.name}, en une fois ou en deux',
      ],
      steps: [QuestStep('activity:${a.id}', a, step, minutes: true)],
      fallsToday: m <= step,
    );
  }

  if (id.startsWith('fois-')) {
    final a = act();
    if (a == null) return null;
    final n = gap.ceil();
    if (n > kQuestMaxReps) return null;
    final per = (a.timerMin ?? 0) > 0 ? a.timerMin! : 3;
    return CardQuest(
      badge: b,
      kind: QuestKind.reps,
      nextRarity: rarity,
      need: 'Il manque $n ${_plural(n, 'fois', 'fois')} · ≈ ${_dur(n * per)}',
      days: 1,
      effortMin: n * per,
      strategy: ['$n ${_plural(n, 'coche', 'coches')} de ${a.name}, même au-delà de la cible du jour'],
      steps: [QuestStep('routine:${a.id}', a, n, minutes: false)],
      fallsToday: true,
    );
  }

  if (id.startsWith('serie-')) {
    final a = act();
    if (a == null) return null;
    final n = gap.ceil();
    if (n > kQuestMaxDays) return null;
    final today = facts?.routines.where((r) => r.activity.id == a.id).firstOrNull;
    final left = today == null || today.reached ? 0 : today.target - today.done;
    return CardQuest(
      badge: b,
      kind: QuestKind.series,
      nextRarity: rarity,
      need: n == 1 ? '${a.name} aujourd’hui, et le palier tombe' : '${a.name} $n jours de suite',
      days: n,
      effortMin: left * ((a.timerMin ?? 0) > 0 ? a.timerMin! : 3),
      strategy: [
        if (left > 0) 'Aujourd’hui : $left ${_plural(left, 'coche', 'coches')} de ${a.name}' else 'Fait pour aujourd’hui',
        if (n > 1) 'Puis chaque jour jusqu’au palier ($n j au total)',
      ],
      steps: [if (left > 0) QuestStep('routine:${a.id}', a, left, minutes: false)],
      fallsToday: n == 1 && left > 0,
    );
  }

  if (id == 'metronome' || id == 'montre-suisse') {
    final n = gap.ceil();
    if (n > kQuestMaxDays) return null;
    final steps = <QuestStep>[];
    if (facts != null && id == 'metronome') {
      for (final r in facts.metronomeRoutines) {
        if (!r.reached) steps.add(QuestStep('routine:${r.activity.id}', r.activity, r.target - r.done, minutes: false));
      }
    }
    if (facts != null && id == 'montre-suisse') {
      for (final p in facts.pace) {
        if (p.onPace) continue;
        final m = p.missingMin;
        steps.add(QuestStep('activity:${p.activity.id}', p.activity, m > kQuestStepMaxMin ? kQuestStepMaxMin : m, minutes: true));
      }
      // Trop d'activités en retard : la journée n'est plus jouable (`kWatchMaxBehind`).
      if (steps.length > 3) return null;
    }
    final what = id == 'metronome' ? 'toutes tes routines du jour' : 'chaque minimum couvert sur 7 jours';
    final today = steps.isEmpty
        ? 'Tenu pour aujourd’hui'
        : id == 'metronome'
            ? 'Ce soir il en reste ${steps.length} : ${steps.map((s) => s.activity.name).join(', ')}'
            : 'Ce soir : ${steps.map((s) => '${s.activity.name} ${s.label}').join(', ')}';
    final effort = steps.fold(0, (s, x) => s + (x.minutes ? x.amount : 3 * x.amount));
    return CardQuest(
      badge: b,
      kind: QuestKind.days,
      nextRarity: rarity,
      need: n == 1 ? '${_cap(what)} ce soir, et le palier tombe' : '${_cap(what)}, $n jours de suite',
      days: n,
      effortMin: effort,
      strategy: [today, if (n > 1) 'Puis $n jours au total'],
      steps: steps,
      fallsToday: n == 1 && steps.isNotEmpty && steps.every((s) => !s.minutes || s.amount < kQuestStepMaxMin),
    );
  }

  const modes = {'guerilla': 'guérilla', 'offensive': 'offensive', 'sniper': 'session Sniper'};
  if (modes.containsKey(id)) {
    final n = gap.ceil();
    if (n > kQuestMaxSessions) return null;
    final what = modes[id]!;
    final rule = switch (id) {
      'guerilla' => 'au moins 3 coups',
      'offensive' => 'au moins 3 coups',
      _ => 'au moins 3 cibles pleines',
    };
    return CardQuest(
      badge: b,
      kind: QuestKind.mode,
      nextRarity: rarity,
      need: n == 1 ? 'Une $what de plus' : '$n ${what}s de plus',
      days: n,
      effortMin: id == 'sniper' ? 30 : 15,
      strategy: ['Lancer une $what ($rule)'],
      modeKind: id,
    );
  }
  return null;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Les cartes à aller chercher : toutes les quêtes possibles, ce qui tombe le
/// plus vite d'abord (jours, puis effort du jour, puis la plus avancée).
List<CardQuest> cardQuests(BadgeDeck deck, {required List<Activity> activities, TodayFacts? facts, int? limit}) {
  final out = [
    for (final b in deck.badges)
      if (cardQuestOf(b, activities: activities, facts: facts) case final q?) q,
  ]..sort((a, b) {
      final d = a.days.compareTo(b.days);
      if (d != 0) return d;
      final e = a.effortMin.compareTo(b.effortMin);
      if (e != 0) return e;
      return (b.badge.progress ?? 0).compareTo(a.badge.progress ?? 0);
    });
  return limit == null || out.length <= limit ? out : out.sublist(0, limit);
}

/// Le gain « carte » posé sur les tirs d'une quête (puce du viseur).
StakeGain questGain(CardQuest q) => StakeGain(
      kind: StakeGainKind.hunt,
      label: 'carte ${q.badge.def.name}',
      detail: q.need,
      weight: 60,
      sourceId: q.badge.def.id,
    );

/// Les enjeux du Sniper ciblé : ceux du jour, où les tirs de la quête portent
/// le gain « carte » ; un tir sans enjeu du jour (compteur de coches d'une
/// routine déjà atteinte, heures d'une activité au rythme) est fabriqué.
List<Stake> focusStakes(List<Stake> stakes, CardQuest q) {
  final gain = questGain(q);
  final keys = {for (final s in q.steps) s.key};
  final out = [
    for (final s in stakes) keys.contains(s.gesture.key) ? Stake(s.gesture, [gain, ...s.gains]) : s,
  ];
  final have = {for (final s in out) s.gesture.key};
  for (final st in q.steps) {
    if (have.contains(st.key)) continue;
    final a = st.activity;
    out.add(Stake(
      StakeGesture(
        key: st.key,
        kind: st.minutes ? StakeGestureKind.activity : StakeGestureKind.routine,
        title: a.name,
        costMin: st.minutes ? st.amount : ((a.timerMin ?? 0) > 0 ? a.timerMin! : 5),
        activity: a,
      ),
      [gain],
    ));
  }
  return out;
}

/// Badge Chasseur de cartes (2026-11-03, idée user) : une carte prise d'un seul
/// Sniper ciblé = tous ses tirs touchés en entier, et son palier tombait aujourd'hui.
const kCardHunterTiers = [1, 5, 15, 50];

bool cardHunterCounts(ChainRun r) => r.kind == 'sniper' && r.cardTaken == true;

/// La carte est-elle prise ? [hitFull] = clés des tirs touchés en entier.
bool cardTakenBy(CardQuest q, Set<String> hitFull) => q.fallsToday && q.steps.every((s) => hitFull.contains(s.key));
