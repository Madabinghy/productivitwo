import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/urge_session_store.dart';
import 'package:productivitwo_v1/utils/urge_session.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/finances.dart' show euros, parseEuros;
import 'package:productivitwo_v1/utils/freedom.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:url_launcher/url_launcher.dart';

// Liberté, lot 2 (maquette validée « Sortir d'une dépendance », 2026-11-04) : créer, la feuille, le moment de
// l'envie, après un écart, ce que ça apprend, l'aide. Logique pure dans `utils/freedom.dart`.

const kFreeAccent = Color(0xFF6FD3B8);
const _freeInk = Color(0xFF062A22);
const kUrgeAccent = Color(0xFFF2A65A);
const _urgeInk = Color(0xFF2A1606);
const _rose = Color(0xFFE88A9A);
const _green = Color(0xFF5CC79A);
const _amber = Color(0xFFE8A33D);

const kFreedomTriggers = ['Stress', 'Ennui', 'Fatigue', 'Après repas', 'Café', 'Soirée', 'Seul', 'Entouré', 'Écrans'];
const kFreedomParades = ['Marcher 5 min', 'Un verre d\'eau', 'Respirer', 'Appeler quelqu\'un', 'Changer de pièce', 'Se brosser les dents'];

String _id() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

Widget _k(String t, Color c) => Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: c));

Widget _pickChips(List<String> options, Set<String> picked, void Function(String) onTap, {Color accent = kFreeAccent, Color ink = _freeInk, VoidCallback? onAdd}) =>
    Wrap(spacing: 6, runSpacing: 6, children: [
      for (final o in options)
        FilterChip(
          label: Text(o),
          selected: picked.contains(o),
          showCheckmark: false,
          selectedColor: accent,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: picked.contains(o) ? ink : null),
          onSelected: (_) => onTap(o),
        ),
      if (onAdd != null) ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Autre'), onPressed: onAdd),
    ]);

Future<String?> _askText(BuildContext context, String title, {String hint = ''}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

// ── Créer / régler ───────────────────────────────────────────────────────────

Future<void> showFreedomSetup(BuildContext context, {required AppLogic logic, String? id}) =>
    showFiche<void>(context, builder: (ctx, scroll) => FreedomSetup(logic: logic, id: id, scroll: scroll));

class FreedomSetup extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  /// null = une nouvelle chose à quitter.
  final String? id;
  const FreedomSetup({super.key, required this.logic, this.id, this.scroll});

  @override
  State<FreedomSetup> createState() => _FreedomSetupState();
}

class _FreedomSetupState extends State<FreedomSetup> {
  late final String _fid = widget.id ?? 'f${_id()}';
  FreedomPlan? get _old => widget.id == null ? null : widget.logic.freedomOf(widget.id!).plan;
  late final _name = TextEditingController(text: _old?.name ?? '');
  late final _unit = TextEditingController(text: _old?.unit ?? 'fois');
  late final _cost = TextEditingController(text: _old?.costPerDay == null ? '' : (_old!.costPerDay! / 100).toStringAsFixed(2).replaceAll('.', ','));
  late final _why = TextEditingController(text: _old?.why ?? '');
  late final _supportName = TextEditingController(text: _old?.supportName ?? '');
  late final _supportPhone = TextEditingController(text: _old?.supportPhone ?? '');
  late FreedomGoal _goal = _old?.goal ?? FreedomGoal.stop;
  late FreedomPeriod _period = _old?.period ?? FreedomPeriod.week;
  late int _limit = _old?.limit ?? 3;
  late final Set<String> _triggers = {...?_old?.triggers};
  late final Set<String> _parades = {...?_old?.parades};
  late final List<String> _triggerOptions = {...kFreedomTriggers, ..._triggers}.toList();
  late final List<String> _paradeOptions = {...kFreedomParades, ..._parades}.toList();

