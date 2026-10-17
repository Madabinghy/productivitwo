import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/routine_chrono_pill.dart';
import 'package:productivitwo_v1/widgets/running_chrono_bar.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart'
    show kRoutineAccent, routineMinus, routinePlus, routineTodayCount;
import 'package:wakelock_plus/wakelock_plus.dart';

/// « Enchaîner les routines » (handoff Segment Routines, lot 2) : la file du
/// moment, une routine par écran — compteur − x / y + sur place, « Suivante »
/// selon le compteur (rien saisi : inactif ; partiel : « Garder 1 / 2 » ;
/// cible atteinte : plein), « Pas maintenant ▾ » (fin de file / report à un
/// moment plus tard), « Pas aujourd'hui ». Écran de fin : « Matin terminé ·
/// 5 sur 5 », reportées, « La suite : à 11 h 30 (midi) ».
Future<void> showRoutineChainScreen(BuildContext context, {required AppLogic logic}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _RoutineChainScreen(logic: logic),
  ));
}

class _RoutineChainScreen extends StatefulWidget {
  final AppLogic logic;
  const _RoutineChainScreen({required this.logic});

  @override
  State<_RoutineChainScreen> createState() => _RoutineChainScreenState();
}

class _RoutineChainScreenState extends State<_RoutineChainScreen> {
  late final List<String> _ids; // file au départ, réordonnée par « plus tard »
  late final Moment _moment;
  late final int _total;
  final Set<String> _passed = {};
  int _reached = 0, _pushedLater = 0, _dismissed = 0, _kept = 0;
  bool _laterMenu = false;

  AppLogic get logic => widget.logic;
  String get _ymd => yyyymmdd(DateTime.now());

