import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/routine_chrono_pill.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;

/// Orange des routines (handoff « Segment Routines », 2026-10).
const kRoutineAccent = Color(0xFFE07B39);

/// Occurrences d'aujourd'hui (depuis minuit) d'une routine.
int routineTodayCount(AppLogic logic, Activity a) {
  final n = DateTime.now();
  final midnight = DateTime(n.year, n.month, n.day);
  return logic.state.habitHits.where((h) => h.habitId == a.id && !h.ts.isBefore(midnight)).length;
}

/// −1 : même règle que « Le meilleur à faire » — le dernier incrément
/// enregistré saute (compteur ET hit), sur la journée vécue de ce hit.
/// Retourne false s'il n'y avait rien à retirer.
bool routineMinus(AppLogic logic, Activity a) {
  final hits = logic.state.habitHits.where((h) => h.habitId == a.id).toList()..sort((x, y) => x.ts.compareTo(y.ts));
  if (hits.isEmpty) return false;
  final t = hits.last.ts;
  final lived = t.hour * 60 + t.minute < 5 * 60 ? t.subtract(const Duration(days: 1)) : t;
  logic.incHabit(a.id, -1, DateTime(lived.year, lived.month, lived.day));
  return true;
}

/// +1 : incrémente et sort la routine des « Pas maintenant » du jour.
void routinePlus(AppLogic logic, Activity a) {
  logic.incHabit(a.id, 1, DateTime.now());
  final ymd = yyyymmdd(DateTime.now());
  if (logic.nowSkippedSet(ymd).contains(a.id)) {
    logic.setNowSkipped(ymd, logic.nowSkippedSet(ymd)..remove(a.id));
  }
}

/// Segment « Routines » d'Aujourd'hui : la journée vue par les routines —
/// carte « Routine du moment » (+1 / −1 / Pas maintenant ▾), puis la journée
/// par moments (moment courant ouvert, les autres repliés, « Toute la
/// journée » toujours ouverte). Les comptes passent par `AppLogic.incHabit` ;
/// « Pas maintenant » = fin de file (`nowSkippedSet`), « Pas aujourd'hui » =
/// écartée (`nowDoneSet`), « Cet après-midi » = report du jour
/// (`routinePushed`). Le moment de la routine n'est jamais modifié d'ici.
class RoutinesDayView extends StatefulWidget {
  final AppLogic logic;
  final VoidCallback? onOrganize;
  final void Function(RoutineDay day)? onChain;
  const RoutinesDayView({super.key, required this.logic, this.onOrganize, this.onChain});

  @override
  State<RoutinesDayView> createState() => _RoutinesDayViewState();
}

class _RoutinesDayViewState extends State<RoutinesDayView> {
  // Sections dépliées à la main (null = défaut : le moment courant).
  final Map<String, bool> _open = {};
  bool _laterMenu = false;
  // Routine gardée dans la carte une fois sa cible atteinte (série de +1 :
  // « Pompes » cible 1, dix pompes d'affilée), jusqu'à « Suivante ».
  String? _held;

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

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _plus(Activity a, {bool hold = false}) {
    HapticFeedback.lightImpact();
    routinePlus(logic, a);
    setState(() {
      if (hold) _held = a.id;
    });
  }

  /// La routine gardée reste en carte tant qu'elle a au moins une occurrence
  /// aujourd'hui (nouveau jour, −1 jusqu'à zéro ou écartée = relâchée).
  RoutineSlot? _heldSlot(RoutineDay day) {
    final id = _held;
    if (id == null) return null;
    final s = day.slots.where((x) => x.id == id).firstOrNull;
    if (s == null || day.dismissed.contains(id) || _todayCount(s.activity) == 0) return null;
    return s;
  }

