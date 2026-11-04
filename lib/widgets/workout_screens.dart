import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sport_stats.dart' show resolveSportPick;
import 'package:productivitwo_v1/utils/workouts.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/sport_sheet.dart' show kSportAccent;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:wakelock_plus/wakelock_plus.dart';

// Séances de muscu, lot 2 (maquette validée « Séances de muscu », 2026-11-04) : Ma séance → Régler un exercice →
// En série → Repos → Bilan. Logique pure dans `utils/workouts.dart`.

const _ink = Color(0xFF1D0F08);

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

const List<int> kRestChoices = [45, 60, 90, 120, 180];

/// « Ma séance » : choisir une séance type, voir ce qui est prévu face à la fois d'avant, ajouter un exercice, démarrer.
Future<void> showWorkoutHub(BuildContext context, {required AppLogic logic, String? templateId}) {
  return showFiche<void>(context, builder: (ctx, scroll) => WorkoutHub(logic: logic, scroll: scroll, templateId: templateId));
}

class WorkoutHub extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  final String? templateId;
  const WorkoutHub({super.key, required this.logic, this.scroll, this.templateId});

  @override
  State<WorkoutHub> createState() => _WorkoutHubState();
}

class _WorkoutHubState extends State<WorkoutHub> {
  AppLogic get logic => widget.logic;
  String? _templateId;
  /// Séance libre : la liste vit ici, sans séance type.
  List<TemplateItem> _freeItems = [];
  final _add = TextEditingController();

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
    _templateId = widget.templateId ?? _lastTemplateId();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    _add.dispose();
    super.dispose();
  }

  String? _lastTemplateId() {
    final live = logic.gym.liveTemplates;
    if (live.isEmpty) return null;
    final done = liveWorkouts(logic.workouts).reversed.where((w) => w.templateId != null && logic.gym.templates[w.templateId]?.deleted == false);
    return done.isEmpty ? live.first.id : done.first.templateId;
  }

  WorkoutTemplate? get _template => _templateId == null ? null : logic.gym.templates[_templateId];
  List<TemplateItem> get _items => _template?.items ?? _freeItems;

  Future<void> _setItems(List<TemplateItem> items) async {
    final t = _template;
    if (t == null) {
      setState(() => _freeItems = items);
    } else {
      await logic.saveWorkoutTemplate(t.copyWith(items: items));
    }
  }

  Future<void> _newTemplate() async {
    final r = await showTemplateEditor(context);
    if (r == null) return;
    final t = WorkoutTemplate(id: _newId(), name: r.$1, place: r.$2, items: _template == null ? _freeItems : const []);
    await logic.saveWorkoutTemplate(t);
    setState(() {
      _templateId = t.id;
      _freeItems = [];
    });
  }

  Future<void> _editTemplate(WorkoutTemplate t) async {
    final r = await showTemplateEditor(context, name: t.name, place: t.place, canDelete: true);
    if (r == null) return;
    if (r.$3) {
      await logic.removeWorkoutTemplate(t.id);
      setState(() => _templateId = _lastTemplateId());
      return;
    }
    await logic.saveWorkoutTemplate(t.copyWith(name: r.$1, place: r.$2, clearPlace: r.$2 == null));
  }

  Future<void> _addByName(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return;
    _add.clear();
    final known = exerciseByName(logic.gym, name);
    final r = await showExerciseEditor(context, logic: logic, exercise: known ?? Exercise(id: _newId(), name: name), isNew: known == null);
    if (r == null) return;
    await _setItems([..._items, r.$2]);
  }

  Future<void> _editItem(int i) async {
    final item = _items[i];
    final e = logic.gym.exercises[item.exerciseId];
    if (e == null) return;
    final r = await showExerciseEditor(context, logic: logic, exercise: e, item: item);
    if (r == null) return;
    final next = [..._items]..[i] = r.$2;
    await _setItems(next);
  }

  Future<void> _removeItem(int i) async {
    final next = [..._items]..removeAt(i);
    await _setItems(next);
  }

  Future<void> _start() async {
    final items = _items.where((i) => logic.gym.exercises[i.exerciseId] != null).toList();
    if (items.isEmpty) return;
    final t = _template;
    Navigator.of(context).pop();
    await showWorkoutPlayer(context, logic: logic, items: items, template: t);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final t = _template;
    final last = t == null ? null : lastWorkoutOf(t.id, logic.workouts);
    final items = _items;
    final templates = logic.gym.liveTemplates;
    final est = items.fold<int>(0, (s, i) {
      final e = logic.gym.exercises[i.exerciseId];
      return s + i.sets * (45 + (e?.restSec ?? kDefaultRestSec));
    });
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      const Text('SPORT · SÉANCE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: kSportAccent)),
      Row(children: [
        Expanded(child: Text(t?.name ?? 'Séance libre', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
        if (t != null) IconButton(tooltip: 'Renommer, lieu, retirer', onPressed: () => _editTemplate(t), icon: const Icon(Icons.edit_outlined)),
      ]),
      Text(
        [
          '${items.length} exercice${items.length > 1 ? 's' : ''}',
          if (items.isNotEmpty) '≈ ${(est / 60).round()} min',
          if (t?.place != null) t!.place!,
          if (last != null) 'la dernière : ${_dayLabel(last.ymd)}',
        ].join(' · '),
        style: TextStyle(fontSize: 13, color: mute),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in templates)
          ChoiceChip(
            key: ValueKey('tpl-${x.id}'),
            label: Text(x.name),
            selected: x.id == _templateId,
            selectedColor: kSportAccent,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: x.id == _templateId ? _ink : null),
            onSelected: (_) => setState(() => _templateId = x.id),
          ),
        ChoiceChip(
          key: const ValueKey('tpl-free'),
          label: const Text('Libre'),
          selected: _templateId == null,
          selectedColor: kSportAccent,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _templateId == null ? _ink : null),
          onSelected: (_) => setState(() => _templateId = null),
        ),
        ActionChip(key: const ValueKey('tpl-new'), avatar: const Icon(Icons.add, size: 18), label: const Text('Séance type'), onPressed: _newTemplate),
      ]),
      const SizedBox(height: 16),
      Text(items.isEmpty ? 'AU PROGRAMME' : 'AU PROGRAMME · APPUI LONG POUR L\'ORDRE',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
      const SizedBox(height: 6),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Ajoute un exercice ou une machine : l\'app retient ton poids, tes répétitions et ton repos.', style: TextStyle(color: mute)),
        ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        onReorder: (a, b) {
          final next = [...items];
          final x = next.removeAt(a);
          next.insert(b > a ? b - 1 : b, x);
          _setItems(next);
        },
        itemBuilder: (ctx, i) => ReorderableDelayedDragStartListener(
          key: ValueKey('item-$i-${items[i].exerciseId}'),
          index: i,
          child: Dismissible(
            key: ValueKey('dis-$i-${items[i].exerciseId}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeItem(i),
            background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: Icon(Icons.delete_outline, color: cs.error)),
            child: _itemTile(cs, i, items[i]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('workout-add'),
        controller: _add,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.add),
          hintText: 'Ajouter un exercice… (machine, nom)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          isDense: true,
        ),
        onSubmitted: _addByName,
      ),
      if (_add.text.isEmpty && logic.gym.liveExercises.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in logic.gym.liveExercises.where((e) => !items.any((i) => i.exerciseId == e.id)).take(8))
            ActionChip(label: Text(e.name), onPressed: () => _addByName(e.name)),
        ]),
      ],
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('workout-start'),
        style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(54)),
        onPressed: items.isEmpty ? null : _start,
        child: const Text('Démarrer la séance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
    ]);
  }

  Widget _itemTile(ColorScheme cs, int i, TemplateItem item) {
    final e = logic.gym.exercises[item.exerciseId];
    if (e == null) return const SizedBox.shrink();
    final last = lastSetsOf(e.id, logic.workouts);
    final sw = suggestedWeight(e, item, last);
    final lastW = last.map((s) => s.weightKg).whereType<double>().fold<double?>(null, (m, x) => m == null || x > m ? x : m);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editItem(i),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(radius: 18, backgroundColor: kSportAccent.withValues(alpha: .18), child: Text('${i + 1}', style: const TextStyle(color: kSportAccent, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text([e.name, if (e.gear?.isNotEmpty == true) e.gear!].join(' · '), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(itemLabel(e, item), style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .85))),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: last.isEmpty ? 'pas encore fait' : 'dernière fois : ${last.map(setLabel).join(', ')}'),
                    if (sw != null && lastW != null && sw > lastW)
                      TextSpan(text: ' · +${kgLabel(sw - lastW)} kg proposé', style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.w700)),
                  ]),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

