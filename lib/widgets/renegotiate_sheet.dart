import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/renegotiation.dart';
import 'package:productivitwo_v1/utils/routine_context.dart';
import 'package:productivitwo_v1/widgets/availability_sheet.dart';
import 'package:productivitwo_v1/widgets/move_block_sheet.dart';

/// Renégociation / sheet du bloc actif (maquettes 12a/12b/12c + 23b) —
/// entrée : « Renégocier » de la carte dérive. Issues GÉNÉRÉES DEPUIS LE RÉEL,
/// verbes qui PORTENT L'OBJET (« Reporter « X » → ce soir 18:30 · juste ce
/// bloc »), exécution au tap. La bascule système (mode soirée) est isolée sous
/// un séparateur « TOUTE LA JOURNÉE » avec sa conséquence écrite — déplacer ≠
/// reporter ≠ basculer. Si le diagnostic détecte 3 échecs sur la même tranche
/// récurrente, le sheet ESCALADE en structurel (12b) : stats à l'appui,
/// options tirées des faits, toute validation = essai 2 semaines. 0 LLM.
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
  bool _saving = false;
  String? _moveSlot; // dernier créneau libre du jour ("HH:mm")
  int _reportCount = 1; // ce report inclus
  // ── Structurel (12b) ────────────────────────────────────────────────────────
  StructuralDiagnosis? _diag;
  List<_ModOption> _options = const [];
  int _chosenOpt = 0;
  _Confirm? _confirm;

  ScheduleBlock get b => widget.block;

  /// Routine du bloc (si liée) — porte son contexte horaire et sa
  /// méta-intention (utils/routine_context.dart).
  Activity? _routine() {
    for (final a in widget.logic.state.activities) {
      if (a.id == b.activityId) return a;
    }
    return null;
  }

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
    // Contexte horaire de la routine (override user sinon catalogue) : une
    // tranche HORS fenêtre n'est jamais une option — « Hygiène du soir à
    // midi » contredit la nature de la routine (constaté sur build).
    final act = _routine();
    final ctx = act != null ? effTimeContextOf(act) : null;
    final alts =
        d.alternatives.where((a) => contextAllowsBucket(ctx, a.bucket)).toList();
    final alt = alts.isNotEmpty ? alts.first : null;
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
      // Aucun créneau prouvé (ou tous hors fenêtre) : essai honnête, DANS la
      // fenêtre naturelle de la routine si elle en a une — à une AUTRE heure
      // que celle qui casse.
      final bucket = ctx != null
          ? bucketOfContext(ctx)
          : (d.bucket == 'matin' ? 'midi' : 'matin');
      final anchor = ctx != null
          ? '${(ctx.anchorMin ~/ 60).toString().padLeft(2, '0')}:${(ctx.anchorMin % 60).toString().padLeft(2, '0')}'
          : (bucket == 'matin' ? '07:30' : '12:45');
      opts.add(_ModOption(
        bucket: bucket,
        time: anchor == d.slotHm && ctx != null
            // L'ancre tombe pile sur l'heure qui casse : décale de 45 min.
            ? '${((ctx.anchorMin + 45) ~/ 60).toString().padLeft(2, '0')}:${((ctx.anchorMin + 45) % 60).toString().padLeft(2, '0')}'
            : anchor,
        durationMin: b.durationMin > 25 ? 25 : b.durationMin,
        freq: d.weeklyFreq,
        subtitle: ctx != null
            ? 'À tester — autre heure dans sa fenêtre naturelle (${ctx.label.toLowerCase()})'
            : 'À tester — aucune donnée sur ce créneau pour l\'instant',
        recommended: true,
      ));
    }
    final alt2 = alts.length > 1 ? alts[1] : null;
    if (alt2 != null) {
      opts.add(_ModOption(
        bucket: alt2.bucket,
        time: alt2.typicalTime,
        durationMin: b.durationMin > 25 ? 25 : b.durationMin,
        freq: d.weeklyFreq > 1 ? d.weeklyFreq - 1 : 1,
        subtitle:
            'À tester si le premier ne suit pas — voilure réduite, pas zéro (${alt2.held}/${alt2.total} tenues)',
      ));
    } else if (alt != null &&
        d.bucket != 'midi' &&
        alt.bucket != 'midi' &&
        contextAllowsBucket(ctx, 'midi')) {
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

  /// « Réduire à 25 min — maintenant » : 1 relance vaut mieux que 0, chrono au tap.
  Future<void> _actReduce() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = TimeOfDay.now();
    final nowHm =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    try {
      await _sync.updateScheduleBlockTime(widget.date, b.id,
          startTime: nowHm, durationMin: 25);
      b.startTime = nowHm;
      b.durationMin = 25;
      if (mounted) Navigator.pop(context);
      if (b.projectId != null || b.activityId != null) {
        widget.onLaunch?.call(b);
      }
    } catch (_) {
      _fail();
    }
  }

  /// « Reporter « X » → <créneau> » : juste ce bloc, le reste ne bouge pas.
  Future<void> _actMoveToSlot() async {
    if (_saving || _moveSlot == null) return;
    setState(() => _saving = true);
    try {
      await _sync.updateScheduleBlockTime(widget.date, b.id,
          startTime: _moveSlot!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _fail();
    }
  }

  /// « Reporter à demain » : demande d'abord LA RAISON (fait tracké, cité par
  /// le check-in et la proposition du lendemain), puis sauté + cause
  /// « reporte » → demain il passe EN PREMIER (règle serveur), refusable.
  Future<void> _actReportTomorrow() async {
    if (_saving) return;
    final reason = await _askReportReason();
    if (reason == null) return; // annulé — rien n'est écrit
    if (!mounted) return;
    // La disponibilité devient un fait : « pas dispo avant X » → le coach
    // suit le flow (pas de relance ni de dérive avant l'heure dite).
    final availability = await showAvailabilitySheet(context);
    setState(() => _saving = true);
    try {
      await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
      await _sync.updateBlockSkipReason(widget.date, b.id, 'reporte',
          reportReason: reason.isEmpty ? null : reason);
      if (availability != null && availability != kAvailableNow) {
        await _sync.setUnavailability(widget.date, availability,
            reason: reason.isEmpty ? null : reason);
      }
      if (mounted) {
        Navigator.pop(context);
        if (availability != null && availability != kAvailableNow) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Noté — je te relance ${_untilFr(availability)}. D\'ici là, je suis le flow.'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      _fail();
    }
  }

  String _untilFr(DateTime d) {
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final hm = d.minute == 0
        ? '${d.hour} h'
        : '${d.hour} h ${d.minute.toString().padLeft(2, '0')}';
    return sameDay ? 'à $hm' : 'demain';
  }

  /// Chips de raison + texte libre — la raison du report est un fait, pas un
  /// souvenir (« aujourd'hui je ne peux pas : je ne suis pas chez moi »).
  Future<String?> _askReportReason() async {
    const reasons = <(String, String)>[
      ('pas_sur_place', 'Pas sur place / pas le matériel'),
      ('imprevu', 'Imprévu'),
      ('energie', 'Pas d\'énergie'),
      ('pas_le_moment', 'Pas le bon moment'),
    ];
    final ctrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(sctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pourquoi le report ?',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Une raison honnête suffit — elle nourrit le coach, jamais la culpabilité.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(sctx).colorScheme.onSurface.withOpacity(.55)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in reasons)
                  ActionChip(
                    label: Text(r.$2, style: const TextStyle(fontSize: 12.5)),
                    onPressed: () => Navigator.pop(sctx, r.$1),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.pop(sctx, v.trim()),
              decoration: const InputDecoration(
                hintText: 'Autre raison…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(sctx, ctrl.text.trim()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text('Reporter à demain'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  /// « Supprimer le bloc » : il n'aurait pas dû être posé — soft-delete
  /// (jamais retiré du tableau), compté par les stats d'hygiène du rapport.
  Future<void> _actDelete() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _sync.updateBlockStatus(widget.date, b.id, 'deleted');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Bloc supprimé — il n\'aurait pas dû être posé. Le rapport hebdo le compte.')));
      }
    } catch (_) {
      _fail();
    }
  }

  /// « Déplacer dans la journée… » → sélecteur des créneaux libres réels (23a).
  Future<void> _actMoveInDay() async {
    final moved = await showMoveBlockSheet(context,
        logic: widget.logic, block: b, date: widget.date);
    if (moved && mounted) Navigator.pop(context);
  }

  /// « Terminer l'après-midi » (23c) : bascule TOUT le système en mode soirée
  /// — les blocs ne sont pas touchés, réversible à tout moment.
  Future<void> _actEndAfternoon() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _sync.setDayMode(widget.date, 'evening');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Mode soirée activé'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () => _sync.setDayMode(widget.date, 'normal'),
          ),
        ));
      }
    } catch (_) {
      _fail();
    }
  }

  /// « Abandonner pour aujourd'hui » — compte comme sauté (le check-in du soir
  /// demandera le pourquoi), aucune pénalité cachée.
  Future<void> _abandon() async {
    await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
    if (mounted) Navigator.pop(context);
  }

  void _fail() {
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Échec réseau — rien n\'a changé, réessaie.')));
    }
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
    final now = DateTime.now();
    // La bascule système n'a de sens qu'avant la soirée, avec du restant.
    final waiting = widget.logic.todayBlocks
        .where((x) =>
            x.status == 'pending' &&
            !x.isPrep &&
            x.category != 'break' &&
            x.id != b.id)
        .length;
    final showDayWide = now.hour < 19;
    final moveEvening =
        _moveSlot != null && _moveSlot!.compareTo('18:00') >= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${b.title} — ${_hFr(b.startTime)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Ces actions ne concernent que ce bloc :',
          style: TextStyle(
              fontSize: 12.5, color: cs.onSurface.withOpacity(.6)),
        ),
        const SizedBox(height: 12),
        if (_moveSlot != null)
          _actionRow(
            cs,
            'Reporter « ${b.title} » → ${moveEvening ? 'ce soir ' : ''}${_hFr(_moveSlot!)}',
            'juste ce bloc — le reste de la journée ne bouge pas',
            _actMoveToSlot,
            highlight: true,
          ),
        _actionRow(
          cs,
          'Réduire à 25 min — maintenant',
          'chrono lancé au tap · l\'essentiel vaut mieux que 0',
          _actReduce,
        ),
        _actionRow(
          cs,
          'Reporter à demain…',
          _reportCount > 1
              ? '$_reportCountᵉ report cette semaine — dis pourquoi, demain il passe en premier'
              : 'dis pourquoi (10 s) — demain il passe en premier, avant tout',
          _actReportTomorrow,
          amber: _reportCount > 1,
        ),
        _actionRow(
          cs,
          'Déplacer dans la journée…',
          'choisir un créneau libre réel',
          _actMoveInDay,
        ),
        if (showDayWide) ...[
          const SizedBox(height: 6),
          // ── Bascule système : isolée, nommée, conséquence écrite (23b) ──────
          Center(
            child: Text('TOUTE LA JOURNÉE',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: cs.tertiary)),
          ),
          const SizedBox(height: 8),
          _actionRow(
            cs,
            'Terminer l\'après-midi — passer l\'app en mode soirée',
            waiting > 0
                ? '${waiting > 1 ? 'les $waiting blocs restants seront' : 'le bloc restant sera'} à replanifier · réversible à tout moment'
                : 'réversible à tout moment',
            _actEndAfternoon,
            amber: true,
          ),
        ],
        const SizedBox(height: 4),
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
        Center(
          child: TextButton(
            onPressed: _saving ? null : _actDelete,
            child: Text(
              'Supprimer le bloc (n\'aurait pas dû être posé)',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withOpacity(.7))),
          ),
        ),
      ],
    );
  }

  /// Rangée d'action 23b : le verbe porte l'objet, la conséquence est écrite,
  /// le tap exécute — pas de validation intermédiaire.
  Widget _actionRow(
      ColorScheme cs, String title, String consequence, VoidCallback onTap,
      {bool amber = false, bool highlight = false}) {
    final accent = amber ? cs.tertiary : cs.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _saving ? null : onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight || amber
                ? accent.withOpacity(.55)
                : cs.onSurface.withOpacity(.15),
          ),
          color: highlight ? accent.withOpacity(.05) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: amber ? cs.tertiary : cs.onSurface)),
            const SizedBox(height: 2),
            Text(consequence,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: amber
                        ? cs.tertiary.withOpacity(.85)
                        : cs.onSurface.withOpacity(.55))),
          ],
        ),
      ),
    );
  }

  Widget _structuralView(StructuralDiagnosis d) {
    final cs = Theme.of(context).colorScheme;
    final domain = _domain();
    final alt = d.alternatives.isNotEmpty ? d.alternatives.first : null;
    final keepChosen = _options[_chosenOpt].keep;
    // L'intention citée est celle de la ROUTINE (méta-intention du catalogue)
    // quand elle existe — celle du domaine (« manger équilibré ») n'a rien à
    // faire sur une routine d'hygiène (constaté sur build).
    final act0 = _routine();
    final intention =
        (act0 != null ? metaIntentionOf(act0) : null) ?? domain?.intention;

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
            if (intention != null)
              TextSpan(
                  text: ' — « $intention »',
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