  RoutineDay _day() => buildRoutineDay(
        activities: logic.state.activeActivities,
        hits: logic.state.habitHits,
        now: DateTime.now(),
        pushed: logic.routinePushed(_ymd),
        deferred: logic.state.nowSkippedByYmd[_ymd] ?? const [],
        dismissed: logic.nowDoneSet(_ymd),
      );

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    final d = _day();
    _moment = d.current;
    _ids = d.queue.map((s) => s.id).toList();
    _total = _ids.length;
    logic.addListener(_onLogic);
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    logic.removeListener(_onLogic);
    super.dispose();
  }

  RoutineSlot? _slotOf(String id, RoutineDay d) => d.slots.where((s) => s.id == id).firstOrNull;

  String? get _currentId => _ids.where((id) => !_passed.contains(id)).firstOrNull;

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _next(RoutineSlot s) {
    HapticFeedback.lightImpact();
    if (s.reached) {
      _reached++;
    } else {
      _kept++;
    }
    setState(() {
      _passed.add(s.id);
      _laterMenu = false;
    });
  }

  void _defer(RoutineSlot s) {
    final ymd = _ymd;
    final list = [...(logic.state.nowSkippedByYmd[ymd] ?? const <String>[])]..remove(s.id);
    list.add(s.id);
    logic.setNowSkipped(ymd, list.toSet());
    logic.state.nowSkippedByYmd[ymd] = list;
    // Restée d'un moment passé : rattachée au moment courant (même règle que
    // la vue Routines), elle quitte sa section d'origine pour la journée.
    final moved = momentOf(s.moment).timed && s.moment != _moment.key;
    if (moved) logic.setRoutinePushed(ymd, logic.routinePushed(ymd)..[s.id] = _moment.key);
    setState(() {
      _ids.remove(s.id);
      _ids.add(s.id);
      _laterMenu = false;
    });
    _toast(moved ? 'Reculée à ${_moment.thisOne} : ${s.activity.name}' : 'Reculée en fin de file : ${s.activity.name}');
  }

  void _pushTo(RoutineSlot s, Moment m) {
    final ymd = _ymd;
    logic.setRoutinePushed(ymd, logic.routinePushed(ymd)..[s.id] = m.key);
    _pushedLater++;
    setState(() {
      _passed.add(s.id);
      _laterMenu = false;
    });
    _toast('Reportée à ${m.thisOne} : ${s.activity.name}');
  }

  void _dismiss(RoutineSlot s) {
    final ymd = _ymd;
    logic.setNowDone(ymd, logic.nowDoneSet(ymd)..add(s.id));
    _dismissed++;
    setState(() {
      _passed.add(s.id);
      _laterMenu = false;
    });
    _toast('Pas aujourd\'hui : ${s.activity.name}');
  }

  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(milliseconds: 2600)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final d = _day();
    final id = _currentId;
    final slot = id == null ? null : _slotOf(id, d);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: slot == null ? _end(pal) : _focus(pal, d, slot),
        ),
      ),
    );
  }

  Widget _bar(NowPalette pal) {
    final processed = _passed.length;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: _total == 0 ? 1 : processed / _total, minHeight: 5, backgroundColor: pal.track, color: kRoutineAccent),
        ),
      ),
      const SizedBox(width: 10),
      Text('$processed / $_total',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
      IconButton(
        tooltip: 'Fermer',
        icon: Icon(Icons.close_rounded, color: pal.text3),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ]);
  }

  Widget _round(NowPalette pal, String label, VoidCallback? onTap, {Color? bg, Color? fg}) => SizedBox(
        width: 56,
        height: 56,
        child: Material(
          color: onTap == null ? pal.chip : (bg ?? pal.chip),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: onTap == null ? Colors.white.withOpacity(.18) : (fg ?? pal.text2))),
            ),
          ),
        ),
      );

  Widget _focus(NowPalette pal, RoutineDay d, RoutineSlot s) {
    final a = s.activity;
    final todayN = routineTodayCount(logic, a);
    final dayTarget = s.todo.dayTarget;
    final count = dayTarget != null ? s.todo.dayDone : s.todo.weekDone;
    final target = dayTarget ?? s.todo.weekTarget;
    final reached = s.reached;
    final domainName = logic.state.domains.where((x) => x.id == a.domainId).map((x) => x.name).firstOrNull ?? '';
    final domainC = domainColor(a.domainId, logic.state.domains) ?? kRoutineAccent;
    final nextId = _ids.where((x) => !_passed.contains(x) && x != s.id).firstOrNull;
    final next = nextId == null ? null : _slotOf(nextId, d);
    final idx = _passed.length + 1;

    final Widget primary;
    if (reached) {
      primary = FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: kRoutineAccent, foregroundColor: kBBg, shape: const StadiumBorder(), minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        onPressed: () => _next(s),
        child: const Text('Cible atteinte — suivante'),
      );
    } else if (count > 0) {
      primary = OutlinedButton(
        style: OutlinedButton.styleFrom(
            foregroundColor: kRoutineAccent,
            side: BorderSide(color: kRoutineAccent.withOpacity(.6)),
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        onPressed: () => _next(s),
        child: Text('Garder $count / $target — suivante'),
      );
    } else {
      primary = OutlinedButton(
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white.withOpacity(.22),
            side: BorderSide(color: Colors.white.withOpacity(.08)),
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        onPressed: null,
        child: const Text('Suivante'),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bar(pal),
      RunningChronoBar(logic: logic),
      const SizedBox(height: 6),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: kRoutineAccent.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
          child: Text('Routine · $idx / $_total',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: kRoutineAccent)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('${_moment.label} · ${_moment.window}',
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, color: pal.text3)),
        ),
      ]),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (s.moment != _moment.key) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: kBAttention.withOpacity(.14), borderRadius: BorderRadius.circular(6)),
                  child: Text('Restée ${momentOf(s.moment).of}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: kBAttention)),
                ),
                const SizedBox(height: 14),
              ],
              Icon(a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.repeat_rounded,
                  size: 72, color: kRoutineAccent),
              const SizedBox(height: 14),
              Text(a.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15, color: pal.text)),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: domainC, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('$domainName · ${s.todo.progressLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ]),
              const SizedBox(height: 14),
              // Chrono de la routine sans sortir : passer à la suivante et
              // lancer son activité enchaîne les chronos.
              RoutineChronoPill(logic: logic, routine: a, centered: true, onChanged: () => setState(() {})),
            ]),
          ),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _round(pal, '−', todayN > 0 || (dayTarget == null && s.todo.weekDone > 0) ? () {
          if (routineMinus(logic, a)) HapticFeedback.selectionClick();
          setState(() {});
        } : null),
        const SizedBox(width: 28),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$count / $target',
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w800, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
          Text(dayTarget != null ? 'AUJOURD\'HUI' : 'CETTE SEMAINE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
        ]),
        const SizedBox(width: 28),
        _round(pal, '+', () {
          HapticFeedback.lightImpact();
          routinePlus(logic, a);
          setState(() {});
        }, bg: kRoutineAccent, fg: kBBg),
      ]),
      const SizedBox(height: 16),
      primary,
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: pal.text,
                backgroundColor: _laterMenu ? pal.track : null,
                side: BorderSide(color: Colors.white.withOpacity(.14)),
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(48)),
            onPressed: () => setState(() => _laterMenu = !_laterMenu),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              const Flexible(
                  child: Text('Pas maintenant',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700))),
              Icon(_laterMenu ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: pal.text,
                side: BorderSide(color: Colors.white.withOpacity(.14)),
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(48)),
            onPressed: () => _dismiss(s),
            child: const Text('Pas aujourd\'hui', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
      if (_laterMenu) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip('Plus tard ${_moment.thisOne}', () => _defer(s)),
          for (final m in d.laterMoments) _chip(m.thisOne[0].toUpperCase() + m.thisOne.substring(1), () => _pushTo(s, m)),
        ]),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.track))),
        child: Row(children: [
          Text('Ensuite', style: TextStyle(fontSize: 12, color: pal.text3)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(next == null ? 'Rien d\'autre : c\'est la dernière.' : next.activity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text2)),
          ),
        ]),
      ),
    ]);
  }

  Widget _chip(String label, VoidCallback onTap) => SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              foregroundColor: kRoutineAccent,
              side: BorderSide(color: kRoutineAccent.withOpacity(.4)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          child: Text(label),
        ),
      );

  Widget _end(NowPalette pal) {
    final n = nextMomentAfter(_moment);
    final parts = <String>[
      if (_kept > 0) '$_kept gardée${_kept > 1 ? 's' : ''} en cours',
      if (_pushedLater > 0) '$_pushedLater reportée${_pushedLater > 1 ? 's' : ''} plus tard',
      if (_dismissed > 0) '$_dismissed reportée${_dismissed > 1 ? 's' : ''} à demain',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bar(pal),
      RunningChronoBar(logic: logic),
      const Spacer(),
      Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: kRoutineAccent.withOpacity(.16), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: kRoutineAccent, size: 32),
        ),
      ),
      const SizedBox(height: 16),
      Text('${_moment.label.toUpperCase()} TERMINÉ',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: kRoutineAccent)),
      const SizedBox(height: 6),
      Text('$_reached sur $_total',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 4),
      Text(parts.isEmpty ? 'Toutes les routines du moment sont faites.' : parts.join(' · '),
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: pal.text3)),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.track)),
        child: Text(
          n == null ? 'La suite : demain matin.' : 'La suite : à ${n.window.split(' → ').first} (${n.label.toLowerCase()})',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.text2),
        ),
      ),
      const Spacer(),
      FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: kRoutineAccent, foregroundColor: kBBg, shape: const StadiumBorder(), minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Revenir à Aujourd\'hui'),
      ),
    ]);
  }
}