  void _minus(Activity a) {
    if (!routineMinus(logic, a)) return;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  int _todayCount(Activity a) => routineTodayCount(logic, a);

  // ── Activité liée : chrono et liaison sans quitter Aujourd'hui ─────────────

  Activity? _linkedOf(Activity a) {
    final id = (a.linkedActivityId ?? '').trim();
    if (id.isEmpty) return null;
    return logic.state.activeActivities.where((x) => x.id == id).firstOrNull;
  }

  bool _isRunning(Activity linked) => logic.runningActivity()?.id == linked.id;

  /// ▶ = chrono libre sur l'activité liée (arrête l'éventuel chrono en cours) ;
  /// déjà dessus = stop.
  void _toggleChrono(Activity linked) {
    HapticFeedback.lightImpact();
    if (_isRunning(linked)) {
      logic.stopActive();
    } else {
      if (logic.runningActivity() != null) logic.stopActive();
      logic.start(linked.id);
    }
    logic.onChange();
    setState(() {});
  }

  Future<void> _openSheet(Activity a) async {
    await showRoutineSheet(context, logic: logic, habitId: a.id, day: DateTime.now(),
        onSaved: () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  /// Coche : atteint la cible d'un coup ; déjà atteinte : remet à zéro.
  void _toggleReach(RoutineSlot s) {
    final a = s.activity;
    if (s.reached) {
      final n = s.todo.dayTarget != null ? _todayCount(a) : 1;
      for (var i = 0; i < n; i++) {
        _minus(a);
      }
      return;
    }
    final missing = s.todo.dayTarget != null ? s.todo.dayTarget! - s.todo.dayDone : s.todo.weekTarget - s.todo.weekDone;
    HapticFeedback.lightImpact();
    for (var i = 0; i < (missing < 1 ? 1 : missing); i++) {
      logic.incHabit(a.id, 1, DateTime.now());
    }
    setState(() {});
  }

  void _defer(Activity a) {
    final ymd = _ymd;
    final list = [...(logic.state.nowSkippedByYmd[ymd] ?? const <String>[])]..remove(a.id);
    list.add(a.id);
    logic.setNowSkipped(ymd, list.toSet());
    logic.state.nowSkippedByYmd[ymd] = list; // l'ordre du report compte
    setState(() {
      _laterMenu = false;
      _held = null;
    });
    _toast('Reculée en fin de file : ${a.name}');
  }

  void _pushTo(Activity a, Moment m) {
    final ymd = _ymd;
    final pushed = logic.routinePushed(ymd)..[a.id] = m.key;
    logic.setRoutinePushed(ymd, pushed);
    setState(() {
      _laterMenu = false;
      _held = null;
    });
    _toast('Reportée à ${m.thisOne} : ${a.name}');
  }

  void _dismiss(Activity a) {
    final ymd = _ymd;
    logic.setNowDone(ymd, logic.nowDoneSet(ymd)..add(a.id));
    setState(() {
      _laterMenu = false;
      _held = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Pas aujourd\'hui : ${a.name}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            logic.setNowDone(ymd, logic.nowDoneSet(ymd)..remove(a.id));
            if (mounted) setState(() {});
          },
        ),
      ));
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
    final day = _day();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _momentCard(pal, day),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(
          child: Text('LA JOURNÉE PAR MOMENTS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
        ),
        if (widget.onOrganize != null)
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: widget.onOrganize,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  foregroundColor: pal.text2,
                  side: BorderSide(color: pal.track),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              child: const Text('Organiser'),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      for (final m in kMoments) ...[
        if (day.of(m.key).isNotEmpty || m.timed) _momentSection(pal, day, m),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _domainDot(Activity a, {double size = 8}) {
    final c = domainColor(a.domainId, logic.state.domains) ?? kRoutineAccent;
    return Container(width: size, height: size, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  String _domainName(Activity a) =>
      logic.state.domains.where((d) => d.id == a.domainId).map((d) => d.name).firstOrNull ?? '';

  Widget _icon(Activity a, {double size = 26, Color? color}) => Icon(
        a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.repeat_rounded,
        size: size,
        color: color ?? kRoutineAccent,
      );

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: kBAttention.withOpacity(.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: kBAttention)),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: kRoutineAccent.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: kRoutineAccent)),
      );

  Widget _momentCard(NowPalette pal, RoutineDay day) {
    final cur = day.current;
    final q = day.queue;
    final heldSlot = _heldSlot(day);
    final first = heldSlot ?? q.firstOrNull;
    final held = heldSlot != null && heldSlot.reached;
    final c = day.countOf(cur.key);
    final progress = c.total == 0 ? 0.0 : (c.done / c.total).clamp(0.0, 1.0);
    final todayN = first == null ? 0 : _todayCount(first.activity);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kRoutineAccent.withOpacity(.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: kRoutineAccent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('ROUTINE DU MOMENT',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
          ),
          _pill('${cur.label} · ${cur.window}'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                size: const Size(96, 96),
                painter: RingPainter(
                    progress: progress, color: kRoutineAccent, stroke: 9, trackColor: pal.track, cap: StrokeCap.round),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${c.done} / ${c.total}',
                    style: TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
                Text('FAITES', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: pal.text3)),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: first == null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('✓', style: TextStyle(fontSize: 34, color: kRoutineAccent)),
                    Text('${cur.label} terminé · ${c.done} sur ${c.total}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
                    const SizedBox(height: 2),
                    Text(_nextLabel(cur), style: TextStyle(fontSize: 12.5, color: pal.text3)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (first.moment != cur.key) ...[
                      _tag('Restée ${momentOf(first.moment).of}'),
                      const SizedBox(height: 6),
                    ],
                    Row(children: [
                      _domainDot(first.activity),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_domainName(first.activity),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.text2)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _icon(first.activity, size: 30),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(first.activity.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.15, color: pal.text)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(first.reached ? '✓ ${first.todo.progressLabel}' : first.todo.progressLabel,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: first.reached ? FontWeight.w700 : null,
                            color: first.reached ? kRoutineAccent : pal.text3,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(height: 8),
                    RoutineChronoPill(logic: logic, routine: first.activity, onChanged: () => setState(() {})),
                  ]),
          ),
        ]),
        if (first != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kRoutineAccent,
                      foregroundColor: kBBg,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  onPressed: () => _plus(first.activity, hold: true),
                  child: const Text('+1'),
                ),
              ),
            ),
            if (todayN > 0) ...[
              const SizedBox(width: 8),
              _round(pal, '−1', () => _minus(first.activity), size: 54),
            ],
            const SizedBox(width: 8),
            if (held)
              SizedBox(
                height: 54,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _held = null;
                    _laterMenu = false;
                  }),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kRoutineAccent,
                      side: BorderSide(color: kRoutineAccent.withOpacity(.5)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  child: const Text('Suivante'),
                ),
              )
            else
              SizedBox(
                height: 54,
                child: Material(
                  color: _laterMenu ? pal.track : pal.chip,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _laterMenu = !_laterMenu),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Pas maintenant', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text)),
                        const SizedBox(width: 4),
                        Icon(_laterMenu ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: pal.text2),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
          if (_laterMenu) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Plus tard ${cur.thisOne}', () => _defer(first.activity)),
              for (final m in day.laterMoments) _chip(_cap(m.thisOne), () => _pushTo(first.activity, m)),
              _chip('Pas aujourd\'hui', () => _dismiss(first.activity), muted: true),
            ]),
          ],
          if (widget.onChain != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => widget.onChain!(day),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kRoutineAccent,
                    side: BorderSide(color: kRoutineAccent.withOpacity(.5)),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text('Enchaîner les routines ${cur.of} · ${q.length}', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ],
      ]),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _nextLabel(Moment cur) {
    final n = nextMomentAfter(cur);
    if (n == null) return 'La suite : demain matin.';
    return 'La suite : à ${n.window.split(' → ').first} (${n.label.toLowerCase()}).';
  }

  Widget _chip(String label, VoidCallback onTap, {bool muted = false}) => SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              foregroundColor: muted ? kBText3 : kRoutineAccent,
              side: BorderSide(color: muted ? kBLine : kRoutineAccent.withOpacity(.4)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          child: Text(label),
        ),
      );

  Widget _round(NowPalette pal, String label, VoidCallback? onTap,
          {double size = 44, Color? bg, Color? fg}) =>
      SizedBox(
        width: size,
        height: size,
        child: Material(
          color: bg ?? pal.chip,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: onTap == null ? Colors.white.withOpacity(.18) : (fg ?? pal.text2))),
            ),
          ),
        ),
      );

  Widget _momentSection(NowPalette pal, RoutineDay day, Moment m) {
    final isCur = m.key == day.current.key;
    final always = m.key == kMomentAllDay;
    final open = always || (_open[m.key] ?? isCur);
    final c = day.countOf(m.key);
    final left = day.leftoverCountOf(m.key);
    final rows = day.of(m.key);
    return Container(
      decoration: BoxDecoration(
        color: isCur ? pal.track : pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCur ? kRoutineAccent.withOpacity(.45) : kBLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: always ? null : () => setState(() => _open[m.key] = !open),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Text(m.label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: isCur ? kRoutineAccent : pal.text3)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.window, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.text4)),
                ),
                if (left > 0) ...[_tag('$left restée${left > 1 ? 's' : ''}'), const SizedBox(width: 10)],
                Text('${c.done} / ${c.total}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: pal.text2, fontFeatures: const [FontFeature.tabularFigures()])),
                if (!always) ...[
                  const SizedBox(width: 6),
                  Icon(open ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: pal.text4),
                ],
              ]),
            ),
          ),
        ),
        if (open)
          for (final s in rows) _row(pal, day, s),
      ]),
    );
  }

  Widget _row(NowPalette pal, RoutineDay day, RoutineSlot s) {
    final a = s.activity;
    final done = s.reached;
    final dismissed = day.dismissed.contains(a.id);
    final n = _todayCount(a);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(.05)))),
      child: Opacity(
        opacity: dismissed ? .45 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(children: [
            SizedBox(
              width: 44,
              height: 44,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _toggleReach(s),
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: done ? kRoutineAccent : Colors.transparent,
                      shape: BoxShape.circle,
                      border: done ? null : Border.all(color: pal.text4, width: 1.5),
                    ),
                    child: done ? const Icon(Icons.check_rounded, size: 14, color: kBBg) : null,
                  ),
                ),
              ),
            ),
            _icon(a, size: 20, color: done ? pal.text4 : kRoutineAccent),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openSheet(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    // Une seule ligne : le compte et le ▶ passent SOUS − / +,
                    // ce qui rend ~90 px au nom.
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: done ? pal.text3 : pal.text,
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: pal.text3)),
                    if (s.pushed)
                      Text('reportée ${momentOf(s.home).of}', style: const TextStyle(fontSize: 11, color: kBAttention)),
                    if (dismissed) Text('pas aujourd\'hui', style: TextStyle(fontSize: 11, color: pal.text4)),
                  ]),
                ),
              ),
            ),
            _rowControls(pal, s, a, done: done, n: n),
          ]),
        ),
      ),
    );
  }

  /// Colonne de droite d'une ligne : − / + en haut ; dessous, centrés sous les
  /// boutons, le compte « ✓ 2 / 3 » et le ▶ de l'activité liée (■ si elle
  /// tourne). Largeur fixe = celle des deux boutons.
  Widget _rowControls(NowPalette pal, RoutineSlot s, Activity a, {required bool done, required int n}) {
    final linked = _linkedOf(a);
    final target = s.todo.dayTarget ?? s.todo.weekTarget;
    final count = s.todo.dayTarget != null ? s.todo.dayDone : s.todo.weekDone;
    final showCount = target > 1 || count > 0;
    return SizedBox(
      width: 94,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          _round(pal, '−', n > 0 || (s.todo.dayTarget == null && s.todo.weekDone > 0) ? () => _minus(a) : null),
          const SizedBox(width: 6),
          _round(pal, '+', () => _plus(a), bg: kRoutineAccent.withOpacity(.14), fg: kRoutineAccent),
        ]),
        if (showCount || linked != null)
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (showCount)
                Text((done ? '✓ ' : '') + '$count / $target',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: done ? kRoutineAccent : pal.text3,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              if (showCount && linked != null) const SizedBox(width: 6),
              if (linked != null)
                SizedBox(
                  width: 28,
                  height: 24,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _toggleChrono(linked),
                    child: Icon(_isRunning(linked) ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 20, color: _isRunning(linked) ? kBAttention : kRoutineAccent),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