String _dayLabel(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// Nom et lieu d'une séance type. Renvoie (nom, lieu, retirer).
Future<(String, String?, bool)?> showTemplateEditor(BuildContext context, {String? name, String? place, bool canDelete = false}) {
  final ctrl = TextEditingController(text: name ?? '');
  String? where = place;
  return showModalBottomSheet<(String, String?, bool)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(name == null ? 'Nouvelle séance type' : 'Séance type', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('tpl-name'),
            controller: ctrl,
            autofocus: name == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nom', hintText: 'Haut du corps, Jambes…'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final p in const [kPlaceHome, kPlaceGym])
              ChoiceChip(
                label: Text(p == kPlaceHome ? 'À la maison' : 'À la salle'),
                selected: where == p,
                selectedColor: kSportAccent,
                onSelected: (_) => set(() => where = where == p ? null : p),
              ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('tpl-save'),
            style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(48)),
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isEmpty) return;
              Navigator.of(ctx).pop((n, where, false));
            },
            child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (canDelete)
            TextButton(onPressed: () => Navigator.of(ctx).pop((ctrl.text, where, true)), child: const Text('Retirer cette séance type')),
        ]),
      );
    }),
  );
}

/// « Régler un exercice » : nom, matériel, type, séries × répétitions × poids, repos entre deux séries.
/// Renvoie l'exercice enregistré et la ligne de séance.
Future<(Exercise, TemplateItem)?> showExerciseEditor(BuildContext context,
    {required AppLogic logic, required Exercise exercise, TemplateItem? item, bool isNew = false}) {
  return showModalBottomSheet<(Exercise, TemplateItem)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _ExerciseEditor(logic: logic, exercise: exercise, item: item, isNew: isNew),
  );
}

