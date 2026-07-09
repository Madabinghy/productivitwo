import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/notifications.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/widgets/domain_naming_sheet.dart';
import 'package:productivitwo_v1/widgets/domain_session_screen.dart';
import 'package:productivitwo_v1/widgets/move_block_sheet.dart';

class DailyScheduleView extends StatefulWidget {
  final String date; // YYYY-MM-DD
  final AppLogic logic;
  // Lancer un bloc (▶) : démarre le chrono de la tâche/activité liée + focus.
  final void Function(ScheduleBlock block)? onLaunch;
  // Tap sur un bloc issu d'une source (tâche/routine/activité) → ouvre SA fiche
  // (au lieu du sheet de renommage du bloc).
  final void Function(ScheduleBlock block)? onOpenSource;
  // Titre de section et texte d'état vide — surchargés par la vue « Demain ».
  final String title;
  final String? emptyText;

  const DailyScheduleView(
      {super.key,
      required this.date,
      required this.logic,
      this.onLaunch,
      this.onOpenSource,
      this.title = 'Programme du jour',
      this.emptyText});

  @override
  State<DailyScheduleView> createState() => _DailyScheduleViewState();
}

class _DailyScheduleViewState extends State<DailyScheduleView> {
  final _sync = FirestoreSync();
  DailySchedule? _schedule;
  StreamSubscription<DailySchedule?>? _sub;
  // Défis déjà comptés (tap OU auto) — évite tout double comptage par bloc.
  final Set<String> _won = {};
  // Blocs ayant déjà validé leur routine liée — évite de re-incrémenter au
  // re-cochage (binding bidirectionnel défi ↔ routine).
  final Set<String> _routineHit = {};
  // Blocs « projet » déjà auto-cochés (tâche terminée ailleurs) — évite les
  // écritures répétées avant le retour du stream.
  final Set<String> _projectSynced = {};

  /// La vue peut afficher une autre date (planif de demain) : les effets de
  /// bord « jour courant » (todayBlocks, auto-coche) ne valent qu'aujourd'hui.
  bool get _isToday {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return widget.date == today;
  }

