import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';
import 'package:productivitwo_v1/widgets/day_timeline_view.dart';
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/next_actions_section.dart';

/// Onglet « Aujourd'hui » : le programme horaire du jour, avec bascule vers
/// « Demain » pour préparer la journée suivante (planif du lendemain).
/// L'exécution (chrono, focus) reste dans l'onglet Maintenant.
class TodayView extends StatefulWidget {
  final AppLogic logic;
  // Lancer un bloc (▶) : démarre le chrono de la tâche/activité liée + focus.
  final void Function(ScheduleBlock block)? onLaunch;
  // Tap sur un bloc issu d'une source → ouvre sa fiche (tâche/routine/activité).
  final void Function(ScheduleBlock block)? onOpenSource;

  const TodayView(
      {super.key, required this.logic, this.onLaunch, this.onOpenSource});

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  final _sync = FirestoreSync();
  bool _showTomorrow = false;
  // Timeline 24 h (façon Calendar) ⇄ liste compacte. La timeline est l'outil
  // de planification (drag, resize, ajout au créneau) ; la liste reste là
  // pour cocher vite.
  bool _timeline = true;
  bool _syncing = false;
  // Scroll de la page — la jauge-minimap saute la timeline à l'heure tapée.
  final _scroll = ScrollController();
  Timer? _gaugeTick;

