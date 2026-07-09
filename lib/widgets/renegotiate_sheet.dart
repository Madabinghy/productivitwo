import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/renegotiation.dart';

/// Renégociation (maquettes 12a/12b/12c) — entrée : « Renégocier » de la carte
/// dérive. Tactique par défaut : trois issues GÉNÉRÉES DEPUIS LE RÉEL, chacune
/// avec sa conséquence affichée. Si le diagnostic détecte 3 échecs sur la même
/// tranche récurrente, le sheet ESCALADE en structurel (12b) : le coach arrête
/// de reposer le bloc tel quel — stats à l'appui, options tirées des faits,
/// toute validation = essai 2 semaines, l'intention ne bouge jamais ici. 0 LLM.
Future<void> showRenegotiateSheet(
  BuildContext context, {
  required AppLogic logic,
  required ScheduleBlock block,
  required String date,
  void Function(ScheduleBlock block)? onLaunch,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RenegotiateSheet(
        logic: logic, block: block, date: date, onLaunch: onLaunch),
  );
}

enum _Issue { reduce, move, report }

/// Option de modalité structurelle (12b) — tirée des faits, jamais inventée.
class _ModOption {
  final bool keep; // « Garder quand même » — déconseillé mais possible
  final String bucket; // matin | midi | apres_midi | soir
  final String time; // "HH:mm"
  final int durationMin;
  final int freq; // ×N / semaine
  final String subtitle;
  final bool recommended;

  const _ModOption({
    this.keep = false,
    this.bucket = '',
    this.time = '',
    this.durationMin = 0,
    this.freq = 0,
    required this.subtitle,
    this.recommended = false,
  });
}

/// Données de l'écran de confirmation (12c) après validation.
class _Confirm {
  final bool suspended;
  final String banner;
  final String? domainName;
  final String? intention;
  final String? fromLabel;
  final String? toLabel;
  final String reason;
  final bool prepAdded;
  final String? bilanDateFr;

  const _Confirm({
    this.suspended = false,
    required this.banner,
    this.domainName,
    this.intention,
    this.fromLabel,
    this.toLabel,
    required this.reason,
    this.prepAdded = false,
    this.bilanDateFr,
  });
}

class _RenegotiateSheet extends StatefulWidget {
  final AppLogic logic;
  final ScheduleBlock block;
  final String date;
  final void Function(ScheduleBlock block)? onLaunch;

  const _RenegotiateSheet(
      {required this.logic,
      required this.block,
      required this.date,
      this.onLaunch});

  @override
  State<_RenegotiateSheet> createState() => _RenegotiateSheetState();
}

class _RenegotiateSheetState extends State<_RenegotiateSheet> {
  final _sync = FirestoreSync();
  _Issue _chosen = _Issue.reduce;
  bool _saving = false;
  String? _moveSlot; // dernier créneau libre du jour ("HH:mm")
  int _reportCount = 1; // ce report inclus
  // ── Structurel (12b) ────────────────────────────────────────────────────────
  StructuralDiagnosis? _diag;
  List<_ModOption> _options = const [];
  int _chosenOpt = 0;
  _Confirm? _confirm;