class _ExerciseEditor extends StatefulWidget {
  final AppLogic logic;
  final Exercise exercise;
  final TemplateItem? item;
  final bool isNew;
  const _ExerciseEditor({required this.logic, required this.exercise, this.item, required this.isNew});

  @override
  State<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<_ExerciseEditor> {
  late final _name = TextEditingController(text: widget.exercise.name);
  late final _gear = TextEditingController(text: widget.exercise.gear ?? '');
  late ExerciseKind _kind = widget.exercise.kind;
  late int _rest = widget.exercise.restSec;
  late int _sets = widget.item?.sets ?? 3;
  late int? _reps = widget.item?.reps ?? _defaultReps(widget.exercise.kind);
  late double? _kg = widget.item?.weightKg ?? _lastKg();

  static int? _defaultReps(ExerciseKind k) => switch (k) {
        ExerciseKind.weight => 10,
        ExerciseKind.bodyweight => null,
        ExerciseKind.duration => 30,
      };

  double? _lastKg() {
    final last = lastSetsOf(widget.exercise.id, widget.logic.workouts);
    return last.map((s) => s.weightKg).whereType<double>().fold<double?>(null, (m, x) => m == null || x > m ? x : m);
  }

  @override
  void dispose() {
    _name.dispose();
    _gear.dispose();
    super.dispose();
  }

  int? _lastRest() => avgRestSec(lastSetsOf(widget.exercise.id, widget.logic.workouts));

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final g = _gear.text.trim();
    final e = await widget.logic.saveExercise(widget.exercise.copyWith(name: n, gear: g, clearGear: g.isEmpty, kind: _kind, restSec: _rest));
    final item = TemplateItem(
      exerciseId: e.id,
      sets: _sets,
      reps: _reps,
      weightKg: _kind == ExerciseKind.weight ? _kg : null,
    );
    if (mounted) Navigator.of(context).pop((e, item));
  }

