import 'package:productivitwo_v1/gamification_flags.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:productivitwo_v1/app_font.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/run_session_store.dart' show RunSessionStore, dropShortSession;
import 'package:productivitwo_v1/sniper_now.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleSniper;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/run_session.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/sniper_scope.dart';
import 'package:productivitwo_v1/widgets/sniper_scope.dart';
import 'package:productivitwo_v1/utils/card_quests.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart' show rarityLabel;
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/confirm_done.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:productivitwo_v1/widgets/objective_readings_card.dart' show noteReadingQuick;
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setActionDone;

export 'package:productivitwo_v1/widgets/sniper_scope.dart' show kSniperAccent, kSniperInk;

/// Écran Sniper (maquette validée 2026-11-01, « Sniper en lunette » 2026-11-20) :
/// le viseur (la lunette = le temps libre, un arc par cible), un tir à la fois
/// (la lunette-minuteur, alarme), l'impact d'une seconde et demie au « Suivant »,
/// et le bilan (carton de tir, précision, badge). Logique : `utils/sniper.dart`,
/// dessins : `widgets/sniper_scope.dart`.
const _bg = Color(0xFF0A1218);
const _card = Color(0xFF13202A);
const _card2 = Color(0xFF1A2A35);
const _line = Color(0xFF24384A);
const _text2 = Color(0xFFB4C8D4);
const _text3 = Color(0xFF8DA2AF);
const _green = kSniperGreen;
const _amber = Color(0xFFF5B041);

/// [focus] = Sniper ciblé sur une carte (2026-11-03) : ses tirs en tête, le reste décoché.
/// Le Sniper s'ouvre en FEUILLE (2026-11-20, demande user : une feuille normale, sans croix) :
/// même mécanique que la page focus — `DraggableScrollableSheet` dont le contrôleur pilote la
/// liste de l'écran ; tirer vers le bas, depuis la liste remontée en haut ou une zone fixe,
/// la referme. Fermée pendant un tir, la session continue (voir `dispose`).
Future<void> showSniperScreen(BuildContext context, AppLogic logic, {BadgeCenter? badges, PendingRun? resume, CardQuest? focus}) {
  return Navigator.of(context).push(ModalBottomSheetRoute<void>(
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: .95,
      minChildSize: .5,
      maxChildSize: .95,
      expand: false,
      builder: (ctx, scroll) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Stack(children: [
          Positioned.fill(child: SniperScreen(logic: logic, badges: badges, resume: resume, focus: focus, sheetScroll: scroll)),
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const Key('sniper-sheet-handle'),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
        ]),
      ),
    ),
  ));
}

enum _Phase { aim, shot, hit, end }

class SniperScreen extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  final PendingRun? resume;
  final CardQuest? focus;

  /// Enjeux fournis tels quels (tests d'écran : pas de deck de badges).
  @visibleForTesting
  final List<Stake>? stakes;

  /// Le moment à suivre quand [stakes] est fourni (tests) ; sinon il est lu sur la journée.
  final SniperScope? scope;

  /// Le contrôleur de la feuille qui porte l'écran : il pilote la liste de chaque étape.
  final ScrollController? sheetScroll;
  const SniperScreen({super.key, required this.logic, this.badges, this.resume, this.focus, this.stakes, this.scope, this.sheetScroll});

  @override
  State<SniperScreen> createState() => _SniperScreenState();
}

class _SniperScreenState extends State<SniperScreen> with SingleTickerProviderStateMixin {
  List<Stake> _stakes = const [];
  CardQuest? _focus;

  /// Sniper par moment : les routines du moment, ce qui reste d'avant, ce qui attend plus tard.
  /// Null pour un Sniper ciblé sur une carte.
  SniperScope? _scope;
  bool _laterOpen = false;
  Map<String, int> _routineLeft = const {};
  double _factor = 1;
  int _endMin = 22 * 60;
  final _excluded = <String>{};

  /// Cibles hors de portée ajoutées à la main.
  final _added = <String>{};

  /// Tirs ajustés à la main : coches ou minutes par cible.
  final _amounts = <String, int>{};

  /// Ordre des tirs posé à la main (null = l'ordre conseillé).
  List<String>? _order;

  /// Le plan calculé une fois ; les écarts et ajouts s'appliquent dessus.
  SniperPlan _base = const SniperPlan(budgetMin: 0);
  SniperPlan _plan = const SniperPlan(budgetMin: 0);
  ({int minutes, int untilMin, ScheduleBlock? until}) _budget = (minutes: 0, untilMin: 0, until: null);
  bool _loading = true;

  // Session
  List<SniperTarget> _aimed = const [];
  int _aimedMin = 0;
  int _index = 0;
  final _hit = <String>[];
  final _skipped = <String>{};
  final _fired = <String, int>{}; // minutes tirées par cible
  _Phase _phase = _Phase.aim;
  DateTime? _startedAt;
  DateTime? _shotStart;
  DateTime? _endsAt;
  int? _pausedLeft; // secondes restantes quand le tir est en pause
  int _remaining = 0;
  Timer? _timer;

  /// L'impact entre deux tirs (une seconde et demie, toucher = tout de suite).
  /// Créé dans `initState` : un `late final` paresseux serait créé au démontage
  /// quand aucun impact n'a eu lieu, ce qui casse sous les versions de Flutter de la CI.
  late final AnimationController _impact;

  /// La vibration de fin de minuteur n'est donnée qu'une fois par tir.
  bool _buzzed = false;
  bool _ownChrono = false;
  bool _saved = false;
  /// Le viseur a été retouché (écarter, remettre, régler, ordonner) : la sélection est gardée à la fermeture.
  bool _touched = false;

  /// Sniper PRÊT (demande user 2026-11-21) : préparé sans être lancé. Rouvert, il garde sa
  /// sélection ; « Tirer » le lance, « Je m'arrête » l'abandonne et remet l'ordre conseillé.
  bool _prepared = false;