  @override
  void dispose() {
    for (final c in [_name, _unit, _cost, _why, _supportName, _supportPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final cost = _cost.text.trim().isEmpty ? null : parseEuros(_cost.text);
    final plan = FreedomPlan(
      name: name,
      goal: _goal,
      limit: _goal == FreedomGoal.reduce ? _limit : null,
      period: _period,
      unit: _unit.text.trim().isEmpty ? 'fois' : _unit.text.trim(),
      startYmd: _old?.startYmd ?? ymdOf(DateTime.now()),
      costPerDay: cost,
      why: _why.text.trim(),
      triggers: [for (final t in _triggerOptions) if (_triggers.contains(t)) t],
      parades: [for (final p in _paradeOptions) if (_parades.contains(p)) p],
      supportName: _supportName.text.trim(),
      supportPhone: _supportPhone.text.trim(),
      warned: true,
    );
    await widget.logic.saveFreedomPlan(_fid, plan);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    InputDecoration dec(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      _k(_old == null ? 'LIBERTÉ · UNE CHOSE À LA FOIS' : 'LIBERTÉ · RÉGLAGES', kFreeAccent),
      Text(_old == null ? 'Ce que je veux quitter' : 'Ce que je quitte', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      TextField(key: const ValueKey('freedom-name'), controller: _name, textCapitalization: TextCapitalization.sentences, decoration: dec('Son nom', hint: 'celui que tu veux, même discret')),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Personne d\'autre ne voit ce nom. L\'app ne te demande jamais ce que c\'est.', style: TextStyle(fontSize: 12, color: mute)),
      ),
      const SizedBox(height: 14),
      _k('MON BUT', mute),
      const SizedBox(height: 6),
      SegmentedButton<FreedomGoal>(
        segments: const [ButtonSegment(value: FreedomGoal.stop, label: Text('Arrêter')), ButtonSegment(value: FreedomGoal.reduce, label: Text('Réduire'))],
        selected: {_goal},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _goal = v.first),
      ),
      if (_goal == FreedomGoal.reduce) ...[
        const SizedBox(height: 10),
        Row(children: [
          IconButton(onPressed: _limit > 1 ? () => setState(() => _limit--) : null, icon: const Icon(Icons.remove)),
          Text('$_limit', key: const ValueKey('freedom-limit'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          IconButton(onPressed: () => setState(() => _limit++), icon: const Icon(Icons.add)),
          const SizedBox(width: 6),
          Expanded(
            child: SegmentedButton<FreedomPeriod>(
              segments: const [ButtonSegment(value: FreedomPeriod.day, label: Text('par jour')), ButtonSegment(value: FreedomPeriod.week, label: Text('par semaine'))],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _period = v.first),
            ),
          ),
        ]),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _unit, decoration: dec('Je compte', hint: 'fois, verres, minutes…'))),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: dec('Coût par jour · €', hint: 'facultatif'),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey('freedom-why'),
        controller: _why,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: dec('Pourquoi je le fais', hint: 'relu au moment de l\'envie'),
      ),
      const SizedBox(height: 14),
      _k('CE QUI ME POUSSE', mute),
      const SizedBox(height: 6),
      _pickChips(_triggerOptions, _triggers, (t) => setState(() => _triggers.contains(t) ? _triggers.remove(t) : _triggers.add(t)), onAdd: () async {
        final t = await _askText(context, 'Ce qui te pousse');
        if (t != null && t.isNotEmpty) setState(() => _triggerOptions.contains(t) ? _triggers.add(t) : (_triggerOptions..add(t), _triggers.add(t)));
      }),
      const SizedBox(height: 14),
      _k('MES PARADES', mute),
      const SizedBox(height: 6),
      _pickChips(_paradeOptions, _parades, (p) => setState(() => _parades.contains(p) ? _parades.remove(p) : _parades.add(p)), onAdd: () async {
        final p = await _askText(context, 'Une parade', hint: 'ce qui t\'aide à laisser passer l\'envie');
        if (p != null && p.isNotEmpty) setState(() => _paradeOptions.contains(p) ? _parades.add(p) : (_paradeOptions..add(p), _parades.add(p)));
      }),
      const SizedBox(height: 14),
      _k('QUELQU\'UN À APPELER · FACULTATIF', mute),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: TextField(controller: _supportName, textCapitalization: TextCapitalization.words, decoration: dec('Prénom'))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _supportPhone, keyboardType: TextInputType.phone, decoration: dec('Téléphone'))),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _amber.withValues(alpha: .4))),
        child: const Text(
          'Si ton corps en dépend, un arrêt brutal peut être dangereux. Demande conseil à un médecin avant de commencer.',
          style: TextStyle(fontSize: 13, height: 1.35),
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        key: const ValueKey('freedom-save'),
        style: FilledButton.styleFrom(backgroundColor: kFreeAccent, foregroundColor: _freeInk, minimumSize: const Size.fromHeight(52)),
        onPressed: _save,
        child: Text(_old == null ? 'Commencer' : 'Enregistrer', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
      if (_old != null)
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Arrêter le suivi ?'),
                content: const Text('Le suivi disparaît de l\'app. Tes envies et écarts restent enregistrés si tu recommences.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arrêter le suivi')),
                ],
              ),
            );
            if (ok == true) {
              await widget.logic.saveFreedomPlan(_fid, null);
              if (mounted) Navigator.of(context).pop();
            }
          },
          child: const Text('Arrêter le suivi'),
        ),
    ]);
  }
}

