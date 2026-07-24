import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';

/// Écran de planification (maquettes 6a / 8a) : une proposition PRÉ-REMPLIE —
/// jamais de page vide — à ajuster puis valider. Deux entrées :
///  · check-in du soir « Poser demain » → cible J+1 ;
///  · carte « journée non planifiée » du matin → cible aujourd'hui, mode
///    « RATTRAPAGE EXPRESS » (horizon = le reste de la journée).
/// La proposition vient d'un appel Haiku unique (proposeDayPlan) ; en cas
/// d'échec réseau, fallback déterministe local. Aucune écriture avant
/// « Valider » (validation optimiste, via les écritures existantes).
/// Retourne (Navigator.pop) le nombre de blocs posés, ou null si abandon.
class PlanDayScreen extends StatefulWidget {
  final AppLogic logic;
  final String targetDate; // YYYY-MM-DD
  final bool rattrapage; // mode 8a : cible = aujourd'hui, arbitrage temps réel
  // « ▶ Je pars » : lancer le chrono ciblé du bloc juste après validation.
  final void Function(ScheduleBlock block)? onLaunchBlock;

  /// true = ignorer le brouillon caché et régénérer (ex : 🗑 « reprogrammer
  /// la journée » — les contraintes viennent de changer, le cache ment).
  final bool forceRegenerate;

  const PlanDayScreen({
    super.key,
    required this.logic,
    required this.targetDate,
    this.rattrapage = false,
    this.onLaunchBlock,
    this.forceRegenerate = false,
  });

  @override
  State<PlanDayScreen> createState() => _PlanDayScreenState();
}

/// Un bloc proposé + ses métadonnées d'affichage (jamais persistées).
class _Draft {
  final ScheduleBlock block;
  final String? subtitle; // provenance courte (« plan de reprise S2 »)
  final bool reproposed; // a sauté la veille — bordure pointillée ambre
  final bool auto; // prep auto — non supprimable par swipe
  _Draft(this.block, {this.subtitle, this.reproposed = false, this.auto = false});
}

class _PlanDayScreenState extends State<PlanDayScreen> {
  final _sync = FirestoreSync();
  static const String _kProposeUrl =
      'https://proposedayplan-dzos75b65q-uc.a.run.app';

  bool _loading = true;
  bool _saving = false;
  String _message = '';
  List<Map<String, dynamic>> _sources = const [];
  final List<_Draft> _draft = [];
  // Prep « ce soir 21:45 » liée à un bloc matinal de la cible (target = J+1).
  _Draft? _eveningPrep;
  // Blocs déjà posés sur la cible (contraintes) — affichés « déjà en place ».
  List<ScheduleBlock> _existing = [];
  // Arbitrage rattrapage : bloc du créneau entamé + choix.
  _Draft? _arbitration;
  bool _launchOnValidate = false;
  int _sameDayPlanCount = 0; // plannedSameDay des 7 derniers jours

  AppLogic get logic => widget.logic;

  String get _todayYmd => _ymd(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load(force: widget.forceRegenerate);
  }

  // ── Chargement de la proposition ─────────────────────────────────────────────