  /// Sorti du Sniper pendant un tir (« Faire ça dans l'app », bug user 2026-11-03 : une cible
  /// Planification se fait dans l'app, l'écran plein la bloquait) : minuteur, alarme et chrono continuent.
  bool _away = false;
  String? _lastHit;
  late final String _runId = widget.resume?.runId ?? ChainRun(date: '', startedAt: DateTime(0), endedAt: DateTime(0), doneCount: 0, total: 0, completed: false).id;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    // L'impact se joue puis attend : le tir suivant se lance à la main (retour user 2026-11-21).
    _impact = AnimationController(vsync: this, duration: kSniperImpact, animationBehavior: AnimationBehavior.preserve);
    WakelockPlus.enable().catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await logic.sync?.fetchDayWindow();
      if (w != null) _endMin = w.endMin;
    } catch (_) {}
    if (widget.badges != null && widget.badges!.deck == null) {
      try {
        await widget.badges!.load();
      } catch (_) {}
    }
    if (!mounted) return;
    _compute();
    final r = widget.resume;
    if (r != null) r.prepared ? _restorePrepared(r) : _restore(r);
    setState(() => _loading = false);
  }

  void _compute() {
    final now = sniperStakesNow(logic, widget.badges);
    _routineLeft = now.routineLeft;
    _stakes = widget.stakes ?? now.stakes;
    _focus = widget.focus ?? _resumedFocus();
    if (_focus case final q?) _stakes = focusStakes(_stakes, q);
    _factor = sniperFactorNow(logic);
    _scope = _focus != null ? null : (widget.stakes != null ? widget.scope : sniperScopeNow(logic));
    _budget = sniperBudgetNow(logic, endMin: _endMin, scope: _scope);
    _replan();
    if (_focus case final q? when widget.resume == null) _aimAt(q);
  }

  /// Session ciblée reprise : la quête est recalculée depuis le deck.
  CardQuest? _resumedFocus() {
    final id = widget.resume?.extra['focus'];
    final deck = widget.badges?.deck;
    if (id is! String || deck == null) return null;
    final b = deck.byId(id);
    if (b == null) return null;
    return cardQuestOf(b, activities: logic.state.activities, facts: widget.badges?.todayFacts());
  }

  /// Le viseur ne garde que les tirs de la carte, à leur montant, en tête ;
  /// les autres enjeux restent proposés, écartés.
  void _aimAt(CardQuest q) {
    final keys = [for (final s in q.steps) s.key];
    _added.addAll(keys);
    _excluded.addAll([for (final t in _base.aimed) if (!keys.contains(t.key)) t.key]);
    final byKey = {
      for (final s in _stakes)
        if (_targetOf(s) case final t?) t.key: t,
    };
    for (final st in q.steps) {
      final t = byKey[st.key];
      if (t != null && t.amount != st.amount) _amounts[st.key] = st.amount;
    }
    _order = keys;
    _adjust();
  }

  SniperTarget? _targetOf(Stake s) => sniperTargetOf(s, routineLeft: _routineLeft, factor: _factor, scope: _scope);

  void _replan() {
    _base = planSniper(
      stakes: _stakes,
      budgetMin: _budget.minutes,
      untilMin: _budget.untilMin,
      routineLeft: _routineLeft,
      factor: _factor,
      scope: _scope,
    );
    _adjust();
  }

  /// La part d'une routine répartie change avec le moment : son montant est toujours gardé.
  bool _keepsAmount(SniperTarget t) => t.amount != t.need || (_scope?.shareLeft.containsKey(t.key) ?? false);

  /// Écarter retire vraiment la cible (le temps visé baisse) ; rien de hors
  /// de portée ne rentre sans qu'on le choisisse.
  void _adjust() => _plan = adjustPlan(_base, excluded: _excluded, added: _added, amounts: _amounts, order: _order);

  void _reorder(int from, int to) {
    final keys = [for (final t in _plan.aimed) t.key];
    if (to > from) to -= 1;
    final k = keys.removeAt(from);
    keys.insert(to, k);
    setState(() {
      _order = keys;
      _touched = true;
      _adjust();
    });
  }

  void _step(SniperTarget t, {required bool up}) {
    final a = stepAmount(t, up: up);
    if (a == null) return;
    final next = t.withAmount(a);
    if (up && !fitsPlan(_plan, next)) {
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(content: Text('Plus de temps libre pour agrandir « ${t.title} » : réduis ou écarte une autre cible.')));
      return;
    }
    setState(() {
      if (a == t.need) {
        _amounts.remove(t.key);
      } else {
        _amounts[t.key] = a;
      }
      _touched = true;
      _adjust();
    });
  }

  void _include(SniperTarget t, {required bool fromOut}) {
    if (!fitsPlan(_plan, t)) {
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(content: Text('« ${t.title} » ne tient plus dans ton temps libre : écarte une autre cible d’abord.')));
      return;
    }
    setState(() {
      _excluded.remove(t.key);
      if (fromOut) _added.add(t.key);
      if (_order case final o?) _order = [...o.where((k) => k != t.key), t.key];
      _touched = true;
      _adjust();
    });
  }

  /// Les cibles écartées à la main (pour les remettre).
  List<SniperTarget> get _excludedTargets => [
        for (final s in _stakes)
          if (_excluded.contains(s.gesture.key)) _targetOf(s),
      ].whereType<SniperTarget>().toList();

  /// Remet le viseur comme il a été préparé : les mêmes cibles, à leurs montants, dans leur
  /// ordre. Une cible tombée depuis (faite ailleurs) n'y est plus ; s'il ne reste rien, le
  /// Sniper préparé est oublié.
  void _restorePrepared(PendingRun r) {
    final keys = r.strings('aimed');
    final amounts = r.extra['amounts'] is Map ? r.extra['amounts'] as Map : const {};
    _excluded
      ..clear()
      ..addAll([for (final t in _base.aimed) if (!keys.contains(t.key)) t.key]);
    _added
      ..clear()
      ..addAll(keys);
    _amounts.clear();
    amounts.forEach((k, v) {
      if (v is num && v > 0) _amounts[k.toString()] = v.toInt();
    });
    _order = r.extra['ordered'] == true ? keys : null;
    _adjust();
    if (_plan.aimed.isEmpty) {
      RunSessionStore.clear();
      _resetSelection();
      return;
    }
    _prepared = true;
  }

  void _resetSelection() {
    _excluded.clear();
    _added.clear();
    _amounts.clear();
    _order = null;
    _touched = false;
    _prepared = false;
    if (_focus case final q?) {
      _aimAt(q);
    } else {
      _adjust();
    }
  }

  /// « Je m'arrête » au viseur : le Sniper préparé est abandonné, l'ordre conseillé revient.
  void _drop() {
    final cur = RunSessionStore.current;
    if (cur != null && cur.kind == kSniperKind && cur.prepared) RunSessionStore.clear();
    setState(_resetSelection);
    ScaffoldMessenger.maybeOf(context)?.showClosingSnackBar(const SnackBar(content: Text('Sniper abandonné · l’ordre conseillé est revenu'), duration: Duration(seconds: 3)));
  }

  /// Garde le viseur tel quel, sans rien lancer. Faux quand une autre session en attente
  /// (Guérilla, Offensive…) tient déjà la place.
  bool _persistPrepared() {
    final cur = RunSessionStore.current;
    if (cur != null && cur.kind != kSniperKind && cur.isLive(DateTime.now(), logic.livedTodayYmd)) return false;
    final now = DateTime.now();
    RunSessionStore.save(PendingRun(
      kind: kSniperKind,
      runId: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: now,
      lastActiveAt: now,
      done: 0,
      extra: {
        'prepared': true,
        'aimed': [for (final t in _plan.aimed) t.key],
        'amounts': {
          for (final t in _plan.aimed)
            if (_keepsAmount(t)) t.key: t.amount
        },
        'ordered': _order != null,
        'aimedMin': _plan.totalMin,
        'total': _plan.aimed.length,
        if (_focus case final q?) 'focus': q.badge.def.id,
      },
    ));
    return true;
  }

  void _restore(PendingRun r) {
    final keys = r.strings('aimed');
    final amounts = r.extra['amounts'] is Map ? r.extra['amounts'] as Map : const {};
    final byKey = {
      for (final s in _stakes)
        if (_targetOf(s) case final t?) t.key: t,
    };
    _startedAt = r.startedAt;
    _hit.addAll(r.strings('hit'));
    _skipped.addAll(r.strings('skipped'));
    _aimedMin = r.intOf('aimedMin') ?? 0;
    final fired = r.extra['fired'];
    if (fired is Map) fired.forEach((k, v) => _fired[k.toString()] = (v as num).toInt());
    // Une cible qui a disparu des enjeux est tombée ailleurs : elle compte
    // touchée (seulement si les enjeux ont pu être recalculés).
    final known = widget.badges?.deck != null;
    final snaps = r.extra['snap'] is Map ? r.extra['snap'] as Map : const {};
    final aimed = <SniperTarget>[];
    for (final k in keys) {
      final t = byKey[k];
      final a = amounts[k];
      if (t != null) {
        aimed.add(a is num && a > 0 && t.adjustable ? t.withAmount(a.toInt()) : t);
        continue;
      }
      // Plus dans les enjeux : déjà touchée, passée, ou tombée ailleurs. Elle garde sa place grâce à sa trace.
      if (known && !_hit.contains(k) && !_skipped.contains(k)) _hit.add(k);
      if (!_hit.contains(k) && !_skipped.contains(k)) continue;
      if (sniperFromSnapshot(k, snaps[k]) case final gone?) aimed.add(gone);
    }
    _aimed = aimed;
    _totalAimed = keys.length;
    // Retour d'une sortie dans l'app : le tir en cours continue (minuteur, chrono, alarme).
    final cur = r.extra['cur'];
    final ci = cur is String ? _aimed.indexWhere((t) => t.key == cur) : -1;
    if (ci >= 0 && !_hit.contains(cur) && !_skipped.contains(cur)) {
      final ends = r.intOf('endsAt'), start = r.intOf('shotStart');
      _index = ci;
      _phase = _Phase.shot;
      _shotStart = start == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(start);
      _endsAt = ends == null ? null : DateTime.fromMillisecondsSinceEpoch(ends);
      _pausedLeft = r.intOf('paused');
      _ownChrono = r.extra['own'] == true && logic.state.sessions.any((x) => x.endAt == null);
      if (_endsAt != null) {
        final left = _endsAt!.difference(DateTime.now()).inSeconds;
        _remaining = left > 0 ? left : 0;
        _ticking();
      }
      _persist();
      return;
    }
    if (logic.state.sessions.any((x) => x.endAt == null && !x.startAt.isBefore(r.startedAt))) logic.stopActive(notify: false);
    final n = _nextIndex(-1);
    if (n == null) {
      _phase = _Phase.end;
      return;
    }
    // Rouvert entre deux tirs : le dernier touché reste affiché, le tir suivant attend ton signal.
    final last = r.strings('hit').reversed.map((k) => _aimed.indexWhere((t) => t.key == k)).where((i) => i >= 0).firstOrNull;
    if (last != null) {
      _index = last;
      _lastHit = _aimed[last].key;
      _phase = _Phase.hit;
      _impact.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enter(n);
    });
  }

  int _totalAimed = 0;

  int? _nextIndex(int from) {
    for (var i = from + 1; i < _aimed.length; i++) {
      final k = _aimed[i].key;
      if (!_hit.contains(k) && !_skipped.contains(k)) return i;
    }
    return null;
  }

  Session? get _runningBefore => logic.state.sessions.where((x) => x.endAt == null).firstOrNull;

  void _persist({bool away = false}) {
    if (_startedAt == null) return;
    final cur = _phase == _Phase.shot && _index < _aimed.length ? _aimed[_index] : null;
    final now = DateTime.now();
    RunSessionStore.save(PendingRun(
      kind: kSniperKind,
      runId: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt!,
      // Sorti pendant un tir : la session reste reprenable jusqu'au bout du minuteur, puis la fenêtre habituelle.
      lastActiveAt: away && _endsAt != null && _endsAt!.isAfter(now) ? _endsAt! : now,
      done: _hit.length,
      extra: {
        'aimed': [for (final t in _aimed) t.key],
        'snap': {for (final t in _aimed) t.key: sniperSnapshot(t)},
        'amounts': {
          for (final t in _aimed)
            if (_keepsAmount(t)) t.key: t.amount
        },
        'hit': _hit,
        'skipped': _skipped.toList(),
        'fired': _fired,
        'aimedMin': _aimedMin,
        if (_focus case final q?) 'focus': q.badge.def.id,
        'full': _fullHits,
        'total': _totalAimed,
        if (away && cur != null) ...{
          'cur': cur.key,
          if (_endsAt case final e?) 'endsAt': e.millisecondsSinceEpoch,
          if (_shotStart case final s?) 'shotStart': s.millisecondsSinceEpoch,
          if (_pausedLeft case final p?) 'paused': p,
          'own': _ownChrono,
        },
      },
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _impact.dispose();
    // La feuille refermée pendant un tir (tirée vers le bas, touchée à côté, retour) ne
    // l'arrête pas : minuteur, alarme et chrono continuent, la session attend avec ce tir en
    // cours, comme « Faire ça dans l'app ». Seul « Je m'arrête » met fin au Sniper.
    if (!_away && _phase == _Phase.shot && _startedAt != null && _index < _aimed.length) {
      _away = true;
      _persist(away: true);
      final messenger = _messenger, text = _awayText;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger != null && messenger.mounted) messenger.showClosingSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
      });
    }
    if (!_away) {
      if (_startedAt != null) CoupAlarm.cancel();
      _stopOwnChrono();
    }
    if (!_saved && _phase == _Phase.end) {
      if (_hit.isNotEmpty) _save();
      RunSessionStore.clear();
    }
    // Refermé au viseur : une sélection retouchée (ou « Garder prêt ») attend, rien n'est lancé.
    if (_phase == _Phase.aim && !_loading && (_touched || _prepared)) {
      if (_plan.aimed.isEmpty) {
        if (RunSessionStore.current?.prepared ?? false) RunSessionStore.clear();
      } else if (_persistPrepared()) {
        final messenger = _messenger, n = _plan.aimed.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (messenger != null && messenger.mounted) {
            messenger.showClosingSnackBar(SnackBar(content: Text('Sniper prêt · $n cible${n > 1 ? 's' : ''} · il t’attend sur Aujourd’hui'), duration: const Duration(seconds: 3)));
          }
        });
      }
    }
    WakelockPlus.disable().catchError((_) {});
    // La session vient d'être gardée, close ou effacée : Aujourd'hui (tuile du mode, carte
    // « Reprendre ») se redessine une fois la feuille partie.
    final l = logic;
    WidgetsBinding.instance.addPostFrameCallback((_) => l.onChange());
    super.dispose();
  }

  // ── Tirs ─────────────────────────────────────────────────────────────────

  void _start() {
    if (_plan.aimed.isEmpty) return;
    if (_runningBefore != null) logic.stopActive(notify: false);
    _aimed = [..._plan.aimed];
    _totalAimed = _aimed.length;
    _aimedMin = _plan.totalMin;
    _startedAt = DateTime.now();
    _prepared = false;
    _enter(0);
  }

  void _enter(int i) {
    _timer?.cancel();
    _index = i;
    _phase = _Phase.shot;
    _pausedLeft = null;
    _buzzed = false;
    _shotStart = DateTime.now();
    final t = _aimed[i];
    if (t.minutes > 0) {
      _endsAt = DateTime.now().add(Duration(minutes: t.minutes));
      _remaining = t.minutes * 60;
      _arm(t);
      _startChrono(t);
      _ticking();
    } else {
      _endsAt = null;
    }
    _persist();
    setState(() {});
  }

  void _ticking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_tick);
    });
  }

  void _tick() {
    if (_phase != _Phase.shot || _endsAt == null || _pausedLeft != null) return;
    final left = _endsAt!.difference(DateTime.now()).inSeconds;
    _remaining = left > 0 ? left : 0;
    if (left <= 0 && !_buzzed) {
      _buzzed = true;
      HapticFeedback.heavyImpact();
    }
    // Au bout du minuteur, l'alarme sonne mais rien n'enchaîne (retour user 2026-11-07) :
    // le chrono continue, le temps en plus s'affiche, « Suivant » fait tomber la cible.
  }

  /// Secondes au-delà du minuteur (0 avant la fin) : le chrono, lui, continue.
  int get _overSec {
    if (_endsAt == null) return 0;
    final left = _pausedLeft ?? _endsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? -left : 0;
  }

  void _arm(SniperTarget t) => CoupAlarm.schedule(logic, endsAt: _endsAt!, title: '◎ Touché', body: '${t.title} · ${t.minutes} min pile');

  String? _chronoActivity(SniperTarget t) {
    final g = t.stake.gesture;
    switch (t.kind) {
      case SniperKind.timed:
        return g.activity?.id;
      case SniperKind.action:
        return g.action?.linkedActivityId ?? g.project?.linkedActivityId ?? g.owner?.id;
      case SniperKind.routine:
        return g.activity?.linkedActivityId;
      case SniperKind.reading:
        return null;
    }
  }

  void _startChrono(SniperTarget t) {
    if (logic.state.sessions.any((s) => s.endAt == null)) return;
    final act = _chronoActivity(t);
    if (act == null) return;
    final g = t.stake.gesture;
    logic.start(act, taskId: g.task?.id, actionId: g.action?.id);
    _ownChrono = true;
  }

  /// Tir de routine sans minuteur, routine liée à une activité : le chrono se lance d'ici, sans quitter le
  /// Sniper (retour user 2026-11-21 : Café). Un chrono lancé ailleurs est arrêté ; le tir qui tombe l'arrête.
  void _toggleRoutineChrono() {
    if (_ownChrono) {
      _stopOwnChrono();
    } else {
      if (_runningBefore != null) logic.stopActive(notify: false);
      _startChrono(_aimed[_index]);
    }
    _persist();
    setState(() {});
  }

  void _stopOwnChrono() {
    if (!_ownChrono) return;
    _ownChrono = false;
    dropShortSession(logic, logic.stopActive(notify: false));
  }

  void _togglePause() {
    if (_endsAt == null) return;
    if (_pausedLeft == null) {
      _pausedLeft = _endsAt!.difference(DateTime.now()).inSeconds;
      CoupAlarm.cancel();
      _stopOwnChrono();
    } else {
      _endsAt = DateTime.now().add(Duration(seconds: _pausedLeft!));
      _pausedLeft = null;
      _arm(_aimed[_index]);
      _startChrono(_aimed[_index]);
    }
    setState(() {});
  }

  void _more() {
    final now = DateTime.now();
    if (_pausedLeft != null) {
      _pausedLeft = _pausedLeft! + 300;
    } else {
      final base = _endsAt == null || _endsAt!.isBefore(now) ? now : _endsAt!;
      _endsAt = base.add(const Duration(minutes: 5));
      _buzzed = false;
      CoupAlarm.cancel(all: false);
      _arm(_aimed[_index]);
    }
    setState(_tick);
  }

  int get _firedNowMin {
    final t = _aimed[_index];
    if (t.minutes == 0 || _shotStart == null) return t.cost;
    if (_endsAt == null) return t.minutes;
    final planned = _endsAt!.difference(_shotStart!).inSeconds;
    final left = _pausedLeft ?? _endsAt!.difference(DateTime.now()).inSeconds;
    return ((planned - left) / 60).round().clamp(0, 1 << 20);
  }

  /// La cible tombe : on écrit ce qu'il faut (coches, action faite), puis pause.
  Future<void> _touch() async {
    if (_phase != _Phase.shot) return;
    final t = _aimed[_index];
    final g = t.stake.gesture;
    if (t.kind == SniperKind.action && g.action != null) {
      if (!await confirmDone(context, title: g.action!.title)) return;
      _markActionDone(t);
    }
    if (t.kind == SniperKind.routine && g.activity != null) {
      logic.incHabit(g.activity!.id, t.delta, livedDate(DateTime.now(), logic.dayStartMin));
    }
    _fired[t.key] = _firedNowMin;
    _finishShot(t);
  }

  Future<void> _noteReading() async {
    final t = _aimed[_index];
    final o = t.stake.gesture.objective;
    final sync = logic.sync;
    if (o == null || sync == null) return;
    final ok = await noteReadingQuick(context, sync: sync, objective: o);
    if (!ok || !mounted) return;
    _fired[t.key] = 1;
    _finishShot(t);
  }

  void _markActionDone(SniperTarget t) {
    final g = t.stake.gesture;
    final a = g.action!;
    setActionDone(a, true);
    if (g.project != null) {
      logic.sync?.patchActionOf(g.project!, a);
    } else if (g.owner != null) {
      logic.sync?.updateOwnActions(g.owner!.id, g.owner!.ownActions);
    }
    logic.onChange();
  }

  void _finishShot(SniperTarget t) {
    _timer?.cancel();
    CoupAlarm.cancel();
    _stopOwnChrono();
    _hit.add(t.key);
    _lastHit = t.key;
    _persist();
    // Un tir entier laisse un impact (lunette verte, vibration) ; un mini-tir passe
    // directement au suivant, avec le message d'avant.
    if (!t.isMini) {
      HapticFeedback.mediumImpact();
      setState(() => _phase = _Phase.hit);
      _impact.forward(from: 0);
      return;
    }
    final fired = _fired[t.key];
    if (t.minutes > 0 && fired != null) {
      ScaffoldMessenger.maybeOf(context)?.showClosingSnackBar(SnackBar(
        content: Text('Mini-tir · ${t.title} · ${fmtMin(fired)}'),
        duration: const Duration(seconds: 3),
      ));
    }
    _advance();
  }

  /// « Tirer » sur l'écran d'impact : le tir suivant, sinon le bilan. Une seule fois.
  void _afterImpact() {
    if (!mounted || _phase != _Phase.hit) return;
    _impact.stop();
    _advance();
  }

  /// Le tir suivant, sinon le bilan.
  void _advance() {
    final n = _nextIndex(_index);
    if (n == null) {
      setState(() => _phase = _Phase.end);
      return;
    }
    _enter(n);
  }

  void _skip() {
    _timer?.cancel();
    CoupAlarm.cancel();
    _stopOwnChrono();
    _skipped.add(_aimed[_index].key);
    _persist();
    final n = _nextIndex(_index);
    if (n == null) {
      setState(() => _phase = _Phase.end);
    } else {
      _enter(n);
    }
  }

  void _stop() {
    _timer?.cancel();
    _impact.stop();
    CoupAlarm.cancel();
    _stopOwnChrono();
    setState(() => _phase = _Phase.end);
  }

  /// Cibles touchées en entier : une cible tombée ailleurs (disparue des
  /// enjeux à la reprise) compte pleine.
  int get _fullHits => _hit.length - _aimed.where((t) => _hit.contains(t.key) && t.isMini).length;

  /// Sniper ciblé : la carte est prise si chacun de ses tirs est touché à son montant.
  bool get _cardTaken {
    final q = _focus;
    if (q == null) return false;
    final byKey = {for (final t in _aimed) t.key: t};
    final full = <String>{
      for (final st in q.steps)
        if (_hit.contains(st.key) && (byKey[st.key] == null || byKey[st.key]!.amount >= st.amount)) st.key,
    };
    return cardTakenBy(q, full);
  }

  void _save() {
    _saved = true;
    final now = DateTime.now();
    final run = ChainRun(
      id: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt ?? now,
      endedAt: now,
      doneCount: _hit.length,
      total: _totalAimed,
      completed: _nextIndex(_index) == null,
      kind: kSniperKind,
      fullCount: _fullHits,
      cardId: _focus?.badge.def.id,
      cardTaken: _focus == null ? null : _cardTaken,
    );
    logic.recordChainRun(run);
    logic.sync?.saveChainRun(run);
  }

  void _finish() {
    if (_hit.isNotEmpty) _save();
    _saved = true;
    RunSessionStore.clear();
    widget.badges?.load(refresh: true).ignore();
    Navigator.of(context).pop();
  }

  // ── Écrans ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: kAppFont).copyWith(scaffoldBackgroundColor: _bg),
      child: Scaffold(
        backgroundColor: _bg,
        body: DecoratedBox(
          // Le halo de la lunette derrière l'écran, vert le temps d'un impact.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -.55),
              radius: 1.1,
              colors: [_phase == _Phase.hit ? const Color(0xFF0F2A1E) : const Color(0xFF11222F), _bg],
              stops: const [0, .62],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kSniperAccent))
                  : switch (_phase) {
                      _Phase.aim => _aim(),
                      _Phase.shot => _shot(),
                      _Phase.hit => _impactView(),
                      _Phase.end => _end(),
                    },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header({Widget? trailing, String label = 'SNIPER', Color color = kSniperAccent, bool info = true}) => SizedBox(
        height: 48,
        child: Row(children: [
          Icon(Icons.gps_fixed, color: color, size: 20),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: color))),
          if (info) const InfoDot(kRuleSniper),
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
      );

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
        child: child,
      );

  Widget _primary(String label, VoidCallback? onTap, {double height = 56}) => SizedBox(
        height: height,
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: kSniperAccent,
            foregroundColor: kSniperInk,
            disabledBackgroundColor: kSniperAccent.withValues(alpha: .25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _outline(String label, VoidCallback? onTap) => SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        ),
      );

  Color _gainColor(StakeGain g) => sniperGainColor(g);

  /// [target] : une petite cible devant chaque enjeu (ce que le tir fait tomber).
  Widget _chips(List<StakeGain> gains, {bool target = false}) => Wrap(spacing: 5, runSpacing: 5, children: [
        for (final g in gains)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: target ? 4 : 2),
            decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(99), border: Border.all(color: _gainColor(g).withValues(alpha: .35))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (target) ...[SniperTargetDot(color: _gainColor(g)), const SizedBox(width: 6)],
              Flexible(child: Text(g.label, style: TextStyle(fontSize: target ? 12.5 : 11.5, color: _gainColor(g)))),
            ]),
          ),
      ]);

  String _hm(int min) {
    final m = min % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  /// [number] = le rang du tir, à la couleur de son arc dans la lunette (il remplace la case à cocher).
  /// [head] = le titre de sa partie du viseur, sur la première cible de la partie.
  Widget _targetRow(SniperTarget t, {required bool on, VoidCallback? onTap, String? reason, int? number, String? head}) {
    if (head != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.only(top: number == 1 ? 6 : 14, bottom: 2),
          child: Text(head,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: t.section == kSniperSecLeft ? const Color(0xFFFFB870) : _text3)),
        ),
        _targetRow(t, on: on, onTap: onTap, reason: reason, number: number),
      ]);
    }
    final mark = sniperTargetColor(t);
    final sub = switch (t.kind) {
      SniperKind.action => t.stake.gesture.action?.estimatedMin == null
          ? 'estimation par défaut'
          : 'estimé ${fmtMin(t.stake.gesture.action!.estimatedMin!)}${_factor > 1.05 ? ' · d’habitude ${_factor.toStringAsFixed(1).replaceAll('.', ',')}×' : ''}',
      SniperKind.timed => t.minutes > t.need ? 'il manque ${fmtMin(t.need)} · tu en fais plus' : 'il manque pile ${fmtMin(t.need)}',
      SniperKind.routine => t.stake.gesture.progress == null ? null : '${t.stake.gesture.progress} aujourd’hui',
      SniperKind.reading => 'une valeur à noter',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? mark : _line, width: 1.5)),
            child: on
                ? Text('${number ?? ''}', style: TextStyle(fontSize: 11, height: 1, fontWeight: FontWeight.w800, color: mark))
                : const Icon(Icons.add, size: 14, color: _text3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: reason == null ? Colors.white : _text3)),
              if (reason != null) Text(reason, style: const TextStyle(fontSize: 12.5, color: _text3)) else if (sub != null) Text(sub, style: const TextStyle(fontSize: 12.5, color: _text3)),
              if (on && t.isMini) Text(_miniLine(t), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kSniperAccent)),
              if (reason == null) ...[const SizedBox(height: 5), Opacity(opacity: on && t.isMini ? .4 : 1, child: _chips(t.gains))],
            ]),
          ),
          const SizedBox(width: 8),
          if (on && t.adjustable && kSniperTuningEnabled)
            _stepper(t)
          else
            Text(t.durLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: reason == null ? kSniperAccent : _text3, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }

  /// « mini-tir · il en restera 10 », « mini-tir · il restera 20 min ».
  String _miniLine(SniperTarget t) => t.kind == SniperKind.routine ? 'mini-tir · il en restera ${t.leftAfter}' : 'mini-tir · il restera ${fmtMin(t.leftAfter)}';

  Widget _stepBtn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        iconSize: 18,
        color: kSniperAccent,
        disabledColor: _line,
        icon: Icon(icon),
        onPressed: onTap,
      );

  Widget _stepper(SniperTarget t) {
    final down = stepAmount(t, up: false), up = stepAmount(t, up: true);
    // Un tap sur le réglage (bouton grisé, valeur) ne doit jamais tomber sur
    // la ligne, qui écarte la cible.
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onLongPress: () {},
        child: Container(
          decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _stepBtn(Icons.remove, 'Moins', down == null ? null : () => _step(t, up: false)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child:
                  Text(t.durLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kSniperAccent, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            _stepBtn(Icons.add, 'Plus', up == null ? null : () => _step(t, up: true)),
          ]),
        ));
  }

  Widget _aim() {
    final b = _budget;
    final total = _plan.totalMin;
    final until = b.until;
    final n = _plan.aimed.length;
    final air = b.minutes - total;
    // Le tour de la lunette = le temps libre ; chaque cible y prend un arc à sa durée.
    final scope = aimScope(costs: [for (final t in _plan.aimed) t.cost], freeMin: b.minutes, pauseMin: _plan.pauseMin);
    final excluded = _excludedTargets;
    final sc = _scope;
    // Les parties du viseur (reste d'avant, moment, le reste) tant que l'ordre est celui du Sniper.
    final parts = sc != null && _order == null && _plan.aimed.any((t) => t.section != kSniperSecOther);
    String? headOf(int i) {
      if (!parts) return null;
      final t = _plan.aimed[i];
      if (i > 0 && _plan.aimed[i - 1].section == t.section) return null;
      final own = sc.ritual && t.section == kSniperSecMoment ? ' · dans ton ordre' : '';
      return '${sc.sectionLabel(t.section)} · ${_plan.aimed.where((x) => x.section == t.section).length}$own';
    }

    final byMoment = sc?.before != null && until == null && b.untilMin == sc!.moment.endMin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(
        label: _prepared ? 'SNIPER PRÊT' : (sc == null ? 'SNIPER' : 'SNIPER · ${sc.momentLabel}'),
        trailing: _prepared || _touched
            ? TextButton(key: const Key('sniper-drop'), onPressed: _drop, child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))
            : null,
      ),
      Expanded(
        child: ListView(controller: widget.sheetScroll, children: [
          SniperAimScope(
            key: const Key('sniper-aim-scope'),
            scope: scope,
            colors: [for (final t in _plan.aimed) sniperTargetColor(t)],
            label: 'Lunette : ${fmtMin(total)} visées sur ${fmtMin(b.minutes)} libres, $n cible${n > 1 ? 's' : ''}',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('LIBRE JUSQU’À ${_hm(b.untilMin)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
              const SizedBox(height: 2),
              if (total < 60)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$total', style: const TextStyle(fontSize: 50, height: 1, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                  const TextSpan(text: ' min', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _text2)),
                ]))
              else
                Text(fmtMin(total), style: const TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text('visées sur ${fmtMin(b.minutes)}', style: const TextStyle(fontSize: 12, color: _text2)),
            ]),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(style: const TextStyle(fontSize: 13, height: 1.35, color: _text2), children: [
              TextSpan(text: n == 0 ? 'Aucune cible' : '$n cible${n > 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              if (until != null) TextSpan(text: ' avant « ${until.title} »') else if (byMoment) TextSpan(text: ' ${sc.before}'),
              TextSpan(text: air > 0 ? ' · il reste ${fmtMin(air)} d’air' : ' · tout ton temps libre est visé'),
            ]),
            key: const Key('sniper-aim-line'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_focus case final q?) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kSniperAccent.withValues(alpha: .7))),
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13.5, height: 1.35, color: _text2), children: [
                const TextSpan(text: 'Visée : '),
                TextSpan(text: q.badge.def.name, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                TextSpan(text: ' · carte ${rarityLabel(q.nextRarity).toLowerCase()}\n${q.need}'),
              ])),
            ),
          ],
          if (parts) const SizedBox(height: 10),
          if (!parts) Row(children: [
            Expanded(child: _label(_order == null || !kSniperTuningEnabled ? 'CE QUI TOMBE · CE QUI SE PERD CE SOIR D’ABORD' : 'CIBLES · DANS TON ORDRE')),
            if (_order != null && kSniperTuningEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextButton(
                  onPressed: () => setState(() {
                    _order = null;
                    _touched = true;
                    _adjust();
                  }),
                  child: const Text('Ordre conseillé', style: TextStyle(fontSize: 13, color: kSniperAccent)),
                ),
              ),
          ]),
          if (_plan.aimed.isEmpty)
            _box(Text(
                _stakes.isEmpty
                    ? 'Rien en jeu pour l’instant : pas de série à sauver, pas de minimum en retard, pas d’action visée.'
                    : 'Aucune cible ne tient dans ton temps libre. Regarde plus bas ce qui reste hors de portée.',
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: _text2)))
          else if (!kSniperTuningEnabled)
            _box(Column(children: [
              for (final (i, t) in _plan.aimed.indexed)
                _targetRow(t,
                    on: true,
                    number: i + 1,
                    head: headOf(i),
                    onTap: () => setState(() {
                          _excluded.add(t.key);
                          _added.remove(t.key);
                          _touched = true;
                          _adjust();
                        })),
            ]))
          else
            _box(ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, __) => Material(color: _card2, borderRadius: BorderRadius.circular(12), elevation: 6, child: child),
              onReorder: _reorder,
              children: [
                for (var i = 0; i < _plan.aimed.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(_plan.aimed[i].key),
                    index: i,
                    child: _targetRow(_plan.aimed[i],
                        on: true,
                        number: i + 1,
                        head: headOf(i),
                        onTap: () => setState(() {
                              _excluded.add(_plan.aimed[i].key);
                              _added.remove(_plan.aimed[i].key);
                              _touched = true;
                              _adjust();
                            })),
                  ),
              ],
            )),
          if (_plan.aimed.length > 1 && _order == null && kSniperTuningEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Appui long sur une cible pour la déplacer.', style: TextStyle(fontSize: 12, color: _text3)),
            ),
          if (excluded.isNotEmpty) ...[
            _label('ÉCARTÉES · TOUCHE POUR REMETTRE'),
            _box(Column(children: [
              for (final t in excluded) _targetRow(t, on: false, onTap: () => _include(t, fromOut: !_base.aimed.any((x) => x.key == t.key))),
            ])),
          ],
          if (_plan.outOfReach.isNotEmpty) ...[
            _label('HORS DE PORTÉE · TOUCHE POUR AJOUTER'),
            Opacity(
              opacity: .7,
              child: _box(Column(children: [for (final m in _plan.outOfReach) _targetRow(m.target, on: false, reason: m.reason, onTap: () => _include(m.target, fromOut: true))])),
            ),
          ],
          if (sc != null && _plan.later.isNotEmpty) ...[
            const SizedBox(height: 14),
            InkWell(
              key: const Key('sniper-later'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _laterOpen = !_laterOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                child: Row(children: [
                  Expanded(child: Text('Plus tard · ${sc.laterLine(_plan.later)}', style: const TextStyle(fontSize: 13, height: 1.35, color: _text3))),
                  const SizedBox(width: 8),
                  Text(_laterOpen ? 'replier' : 'ajouter', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kSniperAccent)),
                ]),
              ),
            ),
            if (_laterOpen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Opacity(
                  opacity: .7,
                  child: _box(Column(children: [for (final m in _plan.later) _targetRow(m.target, on: false, reason: m.reason, onTap: () => _include(m.target, fromOut: true))])),
                ),
              ),
          ],
          if (_runningBefore case final r?) ...[
            const SizedBox(height: 14),
            Text('Le chrono « ${logic.state.activities.where((a) => a.id == r.activityId).firstOrNull?.name ?? 'en cours'} » s’arrête au lancement : le Sniper prend la main.',
                style: const TextStyle(fontSize: 13, height: 1.4, color: kSniperAccent)),
          ],
          const SizedBox(height: 10),
          Text('Pause de $kSniperPauseMin min entre deux tirs · touche une cible pour l’écarter.', style: const TextStyle(fontSize: 12, color: _text3)),
        ]),
      ),
      const SizedBox(height: 12),
      _primary(_plan.aimed.isEmpty ? 'Rien à viser' : 'Tirer · $n cible${n > 1 ? 's' : ''} · ${fmtMin(total)}', _plan.aimed.isEmpty ? null : _start),
      if (_plan.aimed.isNotEmpty)
        Center(
          child: TextButton(
            key: const Key('sniper-keep'),
            onPressed: () {
              _prepared = true;
              Navigator.of(context).maybePop();
            },
            child: const Text('Garder prêt · je tire plus tard', style: TextStyle(color: _text2, fontSize: 14)),
          ),
        ),
    ]);
  }

  /// Le chargeur : un tir par cartouche.
  Widget _track() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SniperMagazine(rounds: [
          for (var i = 0; i < _aimed.length; i++)
            _hit.contains(_aimed[i].key)
                ? MagRound.done
                : _skipped.contains(_aimed[i].key)
                    ? MagRound.skipped
                    : i == _index && _phase == _Phase.shot
                        ? MagRound.current
                        : MagRound.todo,
        ]),
      );

  int get _shotNumber => _aimed.isEmpty ? 0 : _index + 1;

  Widget _nextLine() {
    final n = _nextIndex(_index);
    if (n == null) return const SizedBox.shrink();
    final t = _aimed[n];
    final after = _nextIndex(n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('ENSUITE'),
      _box(Text.rich(TextSpan(style: const TextStyle(fontSize: 13.5, color: _text2), children: [
        TextSpan(text: '${t.title} · '),
        TextSpan(text: t.durLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: kSniperAccent)),
        if (after != null) TextSpan(text: ' · puis ${_aimed[after].title}'),
      ]))),
    ]);
  }

  Widget _shot() {
    final t = _aimed[_index];
    final timed = t.minutes > 0;
    final total = timed ? (_endsAt != null && _shotStart != null ? _endsAt!.difference(_shotStart!).inSeconds : t.minutes * 60) : 1;
    final over = timed ? _overSec : 0;
    final left = (_pausedLeft ?? _remaining).clamp(0, 1 << 30).toInt();
    final shown = over > 0 ? over : left;
    final mm = (shown ~/ 60).toString();
    final ss = (shown % 60).toString().padLeft(2, '0');
    final endAt = _endsAt == null ? null : TimeOfDay.fromDateTime(_endsAt!);
    final chrono = _ownChrono ? logic.runningActivity()?.name : null;
    final action = t.kind == SniperKind.action;
    final linkedId = t.kind == SniperKind.routine ? _chronoActivity(t) : null;
    final linked = linkedId == null ? null : logic.state.activities.where((a) => a.id == linkedId && !a.deleted).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(label: 'TIR $_shotNumber / ${_aimed.length}', trailing: TextButton(onPressed: _stop, child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
      _track(),
      Expanded(
        child: ListView(controller: widget.sheetScroll, children: [
          const SizedBox(height: 12),
          if (timed)
            SniperShotScope(
              key: const Key('sniper-shot-scope'),
              size: 240,
              progress: total <= 0 ? 1 : (1 - left / total).clamp(0, 1).toDouble(),
              over: over > 0,
              // Le point des secondes fait le tour chaque minute ; à l'arrêt en pause.
              sweepDeg: _pausedLeft != null ? null : DateTime.now().second * 6.0,
              label: over > 0 ? 'Temps écoulé, $mm minutes $ss en plus' : 'Reste $mm minutes $ss',
              child: SizedBox(
                width: 158,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${over > 0 ? '+' : ''}$mm:$ss',
                      style: TextStyle(fontSize: 46, height: 1.05, fontWeight: FontWeight.w800, color: over > 0 ? _green : null, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(
                      _pausedLeft != null
                          ? 'en pause'
                          : over > 0
                              ? 'en plus · le chrono continue'
                              : left == 0
                                  ? 'temps écoulé'
                                  : 'sur ${t.minutes}:00${endAt == null ? '' : ' · fin à ${endAt.hour.toString().padLeft(2, '0')}:${endAt.minute.toString().padLeft(2, '0')}'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, height: 1.25, color: _text3)),
                ]),
              ),
            )
          else
            SniperShotScope(
              size: 200,
              label: t.durLabel,
              child: Text(t.durLabel, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: kSniperAccent)),
            ),
          const SizedBox(height: 14),
          Text(t.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            switch (t.kind) {
              SniperKind.timed when t.isMini => '${chrono != null ? 'chrono sur $chrono · ' : ''}${_miniLine(t)}',
              SniperKind.timed => chrono != null ? 'chrono sur $chrono · alarme à la fin' : 'alarme à la fin',
              SniperKind.routine when t.isMini => '${chrono != null ? 'chrono sur $chrono · ' : ''}${_miniLine(t)}',
              SniperKind.action => chrono != null ? 'chrono sur $chrono · l’action tombe quand elle est faite' : 'l’action tombe quand elle est faite',
              SniperKind.routine => '${chrono != null ? 'chrono sur $chrono · ' : ''}${t.delta > 1 ? '${t.delta} coches pour l’atteindre' : 'une coche pour l’atteindre'}',
              SniperKind.reading => 'note la valeur du jour',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: _text2),
          ),
          _label(t.isMini ? 'CE QUI TOMBERA AU BOUT' : 'CE TIR FAIT TOMBER'),
          Align(alignment: Alignment.centerLeft, child: Opacity(opacity: t.isMini ? .5 : 1, child: _chips(t.gains, target: true))),
          _nextLine(),
        ]),
      ),
      const SizedBox(height: 10),
      switch (t.kind) {
        SniperKind.timed => _primary(left == 0 ? 'Suivant ›' : 'Fait plus tôt · suivant', _touch, height: 56),
        SniperKind.action => _primary('Action faite', () => _touch(), height: 56),
        SniperKind.routine => _primary(timed && left > 0 ? 'Fait · +${t.delta}' : '+${t.delta} · touché', () => _touch(), height: 56),
        SniperKind.reading => _primary('Noter le relevé', _noteReading, height: 56),
      },
      const SizedBox(height: 10),
      Row(children: [
        if (timed) ...[
          Expanded(child: _outline(_pausedLeft != null ? 'Reprendre' : 'Pause', _togglePause)),
          const SizedBox(width: 8),
          if (over == 0) ...[
            Expanded(child: _outline('+5 min', _more)),
            const SizedBox(width: 8),
          ],
        ],
        if (!timed && t.kind == SniperKind.routine && linked != null) ...[
          Expanded(
            child: KeyedSubtree(
              key: const Key('sniper-routine-chrono'),
              child: _outline(_ownChrono ? '■ Arrêter le chrono' : '▶ Chrono · ${linked.name}', _toggleRoutineChrono),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: _outline(action ? 'Pas finie · suivante' : 'Passer', _skip)),
      ]),
      TextButton.icon(
        onPressed: _goAway,
        icon: const Icon(Icons.south_rounded, size: 16, color: _text2),
        label: Text(timed ? 'Faire ça dans l’app · le minuteur continue' : 'Faire ça dans l’app · reprendre ensuite',
            style: const TextStyle(color: _text2, fontSize: 13.5)),
      ),
    ]);
  }

  /// Sortir du Sniper sans l'arrêter : la session attend (carte « Reprendre » d'Aujourd'hui).
  void _goAway() {
    _away = true;
    _persist(away: true);
    ScaffoldMessenger.maybeOf(context)?.showClosingSnackBar(SnackBar(content: Text(_awayText), duration: const Duration(seconds: 4)));
    Navigator.of(context).pop();
  }

  String get _awayText => _endsAt == null ? 'Sniper en attente · reprends-le depuis Aujourd’hui' : 'Le minuteur continue · l’alarme sonnera à la fin';

  /// Gardé pour le message affiché quand la feuille se referme pendant un tir.
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  /// L'impact : une seconde et demie après « Suivant », puis le tir suivant (ou le bilan).
  Widget _impactView() {
    final t = _aimed.where((x) => x.key == _lastHit).firstOrNull ?? _aimed[_index];
    final fired = _fired[t.key] ?? t.cost;
    final gap = fired - t.cost;
    final n = _nextIndex(_index);
    final next = n == null ? null : _aimed[n];
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final detail = t.minutes > 0
        ? (gap == 0 ? '${fmtMin(fired)} pile · écart 0' : '${fmtMin(fired)} pour ${fmtMin(t.cost)} visées · ${gap > 0 ? '+' : '−'}${gap.abs()} min')
        : t.kind == SniperKind.reading
            ? 'relevé noté'
            : t.durLabel;
    return GestureDetector(
      key: const Key('sniper-impact'),
      behavior: HitTestBehavior.opaque,
      // Toucher l'écran finit l'animation, sans lancer le tir suivant.
      onTap: () {
        if (_impact.isAnimating) _impact.value = 1;
      },
      child: AnimatedBuilder(
        animation: _impact,
        builder: (context, _) {
          final v = still ? 1.0 : _impact.value;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(
                label: 'TIR $_shotNumber / ${_aimed.length}',
                color: _green,
                info: false,
                trailing: TextButton(onPressed: _stop, child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
            _track(),
            Expanded(
              child: ListView(controller: widget.sheetScroll, children: [
                const SizedBox(height: 8),
                SniperImpactScope(t: v, size: 230),
                const Text('TOUCHÉ', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 5, color: _green)),
                Text.rich(
                  TextSpan(style: const TextStyle(fontSize: 13.5, color: _text2), children: [
                    TextSpan(text: t.title, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                    TextSpan(text: ' · $detail'),
                  ]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                _label('VIENT DE TOMBER'),
                _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, g) in t.gains.indexed)
                    // Les enjeux se cochent l'un après l'autre.
                    Opacity(
                      opacity: ((v - .15 - i * .12) / .15).clamp(0, 1).toDouble(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: _green),
                            child: const Icon(Icons.check, size: 13, color: Color(0xFF04210F)),
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: Text(g.label, style: const TextStyle(fontSize: 14))),
                        ]),
                      ),
                    ),
                ])),
                _label(next == null ? 'ENSUITE' : 'TIR ${n! + 1} · QUAND TU VEUX'),
                _box(Text.rich(TextSpan(style: const TextStyle(fontSize: 13.5, color: _text2), children: [
                  if (next == null)
                    const TextSpan(text: 'Le bilan de la session')
                  else ...[
                    TextSpan(text: '${next.title} · '),
                    TextSpan(text: next.durLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: kSniperAccent)),
                  ],
                ]))),
              ]),
            ),
            const SizedBox(height: 10),
            KeyedSubtree(
              key: const Key('sniper-next'),
              child: _primary(next == null ? 'Voir le bilan' : 'Tirer · ${next.title}', _afterImpact, height: 56),
            ),
            const SizedBox(height: 10),
          ]);
        },
      ),
    );
  }

  Widget _end() {
    final hitTargets = _aimed.where((t) => _hit.contains(t.key)).toList();
    final missed = _aimed.where((t) => !_hit.contains(t.key)).toList();
    final hitN = _hit.length;
    final counted = logic.state.chainRuns.where((r) => r.id != _runId && sniperCounts(r)).length + (sniperSessionCounts(hit: hitN, aimed: _totalAimed, full: _fullHits) ? 1 : 0);
    final nextTier = kSniperTiers.firstWhere((t) => t > counted, orElse: () => kSniperTiers.last);
    // Une cible tombée en dehors du Sniper (cochée ailleurs pendant une sortie) n'a pas de temps de tir : elle compte
    // touchée, mais ni sur le carton ni dans la précision, et l'écran le dit (retour user 2026-11-21 : 79 % pour un
    // carton presque parfait).
    final shot = hitTargets.where((t) => _fired.containsKey(t.key)).toList();
    final elsewhere = hitTargets.where((t) => !_fired.containsKey(t.key)).toList();
    final aimedShotMin = shot.fold<int>(0, (s, t) => s + t.cost);
    final firedShotMin = shot.fold<int>(0, (s, t) => s + _fired[t.key]!);
    final precision = sniperPrecision(aimedShotMin, firedShotMin);
    // Le carton : un impact par cible tirée dans le Sniper, au centre = pile le temps visé.
    final impacts = shotCard([
      for (final t in _aimed) (hit: _hit.contains(t.key) && _fired.containsKey(t.key), gapMin: t.minutes > 0 ? (_fired[t.key] ?? t.cost) - t.cost : 0, mini: t.isMini),
    ]);
    final rank = {for (final (i, t) in _aimed.indexed) t.key: i + 1};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(controller: widget.sheetScroll, children: [
          const SizedBox(height: 12),
          const Text('SESSION SNIPER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _text3)),
          const SizedBox(height: 6),
          Text(hitN == 0 ? 'Aucune cible cette fois' : '$hitN / $_totalAimed cible${_totalAimed > 1 ? 's' : ''} touchée${hitN > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800)),
          Text(sniperCountLine(hitN, _totalAimed, full: _fullHits), style: const TextStyle(fontSize: 13.5, color: _text2)),
          if (_focus case final q?) ...[
            const SizedBox(height: 10),
            _box(Row(children: [
              Icon(_cardTaken ? Icons.style : Icons.style_outlined, color: _cardTaken ? kSniperAccent : _text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _cardTaken
                      ? 'Carte prise : ${q.badge.def.name} · ${rarityLabel(q.nextRarity).toLowerCase()} · Chasseur de cartes +1'
                      : q.fallsToday
                          ? '${q.badge.def.name} : pas encore, un tir manque'
                          : '${q.badge.def.name} avance · ${q.need.toLowerCase()}',
                  style: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w700),
                ),
              ),
            ])),
          ],
          if (impacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            SniperShotCard(key: const Key('sniper-card'), impacts: impacts),
            const SizedBox(height: 4),
            const Text('au centre = pile le temps visé', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: _text3)),
          ],
          if (elsewhere.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('${elsewhere.map((t) => t.title).join(', ')} ${elsewhere.length > 1 ? 'faites' : 'faite'} ailleurs · hors carton',
                key: const Key('sniper-elsewhere'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _text3)),
          ],
          if (kSniperTuningEnabled) const SizedBox(height: 14),
          if (kSniperTuningEnabled) Row(children: [
            for (final (i, (v, l)) in [
              (fmtMin(firedShotMin), 'tirées'),
              (fmtMin(aimedShotMin), 'visées'),
              ('$precision %', elsewhere.isEmpty ? 'précision' : 'sur ${shot.length} tir${shot.length > 1 ? 's' : ''}'),
            ].indexed) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(l, style: const TextStyle(fontSize: 12, color: _text3)),
                  ]),
                ),
              ),
              if (i < 2) const SizedBox(width: 8),
            ],
          ]),
          if (hitTargets.isNotEmpty) ...[
            _label('TOMBÉ'),
            _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final t in hitTargets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Le numéro du tir, le même que sur le carton.
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(top: 1),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: _green),
                      child: Text('${rank[t.key] ?? ''}', style: const TextStyle(fontSize: 10.5, height: 1, fontWeight: FontWeight.w800, color: Color(0xFF04210F))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(
                            !_fired.containsKey(t.key)
                                ? 'faite ailleurs'
                                : t.isMini
                                    ? _miniLine(t)
                                    : t.gains.map((g) => g.label).join(' · '),
                            style: const TextStyle(fontSize: 12.5, color: _text3)),
                      ]),
                    ),
                  ]),
                ),
            ])),
          ],
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Pas tiré : ${missed.map((t) => t.title).join(' · ')}', style: const TextStyle(fontSize: 12.5, color: _amber)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kSniperInk, borderRadius: BorderRadius.circular(14), border: Border.all(color: kSniperAccent.withValues(alpha: .45))),
            child: Row(children: [
              const Icon(Icons.gps_fixed, color: kSniperAccent, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Sniper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kSniperAccent)),
                  Text(counted >= kSniperTiers.last ? '$counted sessions · tous les paliers' : '$counted / $nextTier sessions · palier $nextTier', style: const TextStyle(fontSize: 13, color: _text2)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: (counted / nextTier).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: _card2, color: kSniperAccent),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _primary('Terminer', _finish, height: 54),
    ]);
  }
}