  @override
  void initState() {
    super.initState();
    _sub = _sync.streamDailySchedule(widget.date).listen((s) {
      if (mounted) {
        setState(() => _schedule = s);
        if (_isToday) widget.logic.todayBlocks = s?.blocks ?? [];
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  /// Retrouve (projet, tâche) d'un bloc « projet » dans le snapshot logique.
  (Project, ProjectTask)? _taskOf(ScheduleBlock b) {
    if (b.projectId == null || b.taskId == null) return null;
    for (final p in widget.logic.currentProjects) {
      if (p.id != b.projectId) continue;
      for (final t in p.tasks) {
        if (t.id == b.taskId) return (p, t);
      }
    }
    return null;
  }

  Future<void> _toggleDone(ScheduleBlock block) async {
    // Cocher un bloc « projet » → on demande où en est la tâche (sheet), au lieu
    // de cocher sec (binding bidirectionnel bloc ↔ tâche).
    if (block.status != 'done') {
      final pt = _taskOf(block);
      if (pt != null) {
        await _openTaskProgressSheet(block, pt.$1, pt.$2);
        return;
      }
    }
    final newStatus = block.status == 'done' ? 'pending' : 'done';
    await _sync.updateBlockStatus(widget.date, block.id, newStatus);
    if (block.challenge && newStatus == 'done' && !_won.contains(block.id)) {
      _won.add(block.id);
      widget.logic.recordChallengeAccepted(widget.date.replaceAll('-', ''));
    }
    // Binding défi/bloc → routine : cocher un bloc lié à une routine valide la
    // routine du jour (le chemin minuteur le fait déjà via _onAlarmRing).
    if (newStatus == 'done') _completeLinkedRoutine(block);
  }

  /// Bloc « projet » coché → sheet où l'user coche les actions faites de la
  /// tâche, puis VALIDE la tâche (→ tâche done + bloc coché) ou SORT (on laisse
  /// comme ça : les coches d'actions sont déjà sauvées, le bloc reste tel quel).
  Future<void> _openTaskProgressSheet(
      ScheduleBlock block, Project project, ProjectTask task) async {
    final validated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _TaskProgressSheet(
        task: task,
        onToggleAction: (a, v) async {
          a.done = v;
          a.doneAt = v ? DateTime.now() : null;
          await _sync.saveProjectTasks(project.id, project.tasks);
        },
      ),
    );
    if (validated == true) {
      task.status = 'done';
      await _sync.saveProjectTasks(project.id, project.tasks);
      await _sync.updateBlockStatus(widget.date, block.id, 'done');
    }
  }

  /// Sens inverse du binding bloc ↔ tâche : une tâche terminée ailleurs coche
  /// automatiquement son bloc « projet » dans le programme. Appelé en post-frame.
  void _maybeSyncProjectBlocks() {
    if (!mounted) return;
    for (final b in _schedule?.blocks ?? const <ScheduleBlock>[]) {
      if (b.status != 'pending' ||
          b.projectId == null ||
          b.taskId == null ||
          _projectSynced.contains(b.id)) {
        continue;
      }
      final pt = _taskOf(b);
      if (pt != null && pt.$2.status == 'done') {
        _projectSynced.add(b.id); // garde : 1 seule écriture avant le retour stream
        _sync.updateBlockStatus(widget.date, b.id, 'done');
      }
    }
  }

  /// Parse "YYYY-MM-DD" (date du programme) en DateTime local minuit.
  DateTime _blockDay() {
    final p = widget.date.split('-');
    return DateTime(
        int.parse(p[0]), int.parse(p.elementAtOrNull(1) ?? '1'),
        int.parse(p.elementAtOrNull(2) ?? '1'));
  }

  Activity? _activityById(String id) {
    for (final a in widget.logic.state.activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Valide la routine liée à un bloc (si activité de type habit), 1 incrément,
  /// sans dépasser la cible ni recompter pour un même bloc.
  void _completeLinkedRoutine(ScheduleBlock block) {
    final id = block.activityId;
    if (id == null || _routineHit.contains(block.id)) return;
    final act = _activityById(id);
    if (act == null || !act.isHabit) return;
    final day = _blockDay();
    final tgt = widget.logic.activeHabitTarget(act);
    if (tgt > 0 && widget.logic.habitValueOn(id, day) >= tgt) {
      _routineHit.add(block.id); // déjà atteinte → on marque, sans incrémenter
      return;
    }
    _routineHit.add(block.id);
    widget.logic.incHabit(id, 1, day);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Routine validée : ${act.name}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _deleteBlock(ScheduleBlock block) async {
    await _sync.updateBlockStatus(widget.date, block.id, 'deleted');
    if (block.challenge) {
      NotificationService.cancelChallengeAll(block.id);
    }
    // Retire aussi le todayFlag de la source liée (étoile routine / tâche).
    if (block.activityId != null) {
      widget.logic.setActivityTodayFlag(block.activityId!, false);
      await _sync.toggleActivityTodayFlag(block.activityId!, false);
    } else if (block.taskId != null && block.projectId != null) {
      await _sync.toggleTaskTodayFlag(block.projectId!, block.taskId!, false);
    }
  }

  /// Défi programmé gagné automatiquement si du temps a été loggué sur
  /// l'activité le jour cible (≥ 60 % de la durée prévue, plancher 10 min).
  /// Appelé en post-frame depuis build (FocusView rebuild quand on logge).
  void _maybeAutoWin() {
    if (!mounted) return;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (widget.date != todayStr) return;
    final dayStart = DateTime(now.year, now.month, now.day);
    for (final b in _schedule?.blocks ?? <ScheduleBlock>[]) {
      if (b.status != 'pending' ||
          b.activityId == null ||
          _won.contains(b.id)) {
        continue;
      }
      // Sens inverse du binding : une source validée ailleurs (routine faite,
      // temps loggué) coche son bloc — qu'il soit défi ou bloc routine/activité.
      final act = _activityById(b.activityId!);
      final bool reached;
      if (act != null && act.isHabit) {
        // Routine validée (FAB, donjon, minuteur…) → atteinte de la cible.
        final tgt = widget.logic.activeHabitTarget(act);
        reached =
            tgt > 0 && widget.logic.habitValueOn(b.activityId!, dayStart) >= tgt;
      } else {
        final loggedMin = widget.logic
            .totalForRangeByActivity(b.activityId!, dayStart, now)
            .inMinutes;
        final threshold = (b.durationMin * 0.6).round();
        reached = loggedMin >= (threshold < 10 ? 10 : threshold);
      }
      if (reached) {
        _won.add(b.id);
        _routineHit.add(b.id); // source déjà validée → pas de ré-incrément
        _sync.updateBlockStatus(widget.date, b.id, 'done');
        // Comptage défi + feedback UNIQUEMENT pour les blocs « défi » 🔥 ;
        // un bloc routine/activité simple se coche sans fanfare.
        if (b.challenge) {
          widget.logic.recordChallengeAccepted(widget.date.replaceAll('-', ''));
          if (mounted) {
            final name = b.title.replaceFirst('🔥 Défi : ', '');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '🔥 Défi relevé : $name ! Série : ${widget.logic.state.challengeStreak} 🔥'),
              duration: const Duration(seconds: 4),
            ));
          }
        }
        if (mounted) setState(() {});
      }
    }
  }


  /// Mode soirée (23c) : bloc non fait d'avant 19 h → « en attente, à recaser
  /// ce soir » (rendu seulement — le bloc n'est jamais modifié par la bascule).
  bool _waitingInEveningMode(ScheduleBlock b) =>
      _schedule?.eveningMode == true &&
      b.status == 'pending' &&
      !b.isPrep &&
      b.category != 'break' &&
      b.startTime.compareTo('19:00') < 0;

  Future<void> _saveBlock(ScheduleBlock updated) async {
    final schedule = _schedule;
    if (schedule == null) return;
    final blocks = schedule.blocks.map((b) => b.id == updated.id ? updated : b).toList();
    // Préserver les faits du doc (dayReason, planifié quand, mode soirée) —
    // éditer un bloc ne doit rien effacer d'autre.
    await _sync.saveDailySchedule(DailySchedule(
      date: schedule.date,
      generatedBy: schedule.generatedBy,
      generatedAt: schedule.generatedAt,
      blocks: blocks,
      dayReason: schedule.dayReason,
      plannedAt: schedule.plannedAt,
      plannedSameDay: schedule.plannedSameDay,
      dayMode: schedule.dayMode,
      dayModeActivatedAt: schedule.dayModeActivatedAt,
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Tri chronologique : les défis (ajoutés en fin de tableau) se placent à
    // leur heure dans le programme, pas en bas de liste.
    final visible = (_schedule?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isToday) return;
      _maybeAutoWin();
      _maybeSyncProjectBlocks();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
            const Spacer(),
            if (_schedule != null)
              Text(
                _schedule!.generatedBy == 'orion' ? '✨ ORION' : '🤖 Claude',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(.4)),
              ),
            IconButton(
              tooltip: 'Ajouter un bloc',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.only(left: 8),
              constraints: const BoxConstraints(),
              icon: Icon(Icons.add_circle_outline,
                  size: 20, color: cs.primary),
              onPressed: () => _addManualBlock(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _buildEmptyState(cs)
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            itemBuilder: (context, i) =>
                _buildBlock(context, cs, visible[i], key: ValueKey(visible[i].id)),
          ),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, ColorScheme cs, ScheduleBlock block,
      {required Key key}) {
    if (block.isPrep) return _buildPrepBlock(context, cs, block, key: key);
    final isDone = block.status == 'done';
    // Défi programmé = teinte dorée distincte (cohérent avec « Challenge me »).
    final color =
        block.challenge ? const Color(0xFFB8860B) : _categoryColor(block.category, cs);

    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer, size: 20),
      ),
      onDismissed: (_) => _deleteBlock(block),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          // 23a : déplacer à la main — long-press → créneaux libres réels.
          onLongPress: block.status == 'pending' && !block.isPrep
              ? () => showMoveBlockSheet(context,
                  logic: widget.logic, block: block, date: widget.date)
              : null,
          onTap: () {
            // Bloc session de définition (onboarding 18b) → lance la session ;
            // bloc « nommer mes domaines » (21a) → sheet de nommage in-place.
            if (block.kind == 'session') {
              if (block.domainId != null) {
                Domain? d;
                for (final x in widget.logic.state.domains) {
                  if (x.id == block.domainId && !x.deleted) d = x;
                }
                if (d != null) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DomainSessionScreen(
                        logic: widget.logic, domainName: d!.name),
                  ));
                  return;
                }
              } else {
                showDomainNamingSheet(context, logic: widget.logic);
                return;
              }
            }
            // Bloc issu d'une tâche/routine/activité → ouvre sa fiche ;
            // bloc libre (perso/pause) → sheet de renommage du bloc.
            final hasSource =
                block.projectId != null || block.activityId != null;
            if (hasSource && widget.onOpenSource != null) {
              widget.onOpenSource!(block);
            } else {
              _showEditSheet(context, cs, block);
            }
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Heure
              SizedBox(
                width: 46,
                child: Text(
                  block.startTime,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDone
                        ? cs.onSurface.withOpacity(.25)
                        : cs.onSurface.withOpacity(.55),
                  ),
                ),
              ),
              // Barre couleur catégorie
              Container(
                width: 3,
                height: 44,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDone ? color.withOpacity(.2) : color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Contenu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDone
                            ? cs.onSurface.withOpacity(.3)
                            : cs.onSurface,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        decorationColor: cs.onSurface.withOpacity(.3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(_categoryIcon(block.category),
                            size: 11,
                            color: isDone
                                ? color.withOpacity(.25)
                                : color.withOpacity(.8)),
                        const SizedBox(width: 4),
                        Text(
                          fmtMin(block.durationMin),
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface
                                  .withOpacity(isDone ? .2 : .4)),
                        ),
                        // Mode soirée (23c) : les blocs non faits d'avant 19 h
                        // sont EN ATTENTE — jamais supprimés, recasés au
                        // check-in ; « Revenir » les restaure tels quels.
                        if (_waitingInEveningMode(block)) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'en attente — à recaser ce soir',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  color: cs.tertiary.withOpacity(.9)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Bouton ▶ lancer (chrono + focus tâche), si lançable.
              if (widget.onLaunch != null &&
                  !isDone &&
                  (block.projectId != null || block.activityId != null))
                GestureDetector(
                  onTap: () => widget.onLaunch!(block),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: color.withOpacity(.14), shape: BoxShape.circle),
                    child: Icon(Icons.play_arrow_rounded, size: 18, color: color),
                  ),
                ),
              // Bouton checkbox
              GestureDetector(
                onTap: () => _toggleDone(block),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? color : Colors.transparent,
                      border: isDone
                          ? null
                          : Border.all(
                              color: cs.onSurface.withOpacity(.2),
                              width: 1.5),
                    ),
                    child: isDone
                        ? Icon(Icons.check, size: 15, color: cs.surface)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bloc de préparation la veille (kind:"prep") : rangée compacte, icône sac,
  /// libellé + « pour demain », checkbox en un tap. Swipe = supprimer (comme les
  /// autres blocs). « Demain se gagne ce soir. »
  Widget _buildPrepBlock(BuildContext context, ColorScheme cs, ScheduleBlock block,
      {required Key key}) {
    final isDone = block.status == 'done';
    final color = cs.tertiary;
    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer, size: 20),
      ),
      onDismissed: (_) => _deleteBlock(block),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => _showEditSheet(context, cs, block),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(.18)),
            ),
            child: Row(
              children: [
                Icon(Icons.backpack_outlined,
                    size: 16,
                    color: isDone ? color.withOpacity(.35) : color.withOpacity(.85)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDone ? cs.onSurface.withOpacity(.35) : cs.onSurface,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                          decorationColor: cs.onSurface.withOpacity(.3),
                        ),
                      ),
                      Text(
                        '${block.startTime} · ${_prepForLabel(block)}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: cs.onSurface.withOpacity(isDone ? .3 : .45)),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _toggleDone(block),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone ? color : Colors.transparent,
                        border: isDone
                            ? null
                            : Border.all(
                                color: cs.onSurface.withOpacity(.2), width: 1.5),
                      ),
                      child: isDone
                          ? Icon(Icons.check, size: 14, color: cs.surface)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// « pour demain » si prepForDate = lendemain de la date du programme, sinon
  /// « pour le JJ/MM ».
  String _prepForLabel(ScheduleBlock block) {
    final pd = block.prepForDate;
    if (pd == null || pd.length < 10) return 'pour demain';
    final base = _blockDay();
    final tomorrow = base.add(const Duration(days: 1));
    final tStr =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    if (pd == tStr) return 'pour demain';
    return 'pour le ${pd.substring(8, 10)}/${pd.substring(5, 7)}';
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _addManualBlock(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withOpacity(.12)),
        ),
        child: Row(
          children: [
            Icon(Icons.today_outlined,
                size: 20, color: cs.onSurface.withOpacity(.3)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.emptyText ??
                    'Pas de programme pour aujourd\'hui.\nTouche pour ajouter un bloc, ou dis à Claude ce que tu veux faire.',
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(.4),
                    height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context, ColorScheme cs, ScheduleBlock block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) =>
          _BlockEditSheet(block: block, onSave: _saveBlock),
    );
  }

  /// Ajout manuel d'un bloc perso : ouvre la sheet d'édition vierge, puis
  /// pose le bloc dans le programme du jour (crée le doc au besoin).
  void _addManualBlock(BuildContext context) {
    final now = TimeOfDay.now();
    final draft = ScheduleBlock(
      startTime:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      durationMin: 30,
      title: '',
      category: 'personal',
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _BlockEditSheet(
        block: draft,
        isNew: true,
        activities: widget.logic.state.activeActivities
            .where((a) => !a.isHabit && a.role != ActivityRole.shopping)
            .toList()
          ..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        onSave: (b) => _sync.addScheduleBlock(widget.date, b),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Color _categoryColor(String category, ColorScheme cs) => switch (category) {
        'project' => cs.primary,
        'routine' => const Color(0xFF1a9e6e),
        'personal' => cs.secondary,
        'break' => cs.outline,
        _ => cs.tertiary,
      };

  IconData _categoryIcon(String category) => switch (category) {
        'project' => Icons.rocket_launch_outlined,
        'routine' => Icons.loop,
        'personal' => Icons.home_outlined,
        'break' => Icons.coffee_outlined,
        _ => Icons.circle_outlined,
      };
}

// ── Sheet d'édition d'un bloc ─────────────────────────────────────────────────

class _BlockEditSheet extends StatefulWidget {
  final ScheduleBlock block;
  final Future<void> Function(ScheduleBlock) onSave;
  final bool isNew;
  // Activités « temps » proposables pour lier le bloc (création seulement).
  final List<Activity> activities;

  const _BlockEditSheet(
      {required this.block,
      required this.onSave,
      this.isNew = false,
      this.activities = const []});

  @override
  State<_BlockEditSheet> createState() => _BlockEditSheetState();
}

class _BlockEditSheetState extends State<_BlockEditSheet> {
  late final TextEditingController _titleCtrl;
  late String _startTime;
  late int _durationMin;
  late String _category;
  late String? _activityId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.block.title);
    _startTime = widget.block.startTime;
    _durationMin = widget.block.durationMin;
    _category = widget.block.category;
    _activityId = widget.block.activityId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(ScheduleBlock(
      id: widget.block.id,
      startTime: _startTime,
      durationMin: _durationMin,
      title: title,
      category: _category,
      projectId: widget.block.projectId,
      taskId: widget.block.taskId,
      activityId: _activityId,
      status: widget.block.status,
      doneAt: widget.block.doneAt,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.isNew ? 'Nouveau bloc' : 'Modifier le bloc',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                labelText: 'Titre',
                border: OutlineInputBorder(),
                isDense: true),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimePickerField(
                  label: 'Début',
                  value: _startTime,
                  onChanged: (v) => setState(() => _startTime = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DurationField(
                  value: _durationMin,
                  onChanged: (v) => setState(() => _durationMin = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CategorySelector(
            value: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
          if (widget.isNew && widget.activities.isNotEmpty) ...[
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Activité (optionnel)',
                  border: OutlineInputBorder(),
                  isDense: true),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _activityId,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Aucune')),
                    for (final a in widget.activities)
                      DropdownMenuItem<String?>(
                          value: a.id,
                          child:
                              Text(a.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    _activityId = v;
                    if (v != null && _titleCtrl.text.trim().isEmpty) {
                      for (final a in widget.activities) {
                        if (a.id == v) {
                          _titleCtrl.text = a.name;
                          break;
                        }
                      }
                    }
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Lié à une activité → bouton ▶ pour chronométrer ; se coche au temps loggué.',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.5))),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving
                ? 'Enregistrement…'
                : (widget.isNew ? 'Ajouter' : 'Enregistrer')),
          ),
        ],
      ),
    );
  }
}

// ── Champ sélecteur d'heure ───────────────────────────────────────────────────

class _TimePickerField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TimePickerField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 9,
          minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
        );
        final picked =
            await showTimePicker(context: context, initialTime: initial);
        if (picked != null) {
          onChanged(
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true),
        child: Text(value, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

// ── Champ durée ───────────────────────────────────────────────────────────────

class _DurationField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _DurationField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked =
            await pickDurationMin(context, initial: value, title: 'Durée');
        if (picked != null && picked > 0) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Durée',
            border: OutlineInputBorder(),
            isDense: true),
        child: Text(fmtMin(value), style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

// ── Sélecteur de catégorie ────────────────────────────────────────────────────

class _CategorySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CategorySelector(
      {required this.value, required this.onChanged});

  static const _cats = [
    ('project', 'Projet', Icons.rocket_launch_outlined),
    ('routine', 'Routine', Icons.loop),
    ('personal', 'Perso', Icons.home_outlined),
    ('break', 'Pause', Icons.coffee_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _cats.map((c) {
        final selected = value == c.$1;
        return ChoiceChip(
          avatar: Icon(c.$3, size: 14),
          label: Text(c.$2, style: const TextStyle(fontSize: 13)),
          selected: selected,
          onSelected: (_) => onChanged(c.$1),
          selectedColor: cs.primaryContainer,
          labelStyle: TextStyle(
              color: selected ? cs.onPrimaryContainer : cs.onSurface),
        );
      }).toList(),
    );
  }
}

// ── Sheet de progression d'une tâche (bloc « projet » coché) ──────────────────

/// Liste les actions de la tâche à cocher ; l'user peut « Valider la tâche »
/// (→ true) ou simplement fermer (→ on laisse comme ça). Chaque coche d'action
/// est persistée immédiatement via [onToggleAction].
class _TaskProgressSheet extends StatefulWidget {
  final ProjectTask task;
  final Future<void> Function(TaskAction action, bool value) onToggleAction;

  const _TaskProgressSheet({required this.task, required this.onToggleAction});

  @override
  State<_TaskProgressSheet> createState() => _TaskProgressSheetState();
}

class _TaskProgressSheetState extends State<_TaskProgressSheet> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = widget.task.actions;
    final done = actions.where((a) => a.done).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.task.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text('$done / ${actions.length} actions faites',
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            ),
          if (actions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Cette tâche n\'a pas de sous-actions.',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurface.withOpacity(.6))),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in actions)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: a.done,
                      activeColor: Colors.green,
                      title: Text(a.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: a.done
                                ? cs.onSurface.withOpacity(.4)
                                : cs.onSurface,
                            decoration:
                                a.done ? TextDecoration.lineThrough : null,
                          )),
                      onChanged: (v) async {
                        setState(() {}); // reflète l'état avant l'await
                        await widget.onToggleAction(a, v ?? false);
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600),
            label: const Text('Valider la tâche'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Laisser comme ça'),
          ),
        ],
      ),
    );
  }
}