  ScheduleBlock get b => widget.block;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _moveSlot = findLastFreeSlot(now, widget.logic.todayBlocks, b.durationMin,
        excludeBlockId: b.id);
    _loadHistory(now);
  }

  /// Historique 14 jours (en parallèle) : compte les reports de la semaine
  /// (12a) ET pose le diagnostic structurel (12b) — 3 échecs même tranche.
  Future<void> _loadHistory(DateTime now) async {
    final days = await Future.wait(List.generate(14, (i) {
      final d = now.subtract(Duration(days: i + 1));
      return _sync
          .fetchDailySchedule(_ymd(d))
          .catchError((_) => null);
    }));
    final week = <ScheduleBlock>[];
    final fortnight = <ScheduleBlock>[];
    for (var i = 0; i < days.length; i++) {
      final bl =
          (days[i]?.blocks ?? const []).where((x) => x.status != 'deleted');
      fortnight.addAll(bl);
      if (i < 7) week.addAll(bl);
    }
    if (!mounted) return;
    final diag = diagnoseStructural(b, fortnight, weekBlocks: week);
    setState(() {
      _reportCount = weeklyReportCount(b, week) + 1;
      _diag = diag;
      if (diag != null) {
        _options = _buildOptions(diag);
        _chosenOpt = 0;
      }
    });
  }

  /// Domaine du bloc — via son activité liée. Introuvable = pas de trace
  /// (on ne devine jamais un domaine).
  Domain? _domain() {
    if (b.activityId == null) return null;
    Activity? act;
    for (final a in widget.logic.state.activities) {
      if (a.id == b.activityId) {
        act = a;
        break;
      }
    }
    if (act == null) return null;
    for (final d in widget.logic.state.domains) {
      if (d.id == act.domainId && !d.deleted) return d;
    }
    return null;
  }

  /// Options 12b : le créneau prouvé d'abord, une voilure réduite ensuite,
  /// « garder quand même » en dernier (déconseillé mais possible).
  List<_ModOption> _buildOptions(StructuralDiagnosis d) {
    final opts = <_ModOption>[];
    final alt = d.alternatives.isNotEmpty ? d.alternatives.first : null;
    if (alt != null) {
      final morning = alt.typicalTime.compareTo('09:30') < 0;
      opts.add(_ModOption(
        bucket: alt.bucket,
        time: alt.typicalTime,
        durationMin: b.durationMin > 30 ? 30 : b.durationMin,
        freq: d.weeklyFreq,
        subtitle:
            'Recommandé — c\'est là que tu tiens (${alt.held}/${alt.total})${morning ? ' · prep la veille incluse' : ''}',
        recommended: true,
      ));
    } else {
      // Aucun créneau prouvé : proposition honnête, étiquetée sans données.
      final bucket = d.bucket == 'matin' ? 'midi' : 'matin';
      opts.add(_ModOption(
        bucket: bucket,
        time: bucket == 'matin' ? '07:30' : '12:45',
        durationMin: b.durationMin > 25 ? 25 : b.durationMin,
        freq: d.weeklyFreq,
        subtitle: 'À tester — aucune donnée sur ce créneau pour l\'instant',
        recommended: true,
      ));
    }
    final alt2 = d.alternatives.length > 1 ? d.alternatives[1] : null;
    if (alt2 != null) {
      opts.add(_ModOption(
        bucket: alt2.bucket,
        time: alt2.typicalTime,
        durationMin: b.durationMin > 25 ? 25 : b.durationMin,
        freq: d.weeklyFreq > 1 ? d.weeklyFreq - 1 : 1,
        subtitle:
            'À tester si le premier ne suit pas — voilure réduite, pas zéro (${alt2.held}/${alt2.total} tenues)',
      ));
    } else if (alt != null && d.bucket != 'midi' && alt.bucket != 'midi') {
      opts.add(_ModOption(
        bucket: 'midi',
        time: '12:45',
        durationMin: b.durationMin > 25 ? 25 : b.durationMin,
        freq: d.weeklyFreq > 1 ? d.weeklyFreq - 1 : 1,
        subtitle:
            'À tester si le premier ne suit pas — voilure réduite, pas zéro',
      ));
    }
    opts.add(_ModOption(
      keep: true,
      subtitle: 'Déconseillé — rien n\'a changé dans ${_bucketPossessive(d.bucket)}',
    ));
    return opts;
  }

  // ── Écritures 12a (tactique) ─────────────────────────────────────────────────

  /// Minutes réellement logguées sur le bloc (même croisement que la dérive).
  int _loggedMin() {
    final now = DateTime.now();
    var total = 0;
    for (final s in widget.logic.state.sessions) {
      if (s.startAt.year != now.year ||
          s.startAt.month != now.month ||
          s.startAt.day != now.day) continue;
      final matches = (b.activityId != null && s.activityId == b.activityId) ||
          (b.taskId != null && s.taskId == b.taskId);
      if (!matches) continue;
      total += (s.endAt ?? now).difference(s.startAt).inMinutes;
    }
    return total;
  }

  Future<void> _validate() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = TimeOfDay.now();
    final nowHm =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    try {
      switch (_chosen) {
        case _Issue.reduce:
          // 25 min maintenant — 1 relance vaut mieux que 0 ; chrono à la validation.
          await _sync.updateScheduleBlockTime(widget.date, b.id,
              startTime: nowHm, durationMin: 25);
          b.startTime = nowHm;
          b.durationMin = 25;
          if (mounted) Navigator.pop(context);
          if (b.projectId != null || b.activityId != null) {
            widget.onLaunch?.call(b);
          }
          return;
        case _Issue.move:
          await _sync.updateScheduleBlockTime(widget.date, b.id,
              startTime: _moveSlot!);
          break;
        case _Issue.report:
          // Fait tracké : sauté + cause « reporte » → demain la proposition le
          // pose EN PREMIER (règle serveur), marqué reproposé, refusable.
          await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
          await _sync.updateBlockSkipReason(widget.date, b.id, 'reporte');
          break;
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a changé, réessaie.')));
      }
    }
  }

  /// « Abandonner pour aujourd'hui » — compte comme sauté (le check-in du soir
  /// demandera le pourquoi), aucune pénalité cachée.
  Future<void> _abandon() async {
    await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
    if (mounted) Navigator.pop(context);
  }

  // ── Écritures 12b/12c (structurel) ───────────────────────────────────────────

  String _reason(StructuralDiagnosis d) {
    final alt = d.alternatives.isNotEmpty ? d.alternatives.first : null;
    final altPart = alt != null
        ? ', ${alt.held}/${alt.total} tenues ${bucketLabel(alt.bucket)}'
        : '';
    return '${d.held}/${d.total} tenues à ${_hFr(d.slotHm)}$altPart';
  }

  Future<void> _validateStructural() async {
    if (_saving) return;
    final d = _diag!;
    final opt = _options[_chosenOpt];
    if (opt.keep) {
      // Gardé tel quel — rien ne change, donc rien n'est écrit.
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gardé tel quel — on en reparle si ça recasse.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final domain = _domain();
      final fromLabel = '${b.title} — ${_hFr(d.slotHm)} · ×${d.weeklyFreq}/sem';
      final toLabel =
          '${b.title} — ${bucketLabel(opt.bucket)} ${_hFr(opt.time)} · ${opt.durationMin} min · ×${opt.freq}/sem';
      final reason = '${_reason(d)} — essai 2 semaines';

      // 12c — la trace : la renégociation écrit sur le domaine.
      if (domain != null) {
        final key = b.title.trim().toLowerCase();
        final idx = domain.modalities
            .indexWhere((m) => m.toLowerCase().contains(key));
        if (idx >= 0) {
          domain.modalities[idx] = toLabel;
        } else {
          domain.modalities.add(toLabel);
        }
        domain.history.add({
          'date': now.toIso8601String(),
          'field': 'modalities',
          'from': fromLabel,
          'to': toLabel,
          'reason': reason,
        });
        domain.renegotiatedAt = now;
        await _sync.saveDomain(domain);
      }

      // Le bloc du jour ne sera pas tenu à l'ancien créneau : fait tracké.
      await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
      await _sync.updateBlockSkipReason(widget.date, b.id, 'renegocie');

      // La prep se réactive si la nouvelle modalité en a besoin (matinale).
      var prepAdded = false;
      if (opt.time.compareTo('09:30') < 0) {
        final tomorrow = _ymd(now.add(const Duration(days: 1)));
        final today = await _sync.fetchDailySchedule(widget.date);
        final already = (today?.blocks ?? const <ScheduleBlock>[]).any((x) =>
            x.isPrep && x.status != 'deleted' && x.prepForDate == tomorrow);
        if (!already) {
          await _sync.addScheduleBlock(
              widget.date,
              ScheduleBlock(
                startTime: '21:45',
                durationMin: 5,
                title: 'Préparer les affaires — ${b.title}',
                category: 'personal',
                kind: 'prep',
                prepForDate: tomorrow,
              ));
          prepAdded = true;
        }
      }

      // Bilan d'essai à J+14, déjà dans le programme : on compte et on tranche.
      final bilanDay = now.add(const Duration(days: 14));
      await _sync.addScheduleBlock(
          _ymd(bilanDay),
          ScheduleBlock(
            startTime: '20:00',
            durationMin: 15,
            title: 'Bilan d\'essai — ${b.title}',
            category: 'personal',
            kind: 'bilan',
          ));

      if (mounted) {
        setState(() {
          _saving = false;
          _confirm = _Confirm(
            banner:
                'Modalité changée — ${bucketLabel(opt.bucket)} ${_hFr(opt.time)}, essai 2 semaines',
            domainName: domain?.name,
            intention: domain?.intention,
            fromLabel: fromLabel,
            toLabel: toLabel,
            reason: _reason(d),
            prepAdded: prepAdded,
            bilanDateFr: _frDate(bilanDay),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a changé, réessaie.')));
      }
    }
  }

  /// Suspension assumée 1 semaine — sans pénalité : rien n'est posé sur le
  /// domaine jusqu'à la date, puis il redevient actif tout seul.
  Future<void> _suspend() async {
    if (_saving) return;
    final d = _diag!;
    final domain = _domain();
    if (domain == null) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final untilDay = now.add(const Duration(days: 7));
      domain.suspendedUntil = _ymd(untilDay);
      domain.history.add({
        'date': now.toIso8601String(),
        'field': 'status',
        'from': 'actif',
        'to': 'suspendu 1 semaine',
        'reason': '${_reason(d)} — suspension assumée',
      });
      domain.renegotiatedAt = now;
      await _sync.saveDomain(domain);
      await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
      await _sync.updateBlockSkipReason(widget.date, b.id, 'renegocie');
      if (mounted) {
        setState(() {
          _saving = false;
          _confirm = _Confirm(
            suspended: true,
            banner:
                '${domain.name} suspendu jusqu\'au ${_frDate(untilDay)} — assumé, sans pénalité',
            domainName: domain.name,
            intention: domain.intention,
            reason: _reason(d),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a changé, réessaie.')));
      }
    }
  }

  // ── Rendu ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = _confirm != null
        ? _confirmView(_confirm!)
        : _diag != null
            ? _structuralView(_diag!)
            : _tacticalView();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _tacticalView() {
    final cs = Theme.of(context).colorScheme;
    final logged = _loggedMin();
    final left = usefulMinutesLeft(DateTime.now());
    final leftLabel = left >= 60
        ? '${left ~/ 60} h ${(left % 60).toString().padLeft(2, '0')}'
        : '$left min';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Renégocier — ${b.title}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(
          'POSÉ À ${_hFr(b.startTime)} · $logged MIN LOGGUÉE${logged > 1 ? 'S' : ''}',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.tertiary),
        ),
        const SizedBox(height: 12),
        Text(
          'Il reste $leftLabel utiles aujourd\'hui. Trois issues — choisis en connaissance de cause.',
          style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: cs.onSurface.withOpacity(.85)),
        ),
        const SizedBox(height: 14),
        _option(
          cs,
          _Issue.reduce,
          'Réduire : 25 min, maintenant',
          'L\'essentiel vaut mieux que 0 — le chrono démarre à la validation',
        ),
        if (_moveSlot != null)
          _option(
            cs,
            _Issue.move,
            'Déplacer à ${_hFr(_moveSlot!)}',
            'Dernier créneau libre du jour${(int.tryParse(_moveSlot!.split(':').first) ?? 0) >= 19 ? ' — mord sur la soirée' : ''}',
          ),
        _option(
          cs,
          _Issue.report,
          'Reporter à demain',
          _reportCount > 1
              ? '$_reportCountᵉ report cette semaine — demain il passe en premier, avant tout'
              : 'Demain il passe en premier, avant tout',
          amber: _reportCount > 1,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _validate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(
              _saving ? 'Enregistrement…' : 'Valider — Orion repose le bloc'),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _saving ? null : _abandon,
            child: Text(
              'Abandonner pour aujourd\'hui (compte comme sauté)',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _structuralView(StructuralDiagnosis d) {
    final cs = Theme.of(context).colorScheme;
    final domain = _domain();
    final alt = d.alternatives.isNotEmpty ? d.alternatives.first : null;
    final keepChosen = _options[_chosenOpt].keep;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Le créneau de ${_hFr(d.slotHm)} ne marche pas',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(
          '${b.title.toUpperCase()} · ${d.fails} ÉCHECS SUR ${d.total} · JE NE LE REPOSE PLUS TEL QUEL',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.tertiary),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            const TextSpan(
                text:
                    'Ce n\'est plus un accident, c\'est le créneau. Ton intention ne bouge pas'),
            if (domain?.intention != null)
              TextSpan(
                  text: ' — « ${domain!.intention} »',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: cs.primary)),
            const TextSpan(text: ' — on change la modalité.'),
          ]),
          style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: cs.onSurface.withOpacity(.85)),
        ),
        const SizedBox(height: 14),
        // ── Les faits : tenue au créneau qui casse vs tranche qui tient ────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.onSurface.withOpacity(.04),
          ),
          child: Row(
            children: [
              _stat(cs, '${d.held}/${d.total}',
                  'TENUES À ${_hFr(d.slotHm).toUpperCase()}', cs.error),
              if (alt != null) ...[
                const SizedBox(width: 18),
                _stat(cs, '${alt.held}/${alt.total}',
                    'TENUES ${bucketLabel(alt.bucket).toUpperCase()}',
                    cs.primary),
              ],
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  alt != null
                      ? 'Les faits choisissent presque tout seuls.'
                      : 'Pas encore de créneau prouvé ailleurs — on teste.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: cs.onSurface.withOpacity(.55)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _options.length; i++) _modOption(cs, i),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _validateStructural,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(_saving
              ? 'Enregistrement…'
              : keepChosen
                  ? 'Garder ${_hFr(d.slotHm)} — assumé'
                  : 'Changer la modalité — essai 2 semaines'),
        ),
        if (domain != null) ...[
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _saving ? null : _suspend,
              child: Text(
                'Suspendre ${domain.name} 1 semaine (assumé, sans pénalité)',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _confirmView(_Confirm c) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.primary.withOpacity(.12),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(c.banner,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        if (c.domainName != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.onSurface.withOpacity(.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(c.domainName!,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(
                      c.suspended
                          ? 'suspendu le ${_frDate(DateTime.now())}'
                          : 'renégocié le ${_frDate(DateTime.now())}',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(.5)),
                    ),
                  ],
                ),
                if (c.intention != null) ...[
                  const SizedBox(height: 6),
                  Text('« ${c.intention} »',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withOpacity(.75))),
                ],
                if (c.fromLabel != null && c.toLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(c.fromLabel!,
                      style: TextStyle(
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                          color: cs.onSurface.withOpacity(.45))),
                  const SizedBox(height: 2),
                  Text('→ ${c.toLabel}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: cs.primary)),
                ],
                const SizedBox(height: 6),
                Text(
                  'Motif : ${c.reason}.${c.prepAdded ? ' Prep la veille réactivée.' : ''}',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: cs.onSurface.withOpacity(.55)),
                ),
              ],
            ),
          ),
        ],
        if (c.bilanDateFr != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: cs.onSurface.withOpacity(.04),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('POSÉ AU ${c.bilanDateFr!.toUpperCase()} — BILAN D\'ESSAI',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: cs.tertiary)),
                const SizedBox(height: 6),
                Text(
                  '« 2 semaines d\'essai : on compte les séances tenues et on tranche — on garde, on ajuste, ou on requestionne l\'intention. » Une renégociation est un engagement, pas une échappatoire : le bilan est déjà dans le programme.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: cs.onSurface.withOpacity(.8)),
                ),
              ],
            ),
          ),
        ],
        if (c.suspended) ...[
          const SizedBox(height: 10),
          Text(
            'Rien ne sera posé sur ce domaine d\'ici là — puis il redevient actif tout seul.',
            style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface.withOpacity(.65)),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: const Text('C\'est noté'),
        ),
      ],
    );
  }

  Widget _stat(ColorScheme cs, String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: cs.onSurface.withOpacity(.5))),
      ],
    );
  }

  Widget _modOption(ColorScheme cs, int i) {
    final o = _options[i];
    final selected = _chosenOpt == i;
    final accent = o.keep ? cs.tertiary : cs.primary;
    final title = o.keep
        ? 'Garder ${_hFr(_diag!.slotHm)} quand même'
        : '${_bucketTitle(o.bucket)} ${_hFr(o.time)} · ${o.durationMin} min · ×${o.freq} / semaine';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _chosenOpt = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accent.withOpacity(.7)
                : cs.onSurface.withOpacity(.15),
            width: selected ? 1.4 : 1,
          ),
          color: selected ? accent.withOpacity(.06) : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? accent : cs.onSurface.withOpacity(.3),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(o.subtitle,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: o.keep
                              ? cs.tertiary.withOpacity(.9)
                              : cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
      ColorScheme cs, _Issue issue, String title, String consequence,
      {bool amber = false}) {
    final selected = _chosen == issue;
    final accent = amber ? cs.tertiary : cs.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _chosen = issue),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accent.withOpacity(.7)
                : cs.onSurface.withOpacity(.15),
            width: selected ? 1.4 : 1,
          ),
          color: selected ? accent.withOpacity(.06) : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? accent : cs.onSurface.withOpacity(.3),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(consequence,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: amber
                              ? cs.tertiary.withOpacity(.9)
                              : cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Formats ──────────────────────────────────────────────────────────────────

  String _hFr(String hm) {
    final p = hm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? p[1] : '00';
    return m == '00' ? '$h h' : '$h h $m';
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _frDate(DateTime d) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
      'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _bucketTitle(String bucket) => switch (bucket) {
        'matin' => 'Matin',
        'midi' => 'Midi',
        'apres_midi' => 'Après-midi',
        _ => 'Soir',
      };

  String _bucketPossessive(String bucket) => switch (bucket) {
        'matin' => 'tes matins',
        'midi' => 'tes midis',
        'apres_midi' => 'tes après-midis',
        _ => 'tes soirées',
      };
}
