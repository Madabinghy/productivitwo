import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';
import 'package:productivitwo_v1/widgets/day_timeline_view.dart';
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart';

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
  bool _showTomorrow = false;
  // Timeline 24 h (façon Calendar) ⇄ liste compacte. La timeline est l'outil
  // de planification (drag, resize, ajout au créneau) ; la liste reste là
  // pour cocher vite.
  bool _timeline = true;
  bool _syncing = false;

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      child: SingleChildScrollView(
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
                // Timeline 24 h ⇄ liste compacte.
                IconButton(
                  tooltip: _timeline ? 'Vue liste' : 'Vue agenda',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                      _timeline
                          ? Icons.view_list_outlined
                          : Icons.calendar_view_day_outlined,
                      size: 20),
                  onPressed: () => setState(() => _timeline = !_timeline),
                ),
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
          ],
        ),
      ),
    );
  }
}