  Widget _stepper(String label, String value, VoidCallback? minus, VoidCallback? plus, {String? hint, Key? key}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: .6))),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(visualDensity: VisualDensity.compact, onPressed: minus, icon: const Icon(Icons.remove), tooltip: 'Moins'),
            IconButton(visualDensity: VisualDensity.compact, onPressed: plus, icon: const Icon(Icons.add), tooltip: 'Plus'),
          ]),
          if (hint != null) Text(hint, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .55))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = widget.exercise.stepKg;
    final lastRest = _lastRest();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('EXERCICE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSportAccent)),
          TextField(
            key: const ValueKey('ex-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          TextField(
            key: const ValueKey('ex-gear'),
            controller: _gear,
            decoration: const InputDecoration(labelText: 'Machine ou matériel · facultatif', hintText: 'banc, machine 7, chaise…'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final k in ExerciseKind.values)
              ChoiceChip(
                key: ValueKey('ex-kind-${k.name}'),
                label: Text(switch (k) {
                  ExerciseKind.weight => 'Avec poids',
                  ExerciseKind.bodyweight => 'Poids du corps',
                  ExerciseKind.duration => 'Durée',
                }),
                selected: _kind == k,
                selectedColor: kSportAccent,
                labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _kind == k ? _ink : null),
                onSelected: (_) => setState(() {
                  if (_kind != k) _reps = _defaultReps(k);
                  _kind = k;
                }),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _stepper('SÉRIES', '$_sets', _sets > 1 ? () => setState(() => _sets--) : null, _sets < 20 ? () => setState(() => _sets++) : null),
            const SizedBox(width: 8),
            _stepper(
              _kind == ExerciseKind.duration ? 'SECONDES' : 'RÉPÉTITIONS',
              _reps == null ? 'max' : '$_reps',
              _reps == null ? null : () => setState(() => _reps = _kind == ExerciseKind.duration ? math.max(5, _reps! - 5) : (_reps! <= 1 ? null : _reps! - 1)),
              () => setState(() => _reps = _reps == null ? 10 : _reps! + (_kind == ExerciseKind.duration ? 5 : 1)),
              key: const ValueKey('ex-reps'),
            ),
            if (_kind == ExerciseKind.weight) ...[
              const SizedBox(width: 8),
              _stepper('POIDS', _kg == null ? '—' : kgLabel(_kg!), (_kg ?? 0) > 0 ? () => setState(() => _kg = math.max(0, (_kg ?? 0) - step)) : null,
                  () => setState(() => _kg = (_kg ?? 0) + step),
                  hint: 'kg · pas de ${kgLabel(step)}', key: const ValueKey('ex-kg')),
            ],
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: kSportAccent, width: 2), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('REPOS ENTRE DEUX SÉRIES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSportAccent))),
                Text(restLabel(_rest), key: const ValueKey('ex-rest'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in kRestChoices)
                  ChoiceChip(
                    key: ValueKey('rest-$r'),
                    label: Text(restLabel(r)),
                    selected: _rest == r,
                    selectedColor: kSportAccent,
                    labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _rest == r ? _ink : null),
                    onSelected: (_) => setState(() => _rest = r),
                  ),
                ActionChip(label: const Text('−15 s'), onPressed: _rest > 15 ? () => setState(() => _rest -= 15) : null),
                ActionChip(label: const Text('+15 s'), onPressed: () => setState(() => _rest += 15)),
              ]),
              const SizedBox(height: 6),
              Text(
                'retenu pour cet exercice, à chaque séance${lastRest == null ? '' : ' · repos réellement pris la dernière fois : ${restLabel(lastRest)}'}',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('ex-save'),
            style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(50)),
            onPressed: _save,
            child: Text(widget.isNew ? 'Ajouter l\'exercice' : 'Enregistrer l\'exercice', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

// ── La séance en cours ───────────────────────────────────────────────────────

Future<void> showWorkoutPlayer(BuildContext context, {required AppLogic logic, required List<TemplateItem> items, WorkoutTemplate? template}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => WorkoutPlayer(logic: logic, items: items, template: template)));
}

enum _Phase { set, rest, done }

class WorkoutPlayer extends StatefulWidget {
  final AppLogic logic;
  final List<TemplateItem> items;
  final WorkoutTemplate? template;
  /// Faux en test : pas d'alarme, pas d'écran allumé, pas de chrono.
  final bool sideEffects;
  const WorkoutPlayer({super.key, required this.logic, required this.items, this.template, this.sideEffects = true});

  @override
  State<WorkoutPlayer> createState() => _WorkoutPlayerState();
}

class _WorkoutPlayerState extends State<WorkoutPlayer> {
  AppLogic get logic => widget.logic;
  late Workout _w;
  late final List<Workout> _history = [...logic.workouts];
  int _ex = 0;
  final Set<int> _skipped = {};
  _Phase _phase = _Phase.set;
  // Série en cours (réglable).
  int _reps = 10;
  double? _kg;
  int _secs = 30;
  // Repos.
  DateTime? _restEnds;
  int _restTotal = kDefaultRestSec;
  int? _restAdjusted;
  int? _restTaken;
  Timer? _tick;
  String? _chronoActivityId;

