import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/focus_context.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/web/views/today_view.dart';

/// Pastille de la barre du haut : visible dès qu'un chrono tourne sur une
/// action (cible lue dans l'état d'Aujourd'hui, qui vit dans l'IndexedStack).
/// Sinon, [fallback] (le lanceur de chrono habituel), gardé monté hors écran
/// pour ne pas perdre ses flux.
class FocusPill extends StatefulWidget {
  final GlobalKey<TodayViewState> todayKey;
  final Widget fallback;
  final VoidCallback onTap;
  const FocusPill(
      {super.key, required this.todayKey, required this.fallback, required this.onTap});

  @override
  State<FocusPill> createState() => _FocusPillState();
}

class _FocusPillState extends State<FocusPill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.todayKey.currentState;
    final t = st?.focusTarget;
    final open = st?.openSession;
    final has = t != null && open != null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Offstage(offstage: has, child: widget.fallback),
      if (has)
        Tooltip(
          message: 'Focus : ${t.action.title}',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 7),
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              height: 34,
              decoration: BoxDecoration(
                color: kBRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBPrimary.withOpacity(.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: kBPrimary,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kBPrimary.withOpacity(.25), blurRadius: 0, spreadRadius: 4)],
                  ),
                ),
                const SizedBox(width: 10),
                Text(_clock(DateTime.now().difference(open.startAt)),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kBText,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(t.action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600, color: kBText2)),
                ),
                if (_steps(t) case final s?) ...[
                  const SizedBox(width: 8),
                  Text(s, style: const TextStyle(fontSize: 11.5, color: kBText3, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
        ),
    ]);
  }

  String? _steps(FocusTarget t) {
    if (t.stepsAreTaskActions) {
      final list = taskSteps(t.task);
      return '${list.where((a) => a.done).length}/${list.length}';
    }
    if (t.action.checklist.isEmpty) return null;
    return '${t.action.checklistDone}/${t.action.checklistTotal}';
  }
}

/// Tiroir Focus à droite (depuis n'importe quel onglet) : voile + colonne de
/// 440 px avec la bande en mode compact. Se ferme seul si le chrono s'arrête.
class FocusDrawer extends StatefulWidget {
  final GlobalKey<TodayViewState> todayKey;
  final VoidCallback onClose;
  const FocusDrawer({super.key, required this.todayKey, required this.onClose});

  @override
  State<FocusDrawer> createState() => _FocusDrawerState();
}

class _FocusDrawerState extends State<FocusDrawer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.todayKey.currentState;
    final t = st?.focusTarget;
    if (st == null || t == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return const SizedBox.shrink();
    }
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: Container(color: Colors.black.withOpacity(.45)),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        bottom: 0,
        child: LayoutBuilder(builder: (ctx, box) {
          final w = MediaQuery.sizeOf(context).width;
          return Material(
            color: kBSurface,
            elevation: 24,
            shadowColor: Colors.black,
            child: Container(
              width: w < 520 ? w * .92 : 440,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: kBLine)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: st.focusDrawer(t, onClose: widget.onClose),
              ),
            ),
          );
        }),
      ),
    ]);
  }
}
