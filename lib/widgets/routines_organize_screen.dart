import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show kRoutineAccent;

/// « Organiser » (handoff Segment Routines, lot 3) : ranger les routines par
/// moment — glisser une routine vers un autre moment (appui long) la déplace,
/// ▲ ▼ la réordonnent dans son moment ; « Par domaine » = les mêmes routines
/// groupées par domaine de vie, le moment se change sur la ligne. Écrit
/// `Activity.timeContext` (moment) et `Activity.routineOrder` (rang), via
/// `saveActivity` ; le reste de l'app lit ces deux champs.
Future<void> showRoutinesOrganizeScreen(BuildContext context, {required AppLogic logic, FirestoreSync? sync}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _OrganizeScreen(logic: logic, sync: sync ?? FirestoreSync()),
  ));
}

class _OrganizeScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _OrganizeScreen({required this.logic, required this.sync});

  @override
  State<_OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<_OrganizeScreen> {
  bool _byDomain = false;
  String? _dragOver;
  String? _chipOpen;

  AppLogic get logic => widget.logic;

  List<Activity> get _routines => logic.state.activeActivities
      .where((a) => a.isHabit && a.habitFreq != null && a.habitFreq != HabitFreq.monthly)
      .toList();

  List<Activity> _of(String momentKey) {
    final l = _routines.where((a) => momentKeyOf(a) == momentKey).toList()
      ..sort((a, b) {
        final oa = a.routineOrder, ob = b.routineOrder;
        if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
        if (oa != null && ob == null) return -1;
        if (oa == null && ob != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return l;
  }

  /// Rangs 0..n-1 dans l'ordre donné ; n'enregistre que ce qui change.
  Future<void> _renumber(List<Activity> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].routineOrder != i) {
        ordered[i].routineOrder = i;
        await widget.sync.saveActivity(ordered[i]);
      }
    }
    logic.onChange();
  }

  Future<void> _moveTo(Activity a, String momentKey) async {
    final from = momentKeyOf(a);
    if (from == momentKey) return;
    HapticFeedback.mediumImpact();
    final target = _of(momentKey);
    a.timeContext = momentKey;
    a.routineOrder = target.length;
    await widget.sync.saveActivity(a);
    await _renumber(_of(from));
    if (!mounted) return;
    setState(() => _chipOpen = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('Déplacée vers ${momentOf(momentKey).label} : ${a.name}'),
          duration: const Duration(milliseconds: 2600)));
  }

  Future<void> _nudge(Activity a, int dir) async {
    final list = _of(momentKeyOf(a));
    final i = list.indexOf(a), j = i + dir;
    if (i < 0 || j < 0 || j >= list.length) return;
    HapticFeedback.selectionClick();
    list.removeAt(i);
    list.insert(j, a);
    await _renumber(list);
    if (mounted) setState(() {});
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 52,
            child: Stack(alignment: Alignment.center, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: kRoutineAccent),
                  icon: const Icon(Icons.chevron_left, size: 22),
                  label: const Text('Routines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              Text('Organiser', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x0FFFFFFF)),
              ),
              child: Row(children: [
                _seg(pal, 'Par moment', !_byDomain, () => setState(() => _byDomain = false)),
                _seg(pal, 'Par domaine', _byDomain, () => setState(() => _byDomain = true)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              _byDomain
                  ? 'Les mêmes routines, groupées par domaine de vie · touche le moment pour le changer.'
                  : 'Glisse une routine vers un autre moment pour la déplacer (appui long) · ▲▼ pour réordonner.',
              style: TextStyle(fontSize: 12, color: pal.text4),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: _byDomain ? _domainSections(pal) : _momentSections(pal),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _seg(NowPalette pal, String label, bool on, VoidCallback onTap) => Expanded(
        child: SizedBox(
          height: 40,
          child: Material(
            color: on ? pal.track : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? kRoutineAccent.withOpacity(.4) : Colors.transparent),
                ),
                child: Text(label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? pal.text : pal.text3)),
              ),
            ),
          ),
        ),
      );

  Widget _icon(Activity a, {double size = 20}) => Icon(
        a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.repeat_rounded,
        size: size,
        color: kRoutineAccent,
      );

  Widget _dot(Activity a) {
    final c = domainColor(a.domainId, logic.state.domains) ?? kRoutineAccent;
    return Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  Widget _arrow(NowPalette pal, IconData icon, VoidCallback? onTap) => SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: pal.chip,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: 16, color: onTap == null ? Colors.white.withOpacity(.18) : pal.text2),
          ),
        ),
      );

  // ── Par moment ──────────────────────────────────────────────────────────────

  List<Widget> _momentSections(NowPalette pal) => [
        for (final m in kMoments) ...[
          DragTarget<Activity>(
            onWillAcceptWithDetails: (d) {
              final ok = momentKeyOf(d.data) != m.key;
              if (ok) setState(() => _dragOver = m.key);
              return ok;
            },
            onLeave: (_) => setState(() => _dragOver = null),
            onAcceptWithDetails: (d) {
              setState(() => _dragOver = null);
              _moveTo(d.data, m.key);
            },
            builder: (ctx, cand, rej) {
              final list = _of(m.key);
              final over = _dragOver == m.key;
              return Container(
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: over ? kRoutineAccent : Colors.white.withOpacity(.08), width: over ? 1.5 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(children: [
                        Text(m.label.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kRoutineAccent)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(m.window, style: TextStyle(fontSize: 11.5, color: pal.text4))),
                        Text('${list.length}', style: TextStyle(fontSize: 13, color: pal.text3)),
                      ]),
                    ),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text(over ? 'Déposer ici' : 'Aucune routine',
                          style: TextStyle(fontSize: 12.5, color: over ? kRoutineAccent : pal.text4)),
                    ),
                  for (var i = 0; i < list.length; i++) _momentRow(pal, list[i], i == 0, i == list.length - 1),
                ]),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ];

  Widget _momentRow(NowPalette pal, Activity a, bool first, bool last) {
    final row = Container(
      height: 52,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(.05)))),
      child: Row(children: [
        const SizedBox(width: 12),
        Icon(Icons.drag_handle_rounded, size: 18, color: pal.text4),
        const SizedBox(width: 10),
        _icon(a),
        const SizedBox(width: 10),
        Expanded(
          child: Text(a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.text)),
        ),
        _dot(a),
        const SizedBox(width: 10),
        _arrow(pal, Icons.arrow_drop_up_rounded, first ? null : () => _nudge(a, -1)),
        const SizedBox(width: 6),
        _arrow(pal, Icons.arrow_drop_down_rounded, last ? null : () => _nudge(a, 1)),
        const SizedBox(width: 8),
      ]),
    );
    return LongPressDraggable<Activity>(
      data: a,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width - 32,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: pal.track,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kRoutineAccent),
          ),
          child: Row(children: [
            _icon(a),
            const SizedBox(width: 10),
            Expanded(
                child: Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text))),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: row),
      onDragEnd: (_) => setState(() => _dragOver = null),
      child: row,
    );
  }

  // ── Par domaine ─────────────────────────────────────────────────────────────

  List<Widget> _domainSections(NowPalette pal) {
    final doms = logic.state.domains.where((d) => !d.deleted).toList();
    final byDom = <String, List<Activity>>{};
    for (final a in _routines) {
      (byDom[a.domainId] ??= []).add(a);
    }
    final out = <Widget>[];
    for (final d in [...doms, if (byDom.keys.any((k) => !doms.any((d) => d.id == k))) null]) {
      final list = d == null
          ? [for (final e in byDom.entries) if (!doms.any((x) => x.id == e.key)) ...e.value]
          : (byDom[d.id] ?? const <Activity>[]);
      if (list.isEmpty) continue;
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final c = d == null ? kRoutineAccent : (domainColor(d.id, logic.state.domains) ?? kRoutineAccent);
      out.add(Container(
        decoration: BoxDecoration(
            color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(.06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text((d?.name ?? 'Sans domaine').toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: pal.text2)),
                ),
                Text('${list.length}', style: TextStyle(fontSize: 13, color: pal.text3)),
              ]),
            ),
          ),
          for (final a in list) _domainRow(pal, a),
        ]),
      ));
      out.add(const SizedBox(height: 10));
    }
    return out;
  }

  String _targetLabel(Activity a) {
    final t = a.habitTarget ?? 1;
    return a.habitFreq == HabitFreq.weekly ? '$t / sem.' : '$t / j';
  }

  Widget _domainRow(NowPalette pal, Activity a) {
    final key = momentKeyOf(a);
    final open = _chipOpen == a.id;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(.05)))),
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _icon(a),
          const SizedBox(width: 10),
          Expanded(
            child: Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.text)),
          ),
          Text(_targetLabel(a),
              style: TextStyle(fontSize: 11.5, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 10),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: () => setState(() => _chipOpen = open ? null : a.id),
              style: OutlinedButton.styleFrom(
                  foregroundColor: kRoutineAccent,
                  backgroundColor: open ? kRoutineAccent.withOpacity(.14) : null,
                  side: BorderSide(color: kRoutineAccent.withOpacity(.4)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(momentOf(key).label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Icon(open ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18),
                ]),
              ),
            ),
          ),
        ]),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 8, 0, 6),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in kMoments)
                SizedBox(
                  height: 34,
                  child: m.key == key
                      ? FilledButton(
                          onPressed: () => setState(() => _chipOpen = null),
                          style: FilledButton.styleFrom(
                              backgroundColor: kRoutineAccent,
                              foregroundColor: kBBg,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          child: Text(m.label),
                        )
                      : FilledButton.tonal(
                          onPressed: () => _moveTo(a, m.key),
                          style: FilledButton.styleFrom(
                              backgroundColor: pal.track,
                              foregroundColor: pal.text2,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          child: Text(m.label),
                        ),
                ),
            ]),
          ),
      ]),
    );
  }
}