// ── La feuille ───────────────────────────────────────────────────────────────

Future<void> showFreedomSheet(BuildContext context, {required AppLogic logic, required String id}) =>
    showFiche<void>(context, builder: (ctx, scroll) => FreedomView(logic: logic, id: id, scroll: scroll));

class FreedomView extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  final String id;
  const FreedomView({super.key, required this.logic, required this.id, this.scroll});

  @override
  State<FreedomView> createState() => _FreedomViewState();
}

class _FreedomViewState extends State<FreedomView> {
  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final f = logic.freedomOf(widget.id);
    final p = f.plan;
    if (p == null) {
      return ListView(controller: widget.scroll, padding: const EdgeInsets.all(16), children: [
        const Text('Liberté', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Une chose que tu veux arrêter ou réduire. Tu lui donnes le nom que tu veux.', style: TextStyle(color: mute)),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kFreeAccent, foregroundColor: _freeInk, minimumSize: const Size.fromHeight(50)),
          onPressed: () => showFreedomSetup(context, logic: logic, id: widget.id),
          child: const Text('Commencer', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]);
    }
    final now = DateTime.now();
    final stop = p.goal == FreedomGoal.stop;
    final since = freeSince(f);
    final free = now.difference(since);
    final overcome = urgesOvercome(f);
    final saved = savedCents(f, now);
    final trend = intensityTrendPct(f, now);
    final days = urgeDays(f, now);
    final maxU = days.fold<int>(1, (a, d) => math.max(a, d.urges));
    final next = nextMilestone(free);
    final used = usedThisPeriod(f, now);
    final slips = f.slipList;
    final lastSlip = slips.isEmpty ? null : slips.last;
    Widget stat(String v, String l, {Color? c}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c))),
              Text(l, style: TextStyle(fontSize: 11, color: mute, height: 1.25)),
            ]),
          ),
        );
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      Row(children: [
        Expanded(child: Text(p.name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: kFreeAccent, borderRadius: BorderRadius.circular(99)),
          child: Text(stop ? 'arrêt' : 'réduire', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _freeInk)),
        ),
        IconButton(tooltip: 'Réglages', onPressed: () => showFreedomSetup(context, logic: logic, id: widget.id), icon: const Icon(Icons.tune)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [Color(0xFF14362C), Color(0xFF10221C)]),
          border: Border.all(color: const Color(0xFF23463A)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _k(stop ? 'LIBRE DEPUIS' : (p.period == FreedomPeriod.day ? 'AUJOURD\'HUI' : 'CETTE SEMAINE'), kFreeAccent),
          const SizedBox(height: 2),
          Text(
            stop ? freeLabel(free) : '$used / ${p.limit ?? '?'} ${p.unit}',
            key: const ValueKey('freedom-hero'),
            style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, height: 1.05, color: !stop && overLimit(f, now) ? _amber : null),
          ),
          const SizedBox(height: 4),
          Text(
            stop
                ? (lastSlip == null ? 'depuis le début' : 'depuis le dernier écart · ${slips.length} écart${slips.length > 1 ? 's' : ''} en tout, et reparti à chaque fois')
                : (p.limit == null ? '' : (used <= p.limit! ? 'encore ${p.limit! - used} ${p.unit}' : 'limite dépassée : un écart, rien de plus')),
            style: TextStyle(fontSize: 13, color: mute),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        stat('$overcome', 'envies surmontées · jamais perdues', c: kFreeAccent),
        const SizedBox(width: 6),
        stat(saved > 0 ? euros(saved) : '—', stop ? 'pas dépensés' : 'à suivre en arrêt'),
        const SizedBox(width: 6),
        stat(trend == null ? '—' : '${trend > 0 ? '+' : '−'}${trend.abs()} %', 'force des envies en 7 j', c: trend == null ? null : (trend <= 0 ? _green : _amber)),
      ]),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('freedom-urge'),
        style: FilledButton.styleFrom(backgroundColor: kUrgeAccent, foregroundColor: _urgeInk, minimumSize: const Size.fromHeight(58)),
        onPressed: () => showUrgeScreen(context, logic: logic, id: widget.id),
        child: const Text('J\'ai une envie', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        key: const ValueKey('freedom-slip'),
        onPressed: () => showSlipSheet(context, logic: logic, id: widget.id),
        child: Text(stop ? 'Noter un écart' : 'Noter une fois'),
      ),
      const SizedBox(height: 14),
      _k('CES 14 JOURS · ENVIES', mute),
      const SizedBox(height: 6),
      SizedBox(
        height: 56,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, d) in days.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: d.urges == 0 ? 3 : 56 * (d.urges / maxU).clamp(.12, 1.0),
                decoration: BoxDecoration(
                  color: d.slip ? _rose : (d.urges == 0 ? cs.onSurface.withValues(alpha: .08) : kUrgeAccent.withValues(alpha: .85)),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 4),
      Text('hauteur = nombre d\'envies · rose = jour d\'écart', style: TextStyle(fontSize: 11.5, color: mute)),
      if (stop) ...[
        const SizedBox(height: 14),
        _k('PROCHAINS CAPS', mute),
        const SizedBox(height: 4),
        for (final m in kFreedomMilestones.where((m) => m >= 7).take(3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(free.inDays >= m ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: kFreeAccent),
              const SizedBox(width: 8),
              Expanded(child: Text(milestoneLabel(m) + (p.costPerDay != null ? ' · ${euros(p.costPerDay! * m)} de côté' : ''))),
              Text(free.inDays >= m ? '✓' : 'dans ${m - free.inDays} j', style: TextStyle(color: mute)),
            ]),
          ),
        if (next != null && next.days < 7) Text('Prochain cap : ${milestoneLabel(next.days)} · dans ${next.left} j', style: TextStyle(fontSize: 12, color: mute)),
      ],
      const SizedBox(height: 10),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insights_outlined, color: kFreeAccent),
        title: const Text('Ce que ça m\'apprend'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showFreedomInsights(context, logic: logic, id: widget.id),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.support_outlined, color: kFreeAccent),
        title: const Text('Trouver de l\'aide'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showFreedomHelp(context),
      ),
    ]);
  }
}

