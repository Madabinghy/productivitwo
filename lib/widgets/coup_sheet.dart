import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, rootProjectOf;
import 'package:productivitwo_v1/utils/coups.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/widgets/rest_sheet.dart';

/// Lancer un rush (ex-« coup », maquette validée 2026-10-30) : UNE feuille —
/// quoi · pour (recherche par domaine, projets ou activités) · cible facultative
/// · jusqu'à quand — et, pour chaque autre domaine, un interrupteur explicite
/// « 🌙 En pause | Actif », réglé sur En pause par défaut. Même modèle qu'un
/// objectif (`horizon: "tactical"`) : même fiche, même graphe.
Future<StrategicObjective?> showCoupSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required List<Project> projects,
}) {
  return showModalBottomSheet<StrategicObjective>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .92),
        child: _RushForm(logic: logic, sync: sync, projects: projects),
      ),
    ),
  );
}

/// Ce que le rush sert : un projet OU une activité-temps.
class _Source {
  final Project? project;
  final Activity? activity;
  const _Source.project(this.project) : activity = null;
  const _Source.activity(this.activity) : project = null;
}

class _RushForm extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<Project> projects;
  const _RushForm({required this.logic, required this.sync, required this.projects});
  @override
  State<_RushForm> createState() => _RushFormState();
}

class _RushFormState extends State<_RushForm> {
  final _title = TextEditingController();
  final _target = TextEditingController();
  final _minutes = TextEditingController(text: '60');
  late DateTime _end;
  _Source? _source;
  /// Domaines laissés ACTIFS (les autres passent en pause pendant le rush).
  final Set<String> _keepActive = {};
  String? _error;
  bool _saving = false;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now();
    _end = DateTime(t.year, t.month, t.day + 4); // 5 jours, fin incluse
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String? _domainOfProject(Project p) => p.domainId ?? rootProjectOf(p, widget.projects).domainId;

  String? get _sourceDomain {
    final s = _source;
    if (s == null) return null;
    if (s.project != null) return _domainOfProject(s.project!);
    final d = s.activity!.domainId;
    return d.isEmpty ? null : d;
  }

  List<Domain> get _others => logic.state.activeDomains.where((d) => d.id != _sourceDomain).toList();

  int get _pausedCount => _others.where((d) => !_keepActive.contains(d.id)).length;

  Future<void> _pickSource() async {
    final s = await showModalBottomSheet<_Source>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .88),
        child: _SourcePicker(logic: logic, projects: widget.projects, domainOf: _domainOfProject),
      ),
    );
    if (s != null) setState(() => _source = s);
  }

  Future<void> _save() async {
    final today = DateTime.now();
    final err = validateCoup(title: _title.text, endDate: _end, today: today, hasSource: _source != null);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _saving = true);
    final minPerDay = int.tryParse(_minutes.text.trim()) ?? 0;
    final p = _source?.project;
    final a = _source?.activity;
    final o = StrategicObjective(
      title: _title.text.trim(),
      kpiTarget: _target.text.trim().isEmpty ? null : _target.text.trim(),
      horizon: 'tactical',
      domainId: _sourceDomain,
      startDate: DateTime(today.year, today.month, today.day),
      endDate: _end,
      checkInEvery: 1,
      projectIds: [if (p != null) p.id],
      timeCommitments: [if (a != null && minPerDay > 0) ObjectiveTimeCommitment(activityId: a.id, weeklyMin: minPerDay * 7)],
    );
    try {
      await widget.sync.saveStrategicObjective(o);
      final others = _others;
      await applyRest(logic, widget.sync,
          domains: others, picked: {for (final d in others) if (!_keepActive.contains(d.id)) d.id}, untilYmd: coupRestUntil(o));
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Enregistrement impossible — réessaie.';
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context, o);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: .6);
    final today = DateTime.now();
    final days = DateTime(_end.year, _end.month, _end.day).difference(DateTime(today.year, today.month, today.day)).inDays + 1;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: cs.onSurface.withValues(alpha: .55))),
        );
    final others = _others;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('⚡ Lancer un rush', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('3 à 10 jours sur une seule chose, le reste en pause.', style: TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 14),
          label('QUOI'),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Finir la séquence fractions', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          label('POUR'),
          _sourceField(cs),
          if (_source?.activity != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes par jour', border: OutlineInputBorder(), suffixText: 'min / j'),
            ),
          ],
          const SizedBox(height: 14),
          label('CIBLE · FACULTATIF'),
          TextField(
            controller: _target,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'séquence prête et imprimée', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          label('JUSQU\'À QUAND'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in const [3, 5, 7, 10])
              ChoiceChip(
                label: Text(days == n ? '$n j · ${_dayLabel(_end)}' : '$n j'),
                selected: days == n,
                onSelected: (_) => setState(() => _end = DateTime(today.year, today.month, today.day + n - 1)),
              ),
            ActionChip(
              avatar: const Icon(Icons.event_outlined, size: 16),
              label: Text(const [3, 5, 7, 10].contains(days) ? 'Date' : '$days j · ${_dayLabel(_end)}'),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _end,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 30)),
                    locale: const Locale('fr', 'FR'));
                if (d != null) setState(() => _end = d);
              },
            ),
          ]),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 16),
            label('PENDANT LE RUSH, LES AUTRES DOMAINES'),
            Row(children: [
              Expanded(child: _legend(cs, '🌙 En pause', 'Ne compte pas. Séries gelées : rien ne se perd.', filled: true)),
              const SizedBox(width: 6),
              Expanded(child: _legend(cs, '● Actif', 'Compte comme d\'habitude. Une série peut casser.', filled: false)),
            ]),
            const SizedBox(height: 6),
            for (final d in others) _domainRow(cs, d),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12.5, color: cs.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
            icon: const Icon(Icons.bolt_rounded),
            label: Text('Lancer le rush · $days j${others.isEmpty ? '' : ' · $_pausedCount en pause'}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    const wd = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    return '${wd[d.weekday - 1]} ${dayMonthFr(d)}';
  }

  Widget _sourceField(ColorScheme cs) {
    final s = _source;
    final domains = logic.state.activeDomains;
    final String title;
    final String sub;
    if (s == null) {
      title = 'Choisir un projet ou une activité';
      sub = '';
    } else if (s.project != null) {
      final p = s.project!;
      title = p.title;
      final dn = domains.where((d) => d.id == _domainOfProject(p)).firstOrNull?.name;
      sub = ['Projet', if (dn != null) dn, _openTasksLabel(p)].join(' · ');
    } else {
      final a = s.activity!;
      title = a.name;
      final dn = domains.where((d) => d.id == a.domainId).firstOrNull?.name;
      sub = ['Activité', if (dn != null) dn].join(' · ');
    }
    final color = domainColor(_sourceDomain, domains);
    return Material(
      color: cs.onSurface.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickSource,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            if (s != null) ...[
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color ?? cs.primary, shape: BoxShape.circle)),
              const SizedBox(width: 10),
            ] else ...[
              Icon(Icons.search_rounded, size: 20, color: cs.onSurface.withValues(alpha: .55)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: s == null ? cs.onSurface.withValues(alpha: .6) : null)),
                if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .55))),
              ]),
            ),
            Text(s == null ? 'Choisir' : 'Changer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
          ]),
        ),
      ),
    );
  }

  Widget _legend(ColorScheme cs, String title, String text, {required bool filled}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: filled ? cs.onSurface.withValues(alpha: .07) : null,
          border: filled ? null : Border.all(color: cs.onSurface.withValues(alpha: .2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(text, style: TextStyle(fontSize: 11.5, height: 1.3, color: cs.onSurface.withValues(alpha: .6))),
        ]),
      );

  Widget _domainRow(ColorScheme cs, Domain d) {
    final active = _keepActive.contains(d.id);
    final n = runningSeriesCount(logic, d.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: d.name),
              if (n > 0) TextSpan(text: ' · $n série${n > 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5))),
            ]),
            style: const TextStyle(fontSize: 14.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SegmentedButton<bool>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('🌙 En pause', style: TextStyle(fontSize: 12.5))),
            ButtonSegment(value: true, label: Text('Actif', style: TextStyle(fontSize: 12.5))),
          ],
          selected: {active},
          onSelectionChanged: (v) => setState(() => v.first ? _keepActive.add(d.id) : _keepActive.remove(d.id)),
        ),
      ]),
    );
  }
}