  Future<void> _load({bool force = false}) async {
    // Récurrence « planifié au réveil » (fait rejoué, jamais culpabilisant).
    if (widget.rattrapage) {
      _countSameDayPlans();
    }
    // Heure de lever PRÉVUE : demandée à chaque vraie génération (les jours
    // ne se ressemblent pas — flexibilité), dernière valeur = présélection.
    // Rouvrir un brouillon encore valide ne repose PAS la question.
    // EXCEPTION (retour user) : planifier le JOUR MÊME l'après-midi — la
    // question du lever n'a aucun sens, le plancher c'est « maintenant ».
    final isSameDayPm =
        widget.targetDate == _todayYmd && DateTime.now().hour >= 10;
    final storedWake = await _sync.fetchWakeTime();
    final srcFp = await _sourceFingerprint();
    // ── Cache : l'ouverture répétée de l'écran coûte 0 appel LLM ─────────────
    // Le brouillon persiste sur le doc de la date cible et reste valable < 6 h
    // si le programme source (la veille) n'a pas changé. ⟳ = régénérer.
    if (!force) {
      final cachedFp = isSameDayPm
          ? '$srcFp|sameday'
          : '$srcFp|lever:${storedWake ?? '07:00'}';
      try {
        final cached = await _sync.fetchProposalDraft(widget.targetDate);
        final genAt = cached?['generatedAt'] is String
            ? DateTime.tryParse(cached!['generatedAt'] as String)
            : null;
        if (cached != null &&
            genAt != null &&
            DateTime.now().difference(genAt).inHours < 6 &&
            cached['fingerprint'] == cachedFp &&
            cached['body'] is Map) {
          _applyProposal(Map<String, dynamic>.from(cached['body'] as Map));
          if (_draft.isNotEmpty) {
            await _filterAgainstExisting();
            _postProcess();
            if (mounted) setState(() => _loading = false);
            return; // brouillon réutilisé — zéro appel réseau LLM
          }
        }
      } catch (_) {}
    }
    // Étape « TES BLOCS D'ABORD » (retour user) : ce que le user veut caler
    // lui-même (rendez-vous oublié de l'agenda, contrainte perso) — posé en
    // vrais blocs AVANT la génération, ORION remplit autour (occupiedBlocks).
    await _askUserBlocks();
    final now = DateTime.now();
    final wake = isSameDayPm
        ? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
        : await _ensureWakeTime(storedWake);
    final fingerprint =
        isSameDayPm ? '$srcFp|sameday' : '$srcFp|lever:$wake';
    try {
      final token = await _sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = _sync.uid;
      if (raw == null || raw.isEmpty || uid == null) {
        throw Exception('token indisponible');
      }
      final resp = await http
          .post(
            Uri.parse(_kProposeUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $raw',
            },
            body: jsonEncode(
                {'uid': uid, 'date': widget.targetDate, 'wakeTime': wake}),
          )
          .timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      _applyProposal(body);
      // Persister le brouillon (les fallbacks locaux, gratuits, ne sont pas
      // cachés — seule la proposition LLM l'est).
      if (_draft.isNotEmpty) {
        unawaited(_sync.saveProposalDraft(widget.targetDate, {
          'generatedAt': DateTime.now().toIso8601String(),
          'fingerprint': fingerprint,
          'body': body,
        }));
      }
    } catch (_) {
      // Fallback déterministe — l'écran ne doit jamais être vide ni bloquer.
      await _buildFallback();
    }
    await _filterAgainstExisting();
    _postProcess();
    if (mounted) setState(() => _loading = false);
  }

  /// Heure de lever PRÉVUE pour la journée cible : demandée à chaque
  /// génération (chaque jour est différent), [last] = dernière valeur
  /// utilisée, mise en avant. Fermeture du sheet → on garde la dernière
  /// (sinon 07:00), rien n'est écrit.
  Future<String> _ensureWakeTime(String? last) async {
    if (!mounted) return last ?? '07:00';
    final picked = await _askWakeTime(last);
    if (picked != null) {
      await _sync.setWakeTime(picked);
      return picked;
    }
    return last ?? '07:00';
  }