// ── Le moment de l'envie ─────────────────────────────────────────────────────

/// Ouvre l'écran de l'envie : reprend l'envie en cours de cette chose s'il y en a
/// une (le minuteur a continué pendant qu'on faisait autre chose).
Future<void> showUrgeScreen(BuildContext context, {required AppLogic logic, required String id}) async {
  final pending = await UrgeSessionStore.load();
  if (!context.mounted) return;
  final resume = pending != null && pending.freedomId == id ? pending : null;
  await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => UrgeScreen(logic: logic, id: id, resume: resume)));
}

/// Rouvre l'envie en cours, quelle que soit la chose (carte d'Aujourd'hui, notification).
Future<void> reopenPendingUrge(BuildContext context, {required AppLogic logic}) async {
  final pending = await UrgeSessionStore.load();
  if (pending == null || !context.mounted) return;
  await showUrgeScreen(context, logic: logic, id: pending.freedomId);
}

class UrgeScreen extends StatefulWidget {
  final AppLogic logic;
  /// Faux en test : pas de minuteur, ni alarme.
  final bool ticking;
  final String id;
  final PendingUrge? resume;
  const UrgeScreen({super.key, required this.logic, required this.id, this.ticking = true, this.resume});

  @override
  State<UrgeScreen> createState() => _UrgeScreenState();
}

class _UrgeScreenState extends State<UrgeScreen> {
  AppLogic get logic => widget.logic;
  late PendingUrge _u = widget.resume ?? PendingUrge(freedomId: widget.id, startMs: DateTime.now().millisecondsSinceEpoch);
  final List<String> _extraParades = [];
  Timer? _tick;

  DateTime get _start => _u.start;