String _openTasksLabel(Project p) {
  final n = p.tasks.where((t) => t.status == 'pending' && t.id != 'gtd-flow').length;
  return '$n tâche${n > 1 ? 's' : ''} ouverte${n > 1 ? 's' : ''}';
}

/// « Pour quoi ? » : recherche, onglets Projets / Activités, rangés par domaine.
class _SourcePicker extends StatefulWidget {
  final AppLogic logic;
  final List<Project> projects;
  final String? Function(Project p) domainOf;
  const _SourcePicker({required this.logic, required this.projects, required this.domainOf});
  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  String _q = '';
  bool _activities = false;

  bool _match(String s) => _q.isEmpty || s.toLowerCase().contains(_q.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final domains = widget.logic.state.activeDomains;
    final all = widget.projects;
    final projects = all.where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, all)).toList();
    final acts = widget.logic.state.activeActivities.where((a) => !a.isHabit).toList();
    final shownProjects = projects.where((p) => _match(p.title)).toList();
    final shownActs = acts.where((a) => _match(a.name)).toList();
    final rows = <Widget>[];
    if (_activities) {
      for (final g in groupActivitiesByDomain(shownActs, domains)) {
        rows.add(ActivityDomainHeader(name: g.name, color: g.color));
        for (final a in g.activities) {
          rows.add(ListTile(
            dense: true,
            leading: const Icon(Icons.timer_outlined, size: 20),
            title: Text(a.name),
            onTap: () => Navigator.pop(context, _Source.activity(a)),
          ));
        }
      }
    } else {
      final groups = <String?, List<Project>>{};
      for (final p in shownProjects) {
        groups.putIfAbsent(widget.domainOf(p), () => []).add(p);
      }
      final order = [for (final d in domains) d.id, null];
      for (final id in order) {
        final list = groups[id];
        if (list == null) continue;
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        final d = domains.where((x) => x.id == id).firstOrNull;
        rows.add(ActivityDomainHeader(name: d?.name ?? 'Sans domaine', color: domainColor(id, domains)));
        for (final p in list) {
          final root = rootProjectOf(p, all);
          rows.add(ListTile(
            dense: true,
            leading: const Icon(Icons.view_timeline_outlined, size: 20),
            title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([if (root.id != p.id) '📁 ${root.title}', _openTasksLabel(p)].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(context, _Source.project(p)),
          ));
        }
      }
    }
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Pour quoi ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded), hintText: 'Chercher un projet ou une activité', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text('Projets · ${shownProjects.length}')),
              ButtonSegment(value: true, label: Text('Activités · ${shownActs.length}')),
            ],
            selected: {_activities},
            onSelectionChanged: (v) => setState(() => _activities = v.first),
          ),
        ),
        Flexible(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Rien ne correspond.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withValues(alpha: .5))),
                )
              : ListView(shrinkWrap: true, children: rows),
        ),
      ]),
    );
  }
}
