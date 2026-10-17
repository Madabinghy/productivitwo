import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;

/// Bandeau « chrono en cours » des écrans Enchaîner (programme et routines) :
/// « ⏱ Lecture · 12:34 » avec la couleur du domaine, ■ pour arrêter. Rien
/// n'est affiché sans chrono ouvert. Se met à jour seul chaque seconde.
class RunningChronoBar extends StatefulWidget {
  final AppLogic logic;
  const RunningChronoBar({super.key, required this.logic});

  @override
  State<RunningChronoBar> createState() => _RunningChronoBarState();
}

class _RunningChronoBarState extends State<RunningChronoBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Session? get _open {
    Session? last;
    for (final s in widget.logic.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  String _hms(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final ms = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return h > 0 ? '$h:$ms' : ms;
  }

  @override
  Widget build(BuildContext context) {
    final s = _open;
    if (s == null) return const SizedBox.shrink();
    final logic = widget.logic;
    final act = logic.state.activities.where((a) => a.id == s.activityId).firstOrNull;
    if (act == null) return const SizedBox.shrink();
    final pal = NowPalette.of(context);
    final color = domainColor(act.domainId, logic.state.domains) ?? pal.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.35)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(children: [
          Icon(Icons.timer_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(act.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.text)),
          ),
          const SizedBox(width: 8),
          Text(_hms(DateTime.now().difference(s.startAt)),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          IconButton(
            tooltip: 'Arrêter le chrono',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.stop_rounded, size: 20, color: pal.text3),
            onPressed: () {
              logic.stopActive();
              setState(() {});
            },
          ),
        ]),
      ),
    );
  }
}