  TemplateItem get _item => widget.items[_ex];
  Exercise get _exercise => logic.gym.exercises[_item.exerciseId] ?? Exercise(id: _item.exerciseId, name: 'Exercice');
  List<SetLog> get _doneHere => _w.sets.where((s) => s.exerciseId == _item.exerciseId).toList();
  List<SetLog> get _last => lastSetsOf(_item.exerciseId, _history, beforeMs: _w.startAt);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final t = widget.template;
    _w = Workout(id: _newId(), templateId: t?.id, name: t?.name ?? 'Séance libre', place: t?.place, ymd: logic.livedTodayYmd, startAt: now.millisecondsSinceEpoch);
    _loadPlanned();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    if (widget.sideEffects) {
      WakelockPlus.enable();
      _startChrono();
    }
  }

  void _startChrono() {
    final pick = resolveSportPick(logic.state.activities, logic.state.domains, logic.sportOverrides);
    final acts = pick.sessionActivities;
    if (acts.isEmpty) return;
    Activity a = acts.first;
    for (final x in acts) {
      if (exerciseKey(x.name).contains('muscu')) a = x;
    }
    if (logic.runningActivityId() != a.id) logic.start(a.id);
    _chronoActivityId = a.id;
    _w = _w.copyWith(activityId: a.id);
  }

  void _loadPlanned() {
    final p = plannedSet(_exercise, _item, _last, _doneHere.length);
    _reps = p.reps == 0 ? 10 : p.reps;
    _kg = p.weightKg;
    _secs = p.seconds ?? 30;
  }

  void _onTick() {
    if (!mounted) return;
    if (_phase == _Phase.rest && _restEnds != null && DateTime.now().isAfter(_restEnds!)) {
      _goSet();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (widget.sideEffects) {
      WakelockPlus.disable();
      CoupAlarm.cancel();
    }
    super.dispose();
  }

  Future<void> _persist() async {
    if (_w.sets.isEmpty) return;
    await logic.saveWorkout(_w);
  }

  void _setDone() {
    final now = DateTime.now();
    final e = _exercise;
    final s = SetLog(
      exerciseId: e.id,
      reps: e.kind == ExerciseKind.duration ? 0 : _reps,
      weightKg: e.kind == ExerciseKind.weight ? _kg : null,
      seconds: e.kind == ExerciseKind.duration ? _secs : null,
      restSec: _restTaken,
      at: now.millisecondsSinceEpoch,
    );
    _w = _w.copyWith(sets: [..._w.sets, s]);
    _restTaken = null;
    _persist();
    final doneAll = _doneHere.length >= _item.sets;
    if (doneAll && !_advance()) {
      setState(() => _phase = _Phase.done);
      _finishSideEffects();
      return;
    }
    _startRest(e.restSec);
  }

  /// Passe au prochain exercice non fini ; false = plus rien à faire.
  bool _advance() {
    for (var k = 1; k <= widget.items.length; k++) {
      final i = (_ex + k) % widget.items.length;
      if (_skipped.contains(i)) continue;
      final it = widget.items[i];
      if (_w.sets.where((s) => s.exerciseId == it.exerciseId).length < it.sets) {
        _ex = i;
        _loadPlanned();
        return true;
      }
    }
    return false;
  }

  void _startRest(int sec) {
    final ends = DateTime.now().add(Duration(seconds: sec));
    setState(() {
      _phase = _Phase.rest;
      _restTotal = sec;
      _restEnds = ends;
      _restAdjusted = null;
    });
    if (widget.sideEffects) {
      CoupAlarm.schedule(logic, endsAt: ends, title: 'Repos fini', body: '${_exercise.name} · série ${_doneHere.length + 1} / ${_item.sets}');
    }
  }

  void _adjustRest(int delta) {
    final ends = _restEnds;
    if (ends == null) return;
    final next = ends.add(Duration(seconds: delta));
    setState(() {
      _restEnds = next;
      _restTotal = math.max(5, _restTotal + delta);
      _restAdjusted = _restTotal;
    });
    if (widget.sideEffects) {
      CoupAlarm.cancel(all: false);
      if (next.isAfter(DateTime.now())) {
        CoupAlarm.schedule(logic, endsAt: next, title: 'Repos fini', body: '${_exercise.name} · série ${_doneHere.length + 1} / ${_item.sets}');
      }
    }
  }

  void _goSet() {
    final last = _w.sets.isEmpty ? null : _w.sets.last.at;
    if (widget.sideEffects) CoupAlarm.cancel();
    setState(() {
      _restTaken = last == null ? null : ((DateTime.now().millisecondsSinceEpoch - last) / 1000).round();
      _phase = _Phase.set;
      _restEnds = null;
    });
  }

  void _skipExercise() {
    _skipped.add(_ex);
    if (!_advance()) {
      setState(() => _phase = _Phase.done);
      _finishSideEffects();
      return;
    }
    setState(() {});
  }

  void _jumpTo(int i) {
    setState(() {
      _skipped.remove(i);
      _ex = i;
      _phase = _Phase.set;
      _loadPlanned();
    });
  }

  void _finishSideEffects() {
    if (!widget.sideEffects) return;
    CoupAlarm.cancel();
  }

  Future<void> _end() async {
    if (_w.sets.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _phase = _Phase.done);
    _finishSideEffects();
  }

  Future<void> _save() async {
    _w = _w.copyWith(endAt: DateTime.now().millisecondsSinceEpoch);
    await logic.saveWorkout(_w);
    if (widget.sideEffects && _chronoActivityId != null) {
      if (logic.runningActivityId() == _chronoActivityId) logic.stopActive();
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showClosingSnackBar(SnackBar(content: Text('Séance enregistrée · ${_w.sets.length} séries'), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase == _Phase.done || _w.sets.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: switch (_phase) {
              _Phase.set => _setView(),
              _Phase.rest => _restView(),
              _Phase.done => _doneView(),
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(_w.startAt));
    final mm = elapsed.inMinutes, ss = elapsed.inSeconds % 60;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('${_w.name.toUpperCase()} · EXO ${_ex + 1} / ${widget.items.length} · $mm:${ss.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSportAccent)),
        ),
        TextButton(key: const ValueKey('workout-end'), onPressed: _end, child: const Text('Terminer')),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < widget.items.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            flex: i == _ex ? 2 : 1,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: _w.sets.where((s) => s.exerciseId == widget.items[i].exerciseId).length >= widget.items[i].sets
                    ? const Color(0xFF4CAF7D)
                    : i == _ex
                        ? kSportAccent
                        : cs.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ]),
    ]);
  }

  Widget _setView() {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final e = _exercise;
    final done = _doneHere;
    final idx = done.length;
    final last = _last;
    final prev = idx < last.length ? last[idx] : null;
    final current = SetLog(exerciseId: e.id, reps: _reps, weightKg: _kg, seconds: e.kind == ExerciseKind.duration ? _secs : null, at: 0);
    final diff = prev == null || e.kind != ExerciseKind.weight || prev.weightKg == null || _kg == null || _kg == prev.weightKg
        ? null
        : '${_kg! > prev.weightKg! ? '+' : '−'}${kgLabel((_kg! - prev.weightKg!).abs())} kg';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(),
      const SizedBox(height: 14),
      Text([if (e.gear?.isNotEmpty == true) e.gear!, 'repos ${restLabel(e.restSec)}'].join(' · '), style: TextStyle(fontSize: 13, color: mute)),
      Text(e.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Text('SÉRIE ${idx + 1} / ${_item.sets}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSportAccent)),
          const SizedBox(height: 8),
          Row(children: [
            if (e.kind == ExerciseKind.weight) ...[
              _big('POIDS', _kg == null ? '—' : '${kgLabel(_kg!)} kg', () => setState(() => _kg = math.max(0, (_kg ?? 0) - e.stepKg)),
                  () => setState(() => _kg = (_kg ?? 0) + e.stepKg), key: const ValueKey('set-kg')),
              const SizedBox(width: 10),
            ],
            if (e.kind == ExerciseKind.duration)
              _big('SECONDES', '$_secs', () => setState(() => _secs = math.max(5, _secs - 5)), () => setState(() => _secs += 5), key: const ValueKey('set-secs'))
            else
              _big('RÉPÉTITIONS', '$_reps', () => setState(() => _reps = math.max(0, _reps - 1)), () => setState(() => _reps++), key: const ValueKey('set-reps')),
          ]),
          const SizedBox(height: 8),
          Text(
            prev == null
                ? (last.isEmpty ? 'première fois' : 'dernière fois : ${last.map(setLabel).join(', ')}')
                : 'dernière fois, série ${idx + 1} : ${setLabel(prev)}${diff == null ? '' : ' · aujourd\'hui $diff'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: mute),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text('LES SÉRIES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
      const SizedBox(height: 4),
      Expanded(
        child: ListView(children: [
          for (var i = 0; i < _item.sets; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(i < done.length ? Icons.check_circle : (i == idx ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    size: 22, color: i < done.length ? const Color(0xFF4CAF7D) : (i == idx ? kSportAccent : mute)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(i < done.length ? setLabel(done[i]) : (i == idx ? setLabel(current) : '—'),
                      style: TextStyle(fontSize: 15, fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500)),
                ),
                if (i < last.length) Text('avant ${setLabel(last[i])}', style: TextStyle(fontSize: 13, color: mute)),
              ]),
            ),
        ]),
      ),
      FilledButton(
        key: const ValueKey('set-done'),
        style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(58)),
        onPressed: _setDone,
        child: Text(
          idx + 1 >= _item.sets && widget.items.length == 1 ? 'Dernière série faite' : 'Série faite · repos ${restLabel(e.restSec)}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      Row(children: [
        Flexible(child: TextButton(onPressed: _openList, child: const Text('Liste des exercices', overflow: TextOverflow.ellipsis))),
        const Spacer(),
        Flexible(child: TextButton(key: const ValueKey('ex-skip'), onPressed: _skipExercise, child: const Text('Passer cet exercice', overflow: TextOverflow.ellipsis))),
      ]),
    ]);
  }

  Widget _big(String label, String value, VoidCallback minus, VoidCallback plus, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .6))),
          FittedBox(child: Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(onPressed: minus, icon: const Icon(Icons.remove), tooltip: 'Moins'),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: plus, icon: const Icon(Icons.add), tooltip: 'Plus'),
          ]),
        ]),
      ),
    );
  }

  Future<void> _openList() async {
    final i = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (var i = 0; i < widget.items.length; i++)
          ListTile(
            leading: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
            title: Text(logic.gym.exercises[widget.items[i].exerciseId]?.name ?? 'Exercice'),
            subtitle: Text('${_w.sets.where((s) => s.exerciseId == widget.items[i].exerciseId).length} / ${widget.items[i].sets} séries'),
            selected: i == _ex,
            onTap: () => Navigator.of(ctx).pop(i),
          ),
      ]),
    );
    if (i != null) _jumpTo(i);
  }

  Widget _restView() {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final left = _restEnds == null ? 0 : math.max(0, (_restEnds!.difference(DateTime.now()).inMilliseconds / 1000).ceil());
    final e = _exercise;
    final done = _doneHere;
    final next = plannedSet(e, _item, _last, done.length);
    final prev = done.length < _last.length ? _last[done.length] : null;
    final nextLabel = done.length >= _item.sets ? e.name : '${e.name} · série ${done.length + 1} / ${_item.sets}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('REPOS · ${e.name.toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSportAccent)),
      const Spacer(),
      Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 240,
              height: 240,
              child: CircularProgressIndicator(
                value: _restTotal <= 0 ? 0 : left / _restTotal,
                strokeWidth: 16,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(kSportAccent),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                  key: const ValueKey('rest-left'), style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
              Text('sur ${restLabel(_restTotal)}', style: TextStyle(color: mute)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton(key: const ValueKey('rest-minus'), onPressed: () => _adjustRest(-15), child: const Text('−15 s')),
        const SizedBox(width: 10),
        OutlinedButton(key: const ValueKey('rest-plus'), onPressed: () => _adjustRest(15), child: const Text('+15 s')),
      ]),
      const SizedBox(height: 8),
      Text('sonne à la fin, même téléphone en veille', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: mute)),
      if (_restAdjusted != null && _restAdjusted != e.restSec)
        Center(
          child: TextButton(
            key: const ValueKey('rest-keep'),
            onPressed: () async {
              final v = _restAdjusted!;
              await logic.setExerciseRest(e.id, v);
              if (mounted) setState(() => _restAdjusted = null);
            },
            child: Text('Garder ${restLabel(_restAdjusted!)} pour cet exercice'),
          ),
        ),
      const Spacer(),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ENSUITE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
          Text(nextLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(setLabel(next), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (prev != null) Text('dernière fois : ${setLabel(prev)}', style: TextStyle(fontSize: 13, color: mute)),
        ]),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('rest-go'),
        style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(56)),
        onPressed: _goSet,
        child: const Text('J\'y vais', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
    ]);
  }

  Widget _doneView() {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final all = [..._history.where((x) => x.id != _w.id), _w];
    final sum = summarize(_w, all);
    final prev = _w.templateId == null ? null : lastWorkoutOf(_w.templateId!, _history, beforeMs: _w.startAt);
    final better = sum.byExercise.values.where((d) => d.kind == DeltaKind.better).length;
    final worse = sum.byExercise.values.where((d) => d.kind == DeltaKind.worse).length;
    final title = prev == null ? 'Séance faite' : (better > worse ? 'Mieux que ${_dayLabel(prev.ymd).split(' ').first}' : (better == worse ? 'Comme la dernière fois' : 'Un peu en dessous'));
    final ids = <String>[for (final s in _w.sets) s.exerciseId].toSet().toList();
    final nextTime = <String>[
      for (final it in widget.items)
        if (logic.gym.exercises[it.exerciseId] case final e?)
          if (e.kind == ExerciseKind.weight)
            if (suggestedWeight(e, it, _w.sets.where((s) => s.exerciseId == e.id).toList()) case final w?)
              if (_w.sets.where((s) => s.exerciseId == e.id).any((s) => (s.weightKg ?? 0) < w)) '${e.name} à ${kgLabel(w)} kg',
    ];
    Widget stat(String label, String value, String? sub, {Color? subColor}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: mute)),
              FittedBox(child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              if (sub != null) Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subColor ?? mute)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('SÉANCE TERMINÉE · ${_w.name.toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSportAccent)),
      Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      Text('${sum.durationMin} min · ${sum.sets} séries${sum.avgRest == null ? '' : ' · repos moyen ${restLabel(sum.avgRest!)}'}', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 12),
      Row(children: [
        stat('VOLUME', sum.volume > 0 ? '${sum.volume.round()} kg' : '${sum.reps} reps',
            sum.volumeDeltaPct == null ? null : '${sum.volumeDeltaPct! >= 0 ? '+' : ''}${sum.volumeDeltaPct} %',
            subColor: (sum.volumeDeltaPct ?? 0) >= 0 ? const Color(0xFF4CAF7D) : const Color(0xFFE0A24A)),
        const SizedBox(width: 8),
        stat('DURÉE', '${sum.durationMin} min', prev == null ? null : 'avant ${prev.durationMin} min'),
        const SizedBox(width: 8),
        stat('RECORDS', '${sum.records}', null),
      ]),
      const SizedBox(height: 12),
      Text(prev == null ? 'EXERCICE PAR EXERCICE' : 'EXERCICE PAR EXERCICE · AUJOURD\'HUI / AVANT',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
      const SizedBox(height: 4),
      Expanded(
        child: ListView(children: [
          for (final id in ids)
            Builder(builder: (_) {
              final now = _w.sets.where((s) => s.exerciseId == id).toList();
              final before = lastSetsOf(id, _history, beforeMs: _w.startAt);
              final d = sum.byExercise[id];
              final rec = bestSet(now) != null && isRecord(bestSet(now)!, _history, beforeMs: _w.startAt);
              final color = rec
                  ? kSportAccent
                  : switch (d?.kind) {
                      DeltaKind.better => const Color(0xFF4CAF7D),
                      DeltaKind.worse => const Color(0xFFE0A24A),
                      _ => mute,
                    };
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(logic.gym.exercises[id]?.name ?? 'Exercice', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(rec ? 'RECORD' : (d?.label ?? ''), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                    ]),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: now.map(setLabel).join(', ')),
                      if (before.isNotEmpty) TextSpan(text: '  /  ${before.map(setLabel).join(', ')}', style: TextStyle(color: mute)),
                    ]), style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              );
            }),
          if (nextTime.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('La prochaine fois', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('${nextTime.join(' · ')} · le reste pareil', style: TextStyle(color: cs.onSurface.withValues(alpha: .8))),
                ]),
              ),
            ),
        ]),
      ),
      FilledButton(
        key: const ValueKey('workout-save'),
        style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(54)),
        onPressed: _save,
        child: const Text('Enregistrer la séance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
    ]);
  }
}