  @override
  void initState() {
    super.initState();
    if (widget.resume == null) {
      UrgeSessionStore.save(_u);
      if (widget.ticking) {
        final name = logic.freedomOf(widget.id).plan?.name;
        CoupAlarm.scheduleUrge(logic,
            at: _u.endsAt, title: 'Les 10 minutes sont passées', body: '${name == null || name.isEmpty ? 'Ton envie' : name} : alors, ça a été ?');
      }
    }
    final p = _u.parade;
    if (p != null && !(logic.freedomOf(widget.id).plan?.parades.contains(p) ?? false) && !kFreedomParades.contains(p)) _extraParades.add(p);
    if (widget.ticking) _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _update(PendingUrge u) {
    setState(() => _u = u);
    UrgeSessionStore.save(u);
  }

  /// Quitter sans rien arrêter : le minuteur continue et sonnera au bout.
  void _goAway() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final e = _u.endsAt;
    Navigator.of(context).pop();
    if (!_u.isOver(DateTime.now())) {
      messenger?.showClosingSnackBar(SnackBar(
        content: Text('Le minuteur continue · il sonnera à ${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _cancel() async {
    await UrgeSessionStore.clear();
    if (widget.ticking) unawaited(CoupAlarm.cancelUrge());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addParade() async {
    final p = await _askText(context, 'Ce que j\'ai fait', hint: 'ce qui t\'a aidé à laisser passer l\'envie');
    if (p == null || p.isEmpty || !mounted) return;
    setState(() => _extraParades.add(p));
    _update(_u.copyWith(parade: p));
  }

  Future<void> _finish(bool passed) async {
    final u = FreedomUrge(
      id: _id(),
      at: _u.startMs,
      intensity: _u.intensity,
      trigger: _u.trigger,
      parade: _u.parade,
      passed: passed,
      durationSec: math.min(DateTime.now().difference(_start).inSeconds, kUrgeWaveSec),
    );
    await logic.logUrge(widget.id, u);
    await UrgeSessionStore.clear();
    if (widget.ticking) unawaited(CoupAlarm.cancelUrge());
    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    nav.pop();
    if (passed) {
      messenger.showClosingSnackBar(SnackBar(content: Text('Envie surmontée · ${urgesOvercome(logic.freedomOf(widget.id))} en tout'), duration: const Duration(seconds: 3)));
    } else {
      await showSlipSheet(nav.context, logic: logic, id: widget.id, trigger: _u.trigger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final f = logic.freedomOf(widget.id);
    final p = f.plan;
    final now = DateTime.now();
    final elapsed = now.difference(_start).inSeconds;
    final left = _u.secondsLeft(now);
    final over = widget.ticking && left == 0;
    final best = bestParade(f);
    final rates = {for (final r in paradeRates(f)) r.parade: r};
    final breath = ['Inspire', 'Bloque', 'Expire'][(elapsed % 14) < 4 ? 0 : ((elapsed % 14) < 8 ? 1 : 2)];
    final triggers = {...?p?.triggers, ...kFreedomTriggers}.take(8).toList();
    final parades = <String>[...?p?.parades];
    // À la fin, on demande ce qui a été fait : sans parades réglées, les idées par défaut.
    if (over && parades.isEmpty) parades.addAll(kFreedomParades);
    for (final x in _extraParades) {
      if (!parades.contains(x)) parades.add(x);
    }
    if (best != null && parades.remove(best)) parades.insert(0, best);
    final hasSupport = p?.supportPhone != null && p!.supportPhone!.isNotEmpty;
    final paradeChips = Wrap(spacing: 6, runSpacing: 6, children: [
      for (final pa in parades)
        ChoiceChip(
          label: Text(rates[pa] != null && rates[pa]!.tried >= 3 ? '$pa · ${rates[pa]!.passed}/${rates[pa]!.tried}' : pa),
          selected: _u.parade == pa,
          showCheckmark: false,
          selectedColor: kFreeAccent,
          side: pa == best ? const BorderSide(color: kFreeAccent) : null,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _u.parade == pa ? _freeInk : null),
          onSelected: (_) => _update(_u.parade == pa ? _u.copyWith(clearParade: true) : _u.copyWith(parade: pa)),
        ),
      if (hasSupport && !over)
        ActionChip(
          avatar: const Icon(Icons.call, size: 16),
          label: Text('Appeler ${p.supportName?.isNotEmpty == true ? p.supportName : ''}'.trim()),
          onPressed: () {
            _update(_u.copyWith(parade: 'Appeler ${p.supportName ?? ''}'.trim()));
            launchUrl(Uri(scheme: 'tel', path: p.supportPhone));
          },
        ),
      ActionChip(key: const ValueKey('urge-add-parade'), avatar: const Icon(Icons.add, size: 16), label: const Text('Autre'), onPressed: _addParade),
    ]);
    return Scaffold(
      backgroundColor: const Color(0xFF0E1A16),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 20), children: [
          Row(children: [
            Expanded(child: _k('ENVIE · ${TimeOfDay.fromDateTime(_start).format(context)}', kUrgeAccent)),
            if (!over)
              TextButton.icon(
                key: const ValueKey('urge-away'),
                onPressed: _goAway,
                icon: const Icon(Icons.north_east, size: 16),
                label: const Text('Faire autre chose'),
              ),
          ]),
          if (over) ...[
            const SizedBox(height: 6),
            const Text('Les 10 minutes sont passées.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Alors, ça a été ?', style: TextStyle(fontSize: 15, color: mute)),
            const SizedBox(height: 16),
            _k('QU\'AS-TU FAIT ?', mute),
            const SizedBox(height: 6),
            paradeChips,
            const SizedBox(height: 14),
            _k('ELLE ÉTAIT FORTE COMMENT ?', mute),
            const SizedBox(height: 6),
          ] else
            _k('ELLE EST FORTE COMMENT ?', mute),
          if (!over) const SizedBox(height: 6),
          Row(children: [
            for (var i = 1; i <= 5; i++) ...[
              if (i > 1) const SizedBox(width: 5),
              Expanded(
                child: ChoiceChip(
                  key: ValueKey('urge-$i'),
                  label: SizedBox(width: double.infinity, child: Text('$i', textAlign: TextAlign.center)),
                  selected: _u.intensity == i,
                  showCheckmark: false,
                  selectedColor: kUrgeAccent,
                  labelStyle: TextStyle(fontWeight: FontWeight.w900, color: _u.intensity == i ? _urgeInk : null),
                  onSelected: (_) => _update(_u.copyWith(intensity: i)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          _pickChips(triggers, {if (_u.trigger != null) _u.trigger!}, (t) => _update(_u.trigger == t ? _u.copyWith(clearTrigger: true) : _u.copyWith(trigger: t)),
              accent: kUrgeAccent, ink: _urgeInk),
          if (!over) ...[
            const SizedBox(height: 14),
            Center(
              child: SizedBox(
                width: 190,
                height: 190,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 190,
                    height: 190,
                    child: CircularProgressIndicator(
                      value: left / kUrgeWaveSec,
                      strokeWidth: 14,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: const AlwaysStoppedAnimation(kFreeAccent),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900)),
                    Text('une envie passe en 10 min', style: TextStyle(fontSize: 12, color: mute)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text('$breath · inspire 4 s, bloque 4 s, expire 6 s', textAlign: TextAlign.center, style: TextStyle(color: mute)),
            const SizedBox(height: 4),
            Text('Tu peux faire autre chose : le minuteur continue et sonnera au bout.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: mute)),
            if (p != null && p.why.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(left: BorderSide(color: kFreeAccent, width: 3)),
                ),
                child: Text('« ${p.why} »', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic)),
              ),
            ],
            const SizedBox(height: 14),
            _k('UNE PARADE MAINTENANT', mute),
            const SizedBox(height: 6),
            paradeChips,
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('urge-passed'),
                style: FilledButton.styleFrom(backgroundColor: kFreeAccent, foregroundColor: _freeInk, minimumSize: const Size.fromHeight(52)),
                onPressed: () => _finish(true),
                child: Text(over ? 'Ça a été' : 'Elle est passée', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('urge-slipped'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _finish(false),
                child: const Text('J\'ai craqué'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              key: const ValueKey('urge-cancel'),
              onPressed: _cancel,
              child: Text('Fausse alerte · ne pas la compter', style: TextStyle(color: mute)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Envie en cours, écran quitté (2026-11-04) : en tête d'Aujourd'hui, le temps
/// qui reste et « Revenir » ; au bout des 10 min, l'écran se rouvre une fois de
/// lui-même pour demander comment ça s'est passé.
class PendingUrgeCard extends StatefulWidget {
  final AppLogic logic;
  const PendingUrgeCard({super.key, required this.logic});

  @override
  State<PendingUrgeCard> createState() => _PendingUrgeCardState();
}

class _PendingUrgeCardState extends State<PendingUrgeCard> with WidgetsBindingObserver {
  static int? _autoOpenedFor;
  static bool _open = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UrgeSessionStore.load().then((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    final u = UrgeSessionStore.current;
    // Le minuteur de la carte ne tourne que pendant une envie.
    if (u == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    }
    if (u != null && u.isOver(DateTime.now()) && _autoOpenedFor != u.startMs && !_open) {
      _autoOpenedFor = u.startMs;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reopen();
      });
    }
  }

  Future<void> _reopen() async {
    if (_open) return;
    _open = true;
    try {
      await reopenPendingUrge(context, logic: widget.logic);
    } finally {
      _open = false;
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final u = UrgeSessionStore.current;
    if (u == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final over = u.isOver(now);
    final name = widget.logic.freedomOf(u.freedomId).plan?.name;
    final left = (u.secondsLeft(now) / 60).ceil();
    return Container(
      key: const ValueKey('urge-pending-card'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kUrgeAccent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kUrgeAccent.withValues(alpha: .5)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((over ? 'Envie · les 10 min sont passées' : 'Envie en cours · reste $left min').toUpperCase(),
                style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .7))),
            const SizedBox(height: 3),
            Text(over ? 'Alors, ça a été ?' : 'Tiens bon${name == null || name.isEmpty ? '' : ' · $name'}. Le minuteur sonnera au bout.',
                style: TextStyle(fontSize: 13.5, color: cs.onSurface.withValues(alpha: .8))),
          ]),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: _reopen,
          style: FilledButton.styleFrom(backgroundColor: kUrgeAccent, foregroundColor: _urgeInk),
          child: Text(over ? 'Répondre' : 'Revenir', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// ── Après un écart ───────────────────────────────────────────────────────────

Future<void> showSlipSheet(BuildContext context, {required AppLogic logic, required String id, String? trigger}) =>
    showFiche<void>(context, builder: (ctx, scroll) => SlipView(logic: logic, id: id, scroll: scroll, trigger: trigger));

class SlipView extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  final String? trigger;
  final String id;
  const SlipView({super.key, required this.logic, required this.id, this.scroll, this.trigger});

  @override
  State<SlipView> createState() => _SlipViewState();
}

class _SlipViewState extends State<SlipView> {
  int _count = 1;
  late final Set<String> _triggers = {if (widget.trigger != null) widget.trigger!};
  final _next = TextEditingController();
  bool _toReduce = false;

  @override
  void dispose() {
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final logic = widget.logic;
    final p = logic.freedomOf(widget.id).plan;
    await logic.logSlip(widget.id, FreedomSlip(id: _id(), at: DateTime.now().millisecondsSinceEpoch, count: _count, triggers: _triggers.toList(), next: _next.text.trim()));
    if (_toReduce && p != null && p.goal == FreedomGoal.stop) {
      await logic.saveFreedomPlan(widget.id, p.copyWith(goal: FreedomGoal.reduce, limit: p.limit ?? 3));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final f = widget.logic.freedomOf(widget.id);
    final p = f.plan;
    final stop = p?.goal != FreedomGoal.reduce;
    final now = DateTime.now();
    final saved = savedCents(f, now);
    final triggers = {...?p?.triggers, ...kFreedomTriggers}.toList();
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      _k(stop ? 'NOTER UN ÉCART' : 'NOTER UNE FOIS', _rose),
      Text(stop ? 'Un écart, pas une rechute.' : 'C\'est noté, sans jugement.', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(
        'Ce qui ne bouge pas : ${urgesOvercome(f)} envie${urgesOvercome(f) > 1 ? 's' : ''} surmontée${urgesOvercome(f) > 1 ? 's' : ''}${saved > 0 ? ', ${euros(saved)} de côté' : ''}.',
        style: TextStyle(fontSize: 13, color: mute),
      ),
      const SizedBox(height: 14),
      _k('COMBIEN · FACULTATIF', mute),
      Row(children: [
        IconButton(onPressed: _count > 1 ? () => setState(() => _count--) : null, icon: const Icon(Icons.remove)),
        Text('$_count ${p?.unit ?? 'fois'}', key: const ValueKey('slip-count'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        IconButton(onPressed: () => setState(() => _count++), icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 8),
      _k('CE QUI A POUSSÉ', mute),
      const SizedBox(height: 6),
      _pickChips(triggers, _triggers, (t) => setState(() => _triggers.contains(t) ? _triggers.remove(t) : _triggers.add(t)), accent: _rose, ink: const Color(0xFF2A0E14)),
      const SizedBox(height: 12),
      TextField(
        controller: _next,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'La prochaine fois, je…', border: OutlineInputBorder(), isDense: true),
      ),
      if (stop) ...[
        const SizedBox(height: 14),
        _k('ET MAINTENANT', mute),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Je repars aujourd\'hui')), ButtonSegment(value: true, label: Text('Je passe en réduire'))],
          selected: {_toReduce},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _toReduce = v.first),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('slip-save'),
        style: FilledButton.styleFrom(backgroundColor: kFreeAccent, foregroundColor: _freeInk, minimumSize: const Size.fromHeight(52)),
        onPressed: _save,
        child: Text(stop ? 'Repartir' : 'Noter', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    ]);
  }
}

// ── Ce que ça m'apprend ──────────────────────────────────────────────────────

Future<void> showFreedomInsights(BuildContext context, {required AppLogic logic, required String id}) =>
    showFiche<void>(context, builder: (ctx, scroll) => FreedomInsights(logic: logic, id: id, scroll: scroll));

class FreedomInsights extends StatelessWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  final String id;
  const FreedomInsights({super.key, required this.logic, required this.id, this.scroll});

  static const _slotLabels = ['6 h', '10 h', '14 h', '18 h', '22 h', '2 h'];
  static const _slotNames = ['le matin', 'en fin de matinée', 'après le déjeuner', 'en fin de journée', 'le soir', 'la nuit'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final f = logic.freedomOf(id);
    final now = DateTime.now();
    final heat = urgeHeat(f, now);
    final maxH = heat.expand((r) => r).fold<int>(1, math.max);
    final triggers = triggerShares(f, now).take(4).toList();
    final slipT = slipTriggers(f, now);
    final slipsN = f.slips.values.where((s) => DateTime.fromMillisecondsSinceEpoch(s.at).isAfter(now.subtract(const Duration(days: 30)))).length;
    final rates = paradeRates(f).take(5).toList();
    final mean = meanUrgeSec(f);
    final trend = intensityTrendPct(f, now);
    ({int row, int slot})? peak;
    var peakN = 0;
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 6; c++) {
        if (heat[r][c] > peakN) {
          peakN = heat[r][c];
          peak = (row: r, slot: c);
        }
      }
    }
    Widget line(String a, String b, {Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Expanded(child: Text(a)), Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: c))]),
        );
    final empty = f.urges.isEmpty;
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      _k('CE QUE ÇA T\'APPREND · 30 JOURS', kFreeAccent),
      Text(f.plan?.name ?? 'Liberté', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      if (empty) Text('Note tes envies avec « J\'ai une envie » : c\'est ici que tu verras quand elles viennent et ce qui marche pour toi.', style: TextStyle(color: mute)),
      if (!empty) ...[
        _k('TES ENVIES · QUAND', mute),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FixedColumnWidth(40)},
          children: [
            TableRow(children: [const SizedBox(), for (final l in _slotLabels) Center(child: Text(l, style: TextStyle(fontSize: 10, color: mute)))]),
            for (final (r, name) in [(0, 'sem.'), (1, 'w-e')])
              TableRow(children: [
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(name, style: TextStyle(fontSize: 11, color: mute))),
                for (var c = 0; c < 6; c++)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: heat[r][c] == 0 ? cs.surfaceContainerHighest.withValues(alpha: .5) : kUrgeAccent.withValues(alpha: .2 + .8 * heat[r][c] / maxH),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ]),
          ],
        ),
        if (peak != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Ton creux : ${_slotNames[peak.slot]} ${peak.row == 0 ? 'en semaine' : 'le week-end'}.', style: TextStyle(fontSize: 13, color: mute)),
          ),
        if (triggers.isNotEmpty) ...[
          const SizedBox(height: 14),
          _k('CE QUI TE POUSSE', mute),
          for (final t in triggers) line(t.trigger, '${(t.share * 100).round()} %'),
        ],
        if (slipT.isNotEmpty) ...[
          const SizedBox(height: 10),
          _k('TES ÉCARTS · CE QUI LES ENTOURE', mute),
          for (final e in (slipT.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3))
            line(e.key, '${e.value} / $slipsN écart${slipsN > 1 ? 's' : ''}', c: _amber),
        ],
        if (rates.isNotEmpty) ...[
          const SizedBox(height: 10),
          _k('CE QUI MARCHE POUR TOI', mute),
          for (final r in rates) line(r.parade ?? 'Rien de fait', '${r.passed} / ${r.tried} tenues', c: r.tried > 0 && r.passed / r.tried >= .7 ? _green : null),
        ],
        const SizedBox(height: 10),
        Text(
          [
            if (mean != null) 'Une envie dure en moyenne ${(mean / 60).round()} min',
            if (trend != null) 'elle est ${trend <= 0 ? '${trend.abs()} % moins forte' : '$trend % plus forte'} que la semaine d\'avant',
          ].join(', ') + (mean != null || trend != null ? '.' : ''),
          style: TextStyle(fontSize: 13, color: mute),
        ),
      ],
    ]);
  }
}

// ── Trouver de l'aide ────────────────────────────────────────────────────────

Future<void> showFreedomHelp(BuildContext context) => showFiche<void>(context, builder: (ctx, scroll) {
      final mute = Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .6);
      Widget call(String name, String sub, String tel) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.call, color: kFreeAccent),
            onTap: () => launchUrl(Uri(scheme: 'tel', path: tel.replaceAll(' ', ''))),
          );
      return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        _k('TROUVER DE L\'AIDE', kFreeAccent),
        const Text('Tu n\'as pas à le faire seul', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('D\'abord ton médecin : il peut t\'accompagner, et c\'est indispensable si ton corps en dépend. Ensuite, des lignes d\'écoute gratuites et anonymes.',
            style: TextStyle(color: mute, height: 1.35)),
        const SizedBox(height: 10),
        call('Drogues info service', 'toutes les dépendances · 8 h – 2 h', '0 800 23 13 13'),
        call('Alcool info service', '8 h – 2 h', '0 980 980 930'),
        call('Tabac info service', 'avec un tabacologue', '39 89'),
        call('Joueurs info service', 'jeux d\'argent', '09 74 75 13 13'),
        call('SOS Amitié', 'quand ça va mal · 24 h / 24', '09 72 39 40 50'),
        const SizedBox(height: 8),
        Text('L\'app ne remplace pas un suivi médical.', style: TextStyle(fontSize: 12, color: mute)),
      ]);
    });