  @override
  void initState() {
    super.initState();
    // La jauge suit le chrono en cours + le trait « maintenant ».
    _gaugeTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !_showTomorrow) setState(() {});
    });
  }

  @override
  void dispose() {
    _gaugeTick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Jauge verticale 00:00 → 23:59 (façon Waze) ────────────────────────────
  //
  // Le temps LOGGUÉ du jour (dont le chrono en cours), segmenté aux couleurs
  // des DOMAINES — la composition de la journée en un coup d'œil, toute la
  // journée visible sans scroller. Le vide reste neutre translucide (pas
  // noir : le vide n'est pas une faute, et le noir disparaît en thème
  // sombre). Tap/drag = minimap → la timeline saute à cette heure.

  /// Segments loggués d'un JOUR donné (minuit → minuit), bornés à la journée.
  List<({int start, int end, Color color})> _gaugeSegments(
      DateTime day, DateTime now) {
    final dayEnd = day.add(const Duration(days: 1));
    final out = <({int start, int end, Color color})>[];
    for (final s in widget.logic.state.sessions) {
      final end = s.endAt ?? now;
      if (!end.isAfter(day) || !s.startAt.isBefore(dayEnd)) continue;
      Activity? a;
      for (final x in widget.logic.state.activities) {
        if (x.id == s.activityId) { a = x; break; }
      }
      if (a == null || a.deleted) continue;
      final st = s.startAt.isBefore(day) ? 0 : s.startAt.difference(day).inMinutes;
      final en = end.isAfter(dayEnd) ? 1440 : end.difference(day).inMinutes;
      if (en - st < 1) continue;
      out.add((
        start: st,
        end: en,
        color: domainColor(a.domainId, widget.logic.state.activeDomains) ??
            Colors.teal,
      ));
    }
    return out;
  }

  /// Saut minimap : minute du jour → offset de scroll de la timeline
  /// (1 h = 100 px dans DayTimelineView, ~120 px d'en-tête avant 00:00).
  void _jumpTo(int minute) {
    if (!_timeline || !_scroll.hasClients) return;
    final target = (120.0 + minute / 60.0 * 100.0 - 220.0)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// Une bande verticale 00:00 → 23:59 d'un jour. [thin] = jauge d'HIER :
  /// plus étroite, tamisée, sans trait ni interaction — le point de
  /// comparaison, pas l'objet du jour.
  Widget _gaugeStrip(
    ColorScheme cs,
    List<({int start, int end, Color color})> segments,
    double h, {
    int? nowMin,
    bool thin = false,
  }) {
    double y(int min) => min / 1440.0 * h;
    final opacity = thin ? .45 : .85;
    return Container(
      width: thin ? 7 : 14,
      height: h,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(thin ? .05 : .08),
        borderRadius: BorderRadius.circular(thin ? 4 : 7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        for (final s in segments)
          Positioned(
            top: y(s.start),
            left: thin ? 1 : 2,
            right: thin ? 1 : 2,
            height: (y(s.end) - y(s.start)).clamp(2.0, h),
            child: Container(
              decoration: BoxDecoration(
                color: s.color.withOpacity(opacity),
                borderRadius: BorderRadius.circular(thin ? 2 : 4),
              ),
            ),
          ),
        if (nowMin != null)
          Positioned(
            top: y(nowMin) - 1,
            left: 0,
            right: 0,
            height: 2,
            child: Container(color: const Color(0xFFE53935)),
          ),
      ]),
    );
  }

  Widget _dayGauge(ColorScheme cs, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final segments = _gaugeSegments(today, now);
    // Hier COLLÉ à aujourd'hui (bande fine et tamisée) : la comparaison des
    // deux journées d'un coup d'œil — le benchmark, pas l'objet du jour.
    final ySegments =
        _gaugeSegments(today.subtract(const Duration(days: 1)), now);
    final nowMin = now.hour * 60 + now.minute;
    // À GAUCHE, CENTRÉES verticalement (demande user) : les jauges occupent
    // la moitié de la hauteur, au milieu de la page — présentes d'un coup
    // d'œil sans dominer le bord.
    return Positioned(
      top: 0,
      bottom: 0,
      left: 3,
      width: 23,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          heightFactor: .5,
          child: LayoutBuilder(builder: (gctx, box) {
            final h = box.maxHeight;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _jumpTo(
                  (d.localPosition.dy / h * 1440).round().clamp(0, 1439)),
              onVerticalDragUpdate: (d) => _jumpTo(
                  (d.localPosition.dy / h * 1440).round().clamp(0, 1439)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _gaugeStrip(cs, ySegments, h, thin: true),
                  const SizedBox(width: 2),
                  _gaugeStrip(cs, segments, h, nowMin: nowMin),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Sync agenda À LA DEMANDE (aujourd'hui + demain) : un RDV modifié côté
  /// Google est repris immédiatement dans les miroirs — utile juste avant de
  /// planifier demain, sans attendre la sync d'ouverture.
  Future<void> _forceSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final sync = FirestoreSync();
    final now = DateTime.now();
    var ok = false;
    String? reason;
    for (final d in [now, now.add(const Duration(days: 1))]) {
      final r = await gcalSyncDay(sync, _ymd(d));
      if (r?['ok'] == true) ok = true;
      reason ??= r?['reason'] as String?;
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '🗓️ Agenda synchronisé — aujourd\'hui et demain sont à jour.'
          : reason == 'not_connected'
              ? 'Google Agenda non connecté — Paramètres → Google Agenda.'
              : 'Synchronisation impossible — réessaie.'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// État vide du jour selon les domaines (Partie D) : rien de nommé → le
  /// programme ne peut pas exister ; nommé mais rien de défini → il attend le
  /// rang 1. Sinon : état vide standard (null).
  String? _domainsPlaceholder() {
    final domains =
        widget.logic.state.domains.where((d) => !d.deleted).toList();
    final named = domains.where((d) => d.definitionStatus == 'named').toList();
    final started = domains.any((d) =>
        d.definitionStatus == 'active' || d.definitionStatus == 'draft');
    if (named.isEmpty && !started) {
      return 'Ton programme apparaîtra ici.\nIl se construit à partir de tes domaines — c\'est l\'étape juste au-dessus.';
    }
    if (!started && named.isNotEmpty) {
      return 'Le programme se remplit dès que ${named.first.name} est défini — ce soir si tu veux.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final date =
        _showTomorrow ? _ymd(now.add(const Duration(days: 1))) : _ymd(now);

    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
        controller: _scroll,
        // Padding bas généreux : dégage la pile de boutons du FAB (~156px) pour
        // que les derniers items du programme restent cochables.
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('Aujourd\'hui'),
                        icon: Icon(Icons.today_outlined, size: 16)),
                    ButtonSegment(
                        value: true,
                        label: Text('Demain'),
                        icon: Icon(Icons.event_outlined, size: 16)),
                  ],
                  selected: {_showTomorrow},
                  onSelectionChanged: (s) =>
                      setState(() => _showTomorrow = s.first),
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
                const Spacer(),
                // Sync Google Agenda à la demande (aujourd'hui + demain).
                IconButton(
                  tooltip: 'Synchroniser Google Agenda',
                  visualDensity: VisualDensity.compact,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded, size: 20),
                  onPressed: _syncing ? null : _forceSync,
                ),
                // Espace réservé au toggle liste⇄agenda ÉPINGLÉ (voir Stack) —
                // il ne défile pas avec le contenu, plus besoin de remonter.
                const SizedBox(width: 44),
              ],
            ),
            const SizedBox(height: 16),
            // key par date : force un nouveau state (nouveau stream Firestore)
            // quand on bascule aujourd'hui ↔ demain.
            if (_timeline)
              DayTimelineView(
                key: ValueKey('tl-$date'),
                date: date,
                logic: widget.logic,
                // ▶ n'a de sens que pour le jour même (chrono maintenant).
                onLaunch: _showTomorrow ? null : widget.onLaunch,
                onOpenSource: widget.onOpenSource,
              )
            else
              DailyScheduleView(
                key: ValueKey(date),
                date: date,
                logic: widget.logic,
                onLaunch: _showTomorrow ? null : widget.onLaunch,
                onOpenSource: widget.onOpenSource,
                // Demain = préparation → regroupé par contexte GTD (batching).
                groupByContext: _showTomorrow,
                title:
                    _showTomorrow ? 'Programme de demain' : 'Programme du jour',
                // Placeholder 21a/22c : sans domaine, le programme ne peut pas
                // exister — l'étape est juste au-dessus (nudge de Maintenant).
                emptyText: _showTomorrow
                    ? 'Rien de prévu pour demain.\nTouche pour ajouter un bloc, ou demande à Claude/ORION de planifier ta journée.'
                    : _domainsPlaceholder(),
              ),
            if (_showTomorrow) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Prépare demain ce soir : un plan posé la veille se suit '
                  'beaucoup mieux le matin.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: cs.onSurface.withOpacity(.55)),
                ),
              ),
            ],
            // « Prochaines actions » (GTD) : le canal pull des actions quand
            // le Gantt est en retrait — consultation, création (+), chrono.
            NextActionsSection(logic: widget.logic, sync: _sync),
          ],
        ),
          ),
          // Jauge 00:00 → 23:59 (façon Waze) : le loggué du jour aux couleurs
          // des domaines, minimap tappable — uniquement sur Aujourd'hui.
          if (!_showTomorrow) _dayGauge(cs, now),
          // Toggle liste ⇄ agenda ÉPINGLÉ en haut à droite : accessible sans
          // remonter les 24 h de timeline (demande user).
          Positioned(
            top: 6,
            right: 16,
            child: Material(
              color: cs.surfaceContainerHighest.withOpacity(.92),
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: _timeline ? 'Vue liste' : 'Vue agenda',
                icon: Icon(
                    _timeline
                        ? Icons.view_list_outlined
                        : Icons.calendar_view_day_outlined,
                    size: 20),
                onPressed: () => setState(() => _timeline = !_timeline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