  Future<String?> _askWakeTime(String? last) {
    const options = ['05:30', '06:00', '06:30', '07:00', '07:30', '08:00', '09:00'];
    String fr(String hm) =>
        hm.replaceFirst(':', ' h ').replaceFirst(' h 00', ' h');
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('À quelle heure comptes-tu te lever ?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Chaque jour est différent — rien ne sera posé avant ton lever.',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // La dernière valeur d'abord, mise en avant — un tap et
                  // c'est reparti comme la veille.
                  if (last != null)
                    ActionChip(
                      avatar: Icon(Icons.history_rounded,
                          size: 16, color: cs.primary),
                      label: Text('${fr(last)} · comme la dernière fois'),
                      labelStyle: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: cs.primary),
                      side: BorderSide(color: cs.primary.withOpacity(.6)),
                      onPressed: () => Navigator.pop(ctx, last),
                    ),
                  for (final o in options)
                    if (o != last)
                      ActionChip(
                        label: Text(fr(o)),
                        labelStyle: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                        onPressed: () => Navigator.pop(ctx, o),
                      ),
                  ActionChip(
                    label: const Text('Autre…'),
                    onPressed: () async {
                      final p = (last ?? '07:00').split(':');
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(
                              hour: int.tryParse(p.first) ?? 7,
                              minute: int.tryParse(p.last) ?? 0));
                      if (t != null && ctx.mounted) {
                        Navigator.pop(
                            ctx,
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// « Tes blocs d'abord » : avant de générer, le user pose ce qu'IL veut
  /// caler (rendez-vous oublié de l'agenda, contrainte perso). Chaque ajout
  /// est écrit en VRAI bloc sur la date cible → contrainte dure que la
  /// proposition contourne (occupiedBlocks) et affiche « déjà en place ».
  /// Chaînable ; « Passer » / « C'est tout » → la génération continue.
  Future<void> _askUserBlocks() async {
    if (!mounted) return;
    final titleCtrl = TextEditingController();
    final isToday = widget.targetDate == _todayYmd;
    final now = DateTime.now();
    var time = isToday
        ? TimeOfDay(hour: (now.hour + 1).clamp(0, 23), minute: 0)
        : const TimeOfDay(hour: 9, minute: 0);
    var duration = 60;
    final added = <ScheduleBlock>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;
          String hhmm() =>
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          void add() {
            final t = titleCtrl.text.trim();
            if (t.isEmpty) return;
            final b = ScheduleBlock(
              startTime: hhmm(),
              durationMin: duration,
              title: t,
              category: 'personal',
            );
            // Écrit tout de suite (optimiste) : le bloc devient une
            // contrainte réelle même si la génération est annulée.
            unawaited(_sync.addScheduleBlock(widget.targetDate, b));
            setLocal(() {
              added.add(b);
              titleCtrl.clear();
            });
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Des blocs à poser toi-même ?',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Ce que tu veux caler à heure fixe (rendez-vous oublié, '
                  'contrainte perso…) — ORION remplira AUTOUR, sans y toucher.',
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
                ),
                const SizedBox(height: 12),
                for (final b in added)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E9E6B).withOpacity(.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF2E9E6B).withOpacity(.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.lock_outline,
                          size: 14, color: Color(0xFF2E9E6B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            '${b.startTime} · ${b.title} — ${b.durationMin} min',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          unawaited(_sync.updateBlockStatus(
                              widget.targetDate, b.id, 'deleted'));
                          setLocal(() => added.remove(b));
                        },
                      ),
                    ]),
                  ),
                TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Ex : Rendez-vous garage',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => add(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.schedule_rounded,
                      size: 16, color: cs.onSurface.withOpacity(.55)),
                  const SizedBox(width: 6),
                  Text('À ${hhmm()}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: time);
                      if (t != null) setLocal(() => time = t);
                    },
                    child: const Text('Modifier'),
                  ),
                ]),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final d in const [30, 60, 90])
                    ChoiceChip(
                      selected: duration == d,
                      onSelected: (_) => setLocal(() => duration = d),
                      showCheckmark: false,
                      label: Text('$d min'),
                      visualDensity: VisualDensity.compact,
                    ),
                  // Durée LIBRE (demande user : pas seulement 3 presets) —
                  // même roue que partout ailleurs (pickDurationMin).
                  ChoiceChip(
                    selected: !const [30, 60, 90].contains(duration),
                    onSelected: (_) async {
                      final v = await pickDurationMin(ctx,
                          initial: duration, title: 'Durée du bloc');
                      if (v != null && v > 0) {
                        setLocal(() => duration = v);
                      }
                    },
                    showCheckmark: false,
                    label: Text(const [30, 60, 90].contains(duration)
                        ? 'Autre…'
                        : fmtMin(duration)),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: add,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ajouter ce bloc'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(added.isEmpty
                        ? 'Passer — ORION planifie tout'
                        : 'C\'est tout — planifie le reste'),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
    titleCtrl.dispose();
  }

  /// Empreinte du programme source (la veille de la cible) : si les statuts,
  /// causes ou blocs changent, le brouillon caché est invalide.
  Future<String> _sourceFingerprint() async {
    final ref = _ymd(
        DateTime.parse(widget.targetDate).subtract(const Duration(days: 1)));
    try {
      final s = await _sync.fetchDailySchedule(ref);
      final live =
          (s?.blocks ?? const <ScheduleBlock>[]).where((b) => b.status != 'deleted');
      return [
        s?.dayReason ?? '',
        ...live.map((b) => '${b.id}:${b.status}:${b.skipReason ?? ''}'),
      ].join('|');
    } catch (_) {
      return 'na';
    }
  }

  /// ⟳ explicite : régénère la proposition (1 appel), remplace le brouillon.
  Future<void> _regenerate() async {
    setState(() {
      _loading = true;
      _draft.clear();
      _arbitration = null;
      _eveningPrep = null;
      _sources = const [];
      _message = '';
      _launchOnValidate = false;
    });
    await _load(force: true);
  }

  void _applyProposal(Map<String, dynamic> body) {
    _message = (body['message'] as String?) ?? '';
    _sources = ((body['sources'] as List?) ?? const [])
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    for (final raw in (body['blocks'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final b = Map<String, dynamic>.from(raw);
      _draft.add(_Draft(
        ScheduleBlock(
          startTime: b['startTime'] ?? '09:00',
          durationMin: (b['durationMin'] as num?)?.toInt() ?? 30,
          title: b['title'] ?? '',
          category: b['category'] ?? 'personal',
          activityId: b['activityId'],
          projectId: b['projectId'],
          taskId: b['taskId'],
        ),
        subtitle: b['subtitle'] as String?,
        reproposed: b['reproposed'] == true,
      ));
    }
    if (_draft.isEmpty) {
      // Proposition vide = échec déguisé → même filet que l'offline.
      unawaited(_buildFallback());
    }
  }

  /// Squelette local : blocs de la veille (routines reprises à leurs heures,
  /// sautés reproposés) — zéro réseau au-delà de Firestore (cache local inclus).
  Future<void> _buildFallback() async {
    _message =
        'Proposition locale : la veille reconduite, les blocs sautés repêchés. '
        'Ajuste ce qui coince, valide le reste.';
    try {
      final ref = _ymd(DateTime.parse(widget.targetDate)
          .subtract(const Duration(days: 1)));
      final refSched = await _sync.fetchDailySchedule(ref);
      for (final b in refSched?.blocks ?? const <ScheduleBlock>[]) {
        if (b.status == 'deleted' || b.isPrep) continue;
        // « reporte » = déjà copié dans le programme du jour cible au moment
        // du report effectif — ne pas le reproposer une seconde fois.
        if (b.skipReason == 'reporte') continue;
        final skipped = b.status != 'done';
        _draft.add(_Draft(
          ScheduleBlock(
            startTime: b.startTime,
            durationMin: b.durationMin,
            title: b.title,
            category: b.category,
            activityId: b.activityId,
            projectId: b.projectId,
            taskId: b.taskId,
            actionId: b.actionId,
          ),
          subtitle: skipped ? null : 'reconduit d\'hier',
          reproposed: skipped,
        ));
      }
    } catch (_) {}
    if (_draft.isEmpty) {
      final next = _nextQuarterHour();
      _draft.add(_Draft(
        ScheduleBlock(
            startTime: next, durationMin: 45, title: 'Bloc focus', category: 'personal'),
        subtitle: 'pour démarrer — édite librement',
      ));
    }
  }

  /// Blocs déjà posés sur la cible (manuels, reportés, agenda, défis…) :
  /// la proposition ne fait que REMPLIR LES TROUS. On retire du brouillon
  /// tout doublon de titre ou chevauchement horaire avec un bloc actif
  /// existant — le serveur filtre déjà, ceci couvre le fallback local et
  /// les brouillons cachés générés avant le durcissement.
  Future<void> _filterAgainstExisting() async {
    try {
      final existing = await _sync.fetchDailySchedule(widget.targetDate);
      final active = (existing?.blocks ?? const <ScheduleBlock>[])
          .where((b) => b.status == 'pending' || b.status == 'done')
          .toList();
      // Affichés dans la liste comme « déjà en place » (intouchables).
      _existing = active..sort((a, b) => a.startTime.compareTo(b.startTime));
      if (active.isEmpty) return;
      _draft.removeWhere((d) => _conflictsWithExisting(d.block, active));
      if (_arbitration != null &&
          _conflictsWithExisting(_arbitration!.block, active)) {
        _arbitration = null;
      }
    } catch (_) {}
  }

  static String _normTitle(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  static int _minOf(String hm) =>
      (int.tryParse(hm.substring(0, 2)) ?? 0) * 60 +
      (int.tryParse(hm.substring(3, 5)) ?? 0);

  bool _conflictsWithExisting(ScheduleBlock b, List<ScheduleBlock> active) {
    final bs = _minOf(b.startTime), be = bs + b.durationMin;
    final bt = _normTitle(b.title);
    for (final e in active) {
      if (bt.isNotEmpty && _normTitle(e.title) == bt) return true;
      final es = _minOf(e.startTime), ee = es + e.durationMin;
      if (bs < ee && be > es) return true;
    }
    return false;
  }

  /// Règles communes post-proposition : tri, horizon rattrapage, arbitrage,
  /// bloc check-in du soir, prep auto.
  void _postProcess() {
    final now = DateTime.now();
    final nowHm = _hm(now);

    if (widget.rattrapage) {
      // Horizon = le reste de la journée. Le créneau entamé/imminent passe en
      // carte d'arbitrage (« ▶ Je pars » / « Glisser à 18 h »).
      _draft.removeWhere((d) {
        final end = _addMin(d.block.startTime, d.block.durationMin);
        return end.compareTo(nowHm) <= 0; // bloc entièrement passé
      });
      final imminentIdx = _draft.indexWhere((d) =>
          d.block.startTime.compareTo(_addMin(nowHm, 30)) < 0 &&
          !d.block.isPrep);
      if (imminentIdx >= 0) {
        _arbitration = _draft.removeAt(imminentIdx);
      }
      // Ramener au flux nominal du soir : check-in + poser demain.
      final tomorrowName = _dayName(
          DateTime.parse(widget.targetDate).add(const Duration(days: 1)));
      if (!_draft.any((d) => d.block.title.startsWith('Check-in'))) {
        _draft.add(_Draft(
          ScheduleBlock(
              startTime: '21:30',
              durationMin: 15,
              title: 'Check-in + poser $tomorrowName',
              category: 'personal'),
          subtitle: 'ce soir on reprend l\'avance',
        ));
      }
    }

    _draft.sort((a, b) => a.block.startTime.compareTo(b.block.startTime));
    _refreshEveningPrep();
  }

  /// Prep auto : si la cible est DEMAIN et que la proposition contient un bloc
  /// matinal (<9h30) qui exige du matériel, une prep de 5 min est posée CE SOIR
  /// 21:45 (liée via prepForDate + prepForBlockId) à la validation.
  void _refreshEveningPrep() {
    _eveningPrep = null;
    final tomorrow = _ymd(DateTime.now().add(const Duration(days: 1)));
    if (widget.targetDate != tomorrow) return;
    for (final d in _draft) {
      final b = d.block;
      if (b.isPrep || b.startTime.compareTo('09:30') >= 0) continue;
      if (!_needsPrep(b)) continue;
      _eveningPrep = _Draft(
        ScheduleBlock(
          startTime: '21:45',
          durationMin: 5,
          title: 'Préparer les affaires',
          category: 'personal',
          kind: 'prep',
          prepForDate: widget.targetDate,
          prepForBlockId: b.id,
        ),
        subtitle: 'ajouté auto — lié à « ${b.title} »',
        auto: true,
      );
      break;
    }
  }

  bool _needsPrep(ScheduleBlock b) =>
      b.category == 'personal' ||
      b.category == 'routine' ||
      RegExp(r's[eé]ance|sport|muscu|course|footing|run|piscine|natation|d[eé]placement|train|avion|cuisine|repas',
              caseSensitive: false)
          .hasMatch(b.title);

  Future<void> _countSameDayPlans() async {
    var count = 0;
    for (var i = 1; i <= 7; i++) {
      final d = _ymd(DateTime.now().subtract(Duration(days: i)));
      try {
        final s = await _sync.fetchDailySchedule(d);
        if (s?.plannedSameDay == true) count++;
      } catch (_) {}
    }
    if (mounted) setState(() => _sameDayPlanCount = count);
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  Future<void> _validate() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    try {
      final existing = await _sync.fetchDailySchedule(widget.targetDate);
      // La proposition est ADDITIVE : TOUT ce qui est déjà posé sur la cible
      // est conservé tel quel (blocs manuels, reportés, agenda, défis, prep,
      // done, deleted…) — elle ne fait que remplir les trous. Garde-fou
      // déterministe au moment de l'écriture : tout bloc proposé qui double
      // (titre) ou chevauche (plage) un bloc actif existant est écarté.
      final kept = (existing?.blocks ?? const <ScheduleBlock>[]).toList();
      final active = kept
          .where((b) => b.status == 'pending' || b.status == 'done')
          .toList();
      final incoming = <ScheduleBlock>[
        if (_arbitration != null) _arbitration!.block,
        ..._draft.map((d) => d.block),
      ].where((b) => !_conflictsWithExisting(b, active)).toList();
      final blocks = <ScheduleBlock>[...kept, ...incoming];
      final sameDay = widget.targetDate == _todayYmd && now.hour >= 5;
      await _sync.saveDailySchedule(DailySchedule(
        date: widget.targetDate,
        generatedBy: 'orion',
        blocks: blocks,
        dayReason: existing?.dayReason,
        plannedAt: sameDay ? now : existing?.plannedAt,
        plannedSameDay: sameDay ? true : (existing?.plannedSameDay ?? false),
        // Replanifier sort du mode soirée ET de l'indisponibilité déclarée :
        // poser un programme, c'est se déclarer dispo.
        dayMode: 'normal',
        // L'état déclaré (24a) et la séquence de remontée (25) sont des
        // FAITS — replanifier ne les efface pas.
        energyState: existing?.energyState,
        recoverySequence: existing?.recoverySequence,
      ));
      // Prep du soir (cible = demain) : ajoutée au programme d'AUJOURD'HUI
      // sans le remplacer (même sémantique qu'add_prep_block, idempotent).
      if (_eveningPrep != null) {
        final today = await _sync.fetchDailySchedule(_todayYmd);
        final already = (today?.blocks ?? const <ScheduleBlock>[]).any((b) =>
            b.isPrep &&
            b.status != 'deleted' &&
            b.prepForDate == widget.targetDate);
        if (!already) {
          await _sync.addScheduleBlock(_todayYmd, _eveningPrep!.block);
        }
      }
      if (_launchOnValidate && _arbitration != null) {
        widget.onLaunchBlock?.call(_arbitration!.block);
      }
      if (mounted) {
        Navigator.pop(
            context, blocks.where((b) => b.status != 'deleted').length);
      }
    } catch (_) {
      // Validation optimiste : en cas d'échec, l'écran reste intact.
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a été écrit, réessaie.')));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = DateTime.parse(widget.targetDate);
    final isToday = widget.targetDate == _todayYmd;
    final title =
        '${isToday ? 'Aujourd\'hui' : 'Demain'} — ${_dayName(target)} ${target.day} ${_monthName(target)}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
              widget.rattrapage
                  ? 'ORION · RATTRAPAGE EXPRESS'
                  : 'ORION · PROPOSITION',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.primary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Régénérer la proposition',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading || _saving ? null : _regenerate,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              child: _buildProposal(cs),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _validate,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  child: Text(_saving
                      ? 'Enregistrement…'
                      : widget.rattrapage
                          ? 'Valider la journée — +${_totalBlocks()} blocs'
                          : 'Valider — +${_totalBlocks()} blocs'),
                ),
              ),
            ),
    );
  }

  int _totalBlocks() => _draft.length + (_arbitration != null ? 1 : 0);

  /// Liste fusionnée chronologique : brouillons (refusables) + blocs déjà en
  /// place (hero vert, conservés tels quels à la validation).
  List<Widget> _mergedRows(ColorScheme cs) {
    final entries = <({String start, Widget w})>[
      for (final d in _draft)
        (start: d.block.startTime, w: _draftRow(cs, d)),
      for (final b in _existing)
        (start: b.startTime, w: _existingRow(cs, b)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return entries.map((e) => e.w).toList();
  }

  /// Bloc déjà posé sur la cible (manuel, reporté, agenda, défi…) : contrainte
  /// respectée par la proposition — affiché en « hero » vert, non refusable.
  Widget _existingRow(ColorScheme cs, ScheduleBlock b) {
    const green = Color(0xFF2E9E6B);
    final isDone = b.status == 'done';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: green.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: green.withOpacity(.45), width: 1.4),
      ),
      child: Row(
        children: [
          Text(b.startTime,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: green)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      decoration:
                          isDone ? TextDecoration.lineThrough : null,
                    )),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(
                      b.gcalEventId != null
                          ? Icons.event_available
                          : Icons.verified_rounded,
                      size: 13,
                      color: green),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${fmtMin(b.durationMin)} · '
                      '${b.gcalEventId != null ? 'agenda — déjà en place' : isDone ? 'déjà fait' : 'déjà validé — conservé'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: green),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          Icon(Icons.lock_outline_rounded,
              size: 16, color: green.withOpacity(.7)),
        ],
      ),
    );
  }

  Widget _buildProposal(ColorScheme cs) {
    return ListView(
      key: const ValueKey('proposal'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // ── Carte message : pourquoi cette proposition ──────────────────────
        if (_message.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withOpacity(.3)),
            ),
            child: Text(_message,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: cs.onSurface.withOpacity(.9))),
          ),
        // ── Chips de provenance ─────────────────────────────────────────────
        if (_sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _sources)
                  Chip(
                    avatar: Icon(Icons.description_outlined,
                        size: 14, color: cs.primary),
                    label: Text(s['title']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        // ── Arbitrage temps réel (rattrapage, maquette 8a) ──────────────────
        if (_arbitration != null) _arbitrationCard(cs),
        if (widget.rattrapage)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text('LE RESTE DE LA JOURNÉE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.onSurface.withOpacity(.4))),
          ),
        // ── Blocs proposés ──────────────────────────────────────────────────
        // Tout est refusable : le refus est silencieux et sans pénalité.
        if (_draft.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Glisse un bloc pour le retirer — tout est refusable, sans pénalité.',
                style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withOpacity(.4))),
          ),
        // Fusion chronologique : blocs proposés + blocs DÉJÀ EN PLACE
        // (contraintes intouchables — cartes hero vertes, non refusables).
        ..._mergedRows(cs),
        if (_eveningPrep != null) _draftRow(cs, _eveningPrep!, discreet: true),
        // ── + Ajouter un bloc ───────────────────────────────────────────────
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _addBlock,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: cs.onSurface.withOpacity(.25),
                  style: BorderStyle.solid),
            ),
            child: Center(
              child: Text('+ Ajouter un bloc',
                  style: TextStyle(
                      fontSize: 13.5, color: cs.onSurface.withOpacity(.6))),
            ),
          ),
        ),
        // ── Récurrence « planifié au réveil » (fait, pas de culpabilité) ────
        if (widget.rattrapage && _sameDayPlanCount >= 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: cs.tertiary.withOpacity(.8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_sameDayPlanCount + 1}ᵉ matin planifié au réveil cette semaine — noté, on en reparle au check-in.',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(.55)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _arbitrationCard(ColorScheme cs) {
    final b = _arbitration!.block;
    final now = DateTime.now();
    final start = _parseHm(b.startTime, now);
    final leaveIn = start.difference(now).inMinutes;
    final nowLabel = _hm(now.add(Duration(minutes: leaveIn > 0 ? leaveIn : 15)));
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Planifié au réveil — ça arrive. Il est ${_hm(now)} : « ${b.title} » tient encore si tu pars vite. Sinon elle glisse à 18 h.',
            style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: cs.onSurface.withOpacity(.9)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text('Je pars — $nowLabel'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: () => setState(() {
                    _arbitration!.block.startTime = nowLabel;
                    _launchOnValidate = true;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: () => setState(() {
                    _arbitration!.block.startTime = '18:00';
                    _launchOnValidate = false;
                    _draft.add(_arbitration!);
                    _arbitration = null;
                    _draft.sort(
                        (a, b) => a.block.startTime.compareTo(b.block.startTime));
                  }),
                  child: const Text('Glisser à 18 h'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _draftRow(ColorScheme cs, _Draft d, {bool discreet = false}) {
    final b = d.block;
    final border = d.reproposed
        ? Border.all(color: cs.tertiary.withOpacity(.7))
        : Border.all(color: cs.onSurface.withOpacity(.12));
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: discreet
            ? Colors.transparent
            : cs.surfaceContainerHighest.withOpacity(.25),
        borderRadius: BorderRadius.circular(12),
        border: discreet ? null : border,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              b.startTime,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: discreet
                    ? cs.onSurface.withOpacity(.4)
                    : cs.primary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discreet ? '🎒 ${b.title}' : b.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: discreet
                        ? cs.onSurface.withOpacity(.55)
                        : cs.onSurface,
                  ),
                ),
                if (d.reproposed)
                  Text('a sauté — reproposé',
                      style: TextStyle(
                          fontSize: 11, color: cs.tertiary.withOpacity(.9)))
                else if (d.subtitle != null || !discreet)
                  Text(
                    [
                      fmtMin(b.durationMin),
                      if (d.subtitle != null) d.subtitle!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface.withOpacity(.45)),
                  )
                else if (d.subtitle != null)
                  Text(d.subtitle!,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurface.withOpacity(.45))),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.swap_vert_rounded,
                size: 18, color: cs.onSurface.withOpacity(.4)),
            tooltip: 'Changer l\'heure',
            onPressed: () => _pickTime(d),
          ),
          // Bloc reproposé : le refus doit être VISIBLE (pas seulement le
          // swipe) — ✕ en un tap, silencieux, sans pénalité.
          if (d.reproposed)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: cs.tertiary.withOpacity(.9)),
              tooltip: 'Refuser ce bloc',
              onPressed: () => setState(() {
                _draft.remove(d);
                _refreshEveningPrep();
              }),
            ),
        ],
      ),
    );

    // Prep auto : pas de swipe (elle vient de la règle), mais éditable.
    if (d.auto) {
      return GestureDetector(onTap: () => _editBlock(d), child: row);
    }
    return Dismissible(
      key: ValueKey(b.id),
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
      onDismissed: (_) => setState(() {
        _draft.remove(d);
        _refreshEveningPrep();
      }),
      child: GestureDetector(onTap: () => _editBlock(d), child: row),
    );
  }

  // ── Édition d'un bloc proposé (en mémoire uniquement) ───────────────────────

  Future<void> _pickTime(_Draft d) async {
    final parts = d.block.startTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
      ),
    );
    if (picked == null) return;
    setState(() {
      // Snap sur 15 min — pas de grille libre.
      final snapped = (picked.minute / 15).round() * 15 % 60;
      final hour = picked.minute >= 53 ? (picked.hour + 1) % 24 : picked.hour;
      d.block.startTime =
          '${hour.toString().padLeft(2, '0')}:${snapped.toString().padLeft(2, '0')}';
      _draft.sort((a, b) => a.block.startTime.compareTo(b.block.startTime));
    });
  }

  Future<void> _editBlock(_Draft d) async {
    final titleCtrl = TextEditingController(text: d.block.title);
    var duration = d.block.durationMin;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Titre',
                    border: OutlineInputBorder(),
                    isDense: true),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final v = await pickDurationMin(ctx,
                      initial: duration, title: 'Durée');
                  if (v != null && v > 0) setSheet(() => duration = v);
                },
                child: Text('Durée : ${fmtMin(duration)}'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
    setState(() {
      final t = titleCtrl.text.trim();
      if (t.isNotEmpty) d.block.title = t;
      d.block.durationMin = duration;
    });
    titleCtrl.dispose();
  }

  void _addBlock() {
    final draft = _Draft(
      ScheduleBlock(
          startTime: _nextQuarterHour(),
          durationMin: 30,
          title: 'Nouveau bloc',
          category: 'personal'),
    );
    setState(() {
      _draft.add(draft);
      _draft.sort((a, b) => a.block.startTime.compareTo(b.block.startTime));
    });
    _editBlock(draft);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static DateTime _parseHm(String hm, DateTime day) {
    final p = hm.split(':');
    return DateTime(day.year, day.month, day.day,
        int.tryParse(p.first) ?? 0, int.tryParse(p.elementAtOrNull(1) ?? '') ?? 0);
  }

  static String _addMin(String hm, int min) {
    final p = hm.split(':');
    final total = (int.tryParse(p.first) ?? 0) * 60 +
        (int.tryParse(p.elementAtOrNull(1) ?? '') ?? 0) +
        min;
    final h = (total ~/ 60) % 24;
    final m = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String _nextQuarterHour() {
    final now = DateTime.now();
    final total = now.hour * 60 + now.minute;
    final next = ((total ~/ 15) + 1) * 15;
    final h = (next ~/ 60) % 24;
    final m = next % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String _dayName(DateTime d) =>
      const ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'][d.weekday - 1];

  static String _monthName(DateTime d) => const [
        '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
        'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
      ][d.month];
}
