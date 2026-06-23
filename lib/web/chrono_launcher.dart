import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

/// Lanceur de chrono/minuteur GLOBAL (barre du haut de l'app web).
///
/// Permet de démarrer une activité‑temps depuis N'IMPORTE QUEL onglet, sans
/// passer par l'Arène. Affiche le chrono en cours (élapsé + objectif éventuel)
/// avec un bouton stop. Auto‑synchronisé avec les chronos lancés ailleurs
/// (Arène, mobile) via `streamSessions`.
class ChronoLauncher extends StatefulWidget {
  final FirestoreSync sync;
  const ChronoLauncher({required this.sync, super.key});

  @override
  State<ChronoLauncher> createState() => _ChronoLauncherState();
}

class _ChronoLauncherState extends State<ChronoLauncher> {
  AppLogic? _logic;
  Timer? _ticker;
  StreamSubscription<List<Session>>? _sessionsSub;
  int? _targetMin; // minuteur : objectif d'affichage (null = chrono libre)

  FirestoreSync get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await sync.pull();
    if (state == null || !mounted) return;
    final logic = AppLogic(state, () {
      if (mounted) setState(() {});
    });
    logic.sync = sync;
    setState(() => _logic = logic);
    // Reflète en direct les chronos lancés/arrêtés ailleurs (Arène, mobile).
    _sessionsSub = sync.streamSessions().listen((sessions) {
      final l = _logic;
      if (l == null) return;
      // Préserve une session ouverte localement pas encore remontée par le flux.
      final localOpen = l.state.sessions.where((s) => s.endAt == null).toList();
      l.state.sessions = sessions;
      for (final s in localOpen) {
        if (!sessions.any((x) => x.id == s.id)) l.state.sessions.add(s);
      }
      if (_openSession == null) _targetMin = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sessionsSub?.cancel();
    super.dispose();
  }

  Session? get _openSession {
    final l = _logic;
    if (l == null) return null;
    Session? last;
    for (final s in l.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  void _syncTicker() {
    final running = _openSession != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String _activityName(String id) {
    for (final a in _logic!.state.activities) {
      if (a.id == id) return a.name;
    }
    return 'Activité';
  }

  void _start(Activity a, {int? targetMin}) {
    final l = _logic!;
    final openBefore = l.state.sessions.where((s) => s.endAt == null).toList();
    l.start(a.id);
    for (final s in openBefore) {
      sync.saveSession(s); // ferme proprement le chrono précédent
    }
    if (l.state.sessions.isNotEmpty) sync.saveSession(l.state.sessions.last);
    _targetMin = targetMin;
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    final s = _openSession;
    if (s == null) return;
    s.endAt = DateTime.now();
    await sync.saveSession(s);
    _logic?.reconcileLiveGold(sync); // l'or du jour intègre le temps loggué
    _logic?.onChange();
    _targetMin = null;
    if (mounted) setState(() {});
  }

  Future<void> _openPicker() async {
    final l = _logic!;
    final acts =
        l.state.activeActivities.where((a) => !a.isHabit).toList();
    final domains = l.state.domains.where((d) => !d.deleted).toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ChronoPickerDialog(
        activities: acts,
        domains: domains,
        onPick: (a, target) {
          Navigator.pop(ctx);
          _start(a, targetMin: target);
        },
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = _logic;
    if (l == null) return const SizedBox.shrink();
    _syncTicker();
    final cs = Theme.of(context).colorScheme;
    final open = _openSession;

    if (open == null) {
      // État repos : bouton « Chrono » → ouvre le sélecteur d'activité.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextButton.icon(
          onPressed: _openPicker,
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('Chrono'),
        ),
      );
    }

    // État actif : pastille chrono (nom · élapsé [/ objectif]) + stop.
    final elapsed = DateTime.now().difference(open.startAt);
    final reached =
        _targetMin != null && elapsed.inMinutes >= _targetMin!;
    final color = reached ? Colors.green.shade600 : cs.primary;
    final timeLabel = _targetMin != null
        ? '${_fmt(elapsed)} / ${_targetMin}min'
        : _fmt(elapsed);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(reached ? Icons.check_circle : Icons.timelapse,
            size: 16, color: color),
        const SizedBox(width: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            _activityName(open.activityId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        Text(timeLabel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        IconButton(
          icon: const Icon(Icons.stop_circle, size: 20),
          color: cs.error,
          tooltip: 'Arrêter le chrono',
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: _stop,
        ),
      ]),
    );
  }
}

/// Sélecteur d'activité‑temps : tap sur la ligne = chrono libre ; menu ⏱ =
/// minuteur avec une durée cible. Activités groupées par domaine.
class _ChronoPickerDialog extends StatelessWidget {
  final List<Activity> activities;
  final List<Domain> domains;
  final void Function(Activity a, int? targetMin) onPick;
  const _ChronoPickerDialog({
    required this.activities,
    required this.domains,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final knownIds = domains.map((d) => d.id).toSet();
    final byDomain = <String, List<Activity>>{};
    final others = <Activity>[];
    for (final a in activities) {
      if (a.domainId.isNotEmpty && knownIds.contains(a.domainId)) {
        byDomain.putIfAbsent(a.domainId, () => []).add(a);
      } else {
        others.add(a);
      }
    }

    final rows = <Widget>[];
    void addGroup(String title, Color color, List<Activity> acts) {
      if (acts.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(.6))),
        ]),
      ));
      for (final a in acts) {
        rows.add(_row(context, a, color, cs));
      }
    }

    for (final d in domains) {
      addGroup(d.name, domainColor(d.id, domains) ?? cs.primary,
          byDomain[d.id] ?? const []);
    }
    addGroup('Autres', cs.outline, others);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
            child: Row(children: [
              const Icon(Icons.play_circle_outline, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Lancer un chrono',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          if (activities.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text('Aucune activité‑temps à lancer.',
                  style: TextStyle(color: cs.onSurface.withOpacity(.5))),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, Activity a, Color color, ColorScheme cs) {
    final durations = <int>[15, 25, 45, 60];
    if (a.goalMin > 0 && !durations.contains(a.goalMin)) {
      durations.add(a.goalMin);
    }
    durations.sort();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onPick(a, null), // chrono libre
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(children: [
            Icon(Icons.timer_outlined, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            // Minuteur : choisir une durée objectif.
            PopupMenuButton<int>(
              tooltip: 'Minuteur (objectif)',
              icon: Icon(Icons.more_time,
                  size: 18, color: cs.onSurface.withOpacity(.5)),
              onSelected: (min) => onPick(a, min),
              itemBuilder: (_) => [
                for (final m in durations)
                  PopupMenuItem<int>(
                      value: m, child: Text('Minuteur · $m min')),
              ],
            ),
            const SizedBox(width: 2),
            Icon(Icons.play_arrow_rounded, size: 22, color: color),
          ]),
        ),
      ),
    );
  }
}
