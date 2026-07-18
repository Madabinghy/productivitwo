import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';

// ─── GÉNÉRATION D'ARTEFACTS (maquettes 14a/14b · 15a/15b) ────────────────────
//
// L'intention devient du programme : un artefact (plan, menu) est une SOURCE DE
// BLOCS, pas un document à lire. Cadrage = 3-4 paramètres pré-remplis depuis la
// fiche domaine, chacun éditable — pas un wizard. Génération = 1 appel (classe
// quotidienne), JSON structuré, jamais d'artefact à moitié écrit. « Vivant,
// pas gravé » : ⟳ régénère LA SUITE depuis les faits, le passé n'est jamais
// réécrit (jamais de culpabilité rétroactive).

const String _kGenerateUrl = 'https://generateartifact-dzos75b65q-uc.a.run.app';

/// Détecte le kind d'artefact depuis le libellé voulu en session (13c).
String artifactKindFromLabel(String label) =>
    RegExp(r'menu|repas|cuisine|meal', caseSensitive: false).hasMatch(label)
        ? 'weekly_menu'
        : 'training_plan';

// ── Cadrage (14a / 15a) ───────────────────────────────────────────────────────

class ArtifactSetupScreen extends StatefulWidget {
  final Domain domain;
  final String kind; // training_plan | weekly_menu

  const ArtifactSetupScreen(
      {super.key, required this.domain, required this.kind});

  @override
  State<ArtifactSetupScreen> createState() => _ArtifactSetupScreenState();
}

class _ArtifactSetupScreenState extends State<ArtifactSetupScreen> {
  final _sync = FirestoreSync();
  bool _generating = false;
  String? _error;

  // Les 3-4 paramètres, pré-remplis depuis la fiche (modalités, vital).
  late final List<_Param> _params;

  bool get _isMenu => widget.kind == 'weekly_menu';

  @override
  void initState() {
    super.initState();
    final d = widget.domain;
    final firstModality = d.modalities.isNotEmpty ? d.modalities.first : null;
    final vital = d.vitalMinimum.isNotEmpty ? d.vitalMinimum.first : null;
    if (_isMenu) {
      _params = [
        _Param('Repas cuisinés — ton vital',
            vital != null ? vital.label : '4 / semaine'),
        _Param('Batch — depuis ta fiche',
            _modalityLike(d, RegExp(r'cuisine|batch|dimanche')) ??
                'Dimanche 17 h · 1 h 30 max'),
        _Param('Contraintes', 'Simple, rapide à réchauffer'),
        _Param('On ne touche pas', 'Ven + sam soir — off, pas de menu',
            offSlots: true),
      ];
    } else {
      _params = [
        _Param('Durée du plan', '6 semaines, progressif'),
        _Param('Créneau — depuis ta fiche',
            firstModality ?? 'Matin 7 h 15 · 20 min · ×3/sem'),
        _Param('Point de départ', 'Reprise en douceur'),
        _Param('Matériel', 'Poids du corps'),
      ];
    }
  }

  String? _modalityLike(Domain d, RegExp re) {
    for (final m in d.modalities) {
      if (re.hasMatch(m.toLowerCase())) return m;
    }
    return null;
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final token = await _sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = _sync.uid;
      if (raw == null || raw.isEmpty || uid == null) {
        throw Exception('token indisponible');
      }
      final resp = await http
          .post(
            Uri.parse(_kGenerateUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $raw',
            },
            body: jsonEncode({
              'uid': uid,
              'kind': widget.kind,
              'domainId': widget.domain.id,
              'params': {for (final p in _params) p.label: p.value},
            }),
          )
          .timeout(const Duration(seconds: 90));
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        throw Exception(body['error'] ?? 'HTTP ${resp.statusCode}');
      }
      final artifact = await _sync.fetchArtifact(body['artifactId'] as String);
      if (artifact == null) throw Exception('artefact introuvable');
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) =>
              ArtifactViewScreen(artifact: artifact, domain: widget.domain),
        ));
      }
    } catch (_) {
      // Jamais d'artefact à moitié écrit : erreur + retry, rien n'est posé.
      if (mounted) {
        setState(() {
          _generating = false;
          _error = 'Génération échouée — rien n\'a été écrit. Réessaie.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vital = widget.domain.vitalMinimum.isNotEmpty
        ? widget.domain.vitalMinimum.first.label
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isMenu ? 'Menu de la semaine' : 'Plan de reprise',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text('${widget.domain.name.toUpperCase()} · AVANT DE GÉNÉRER',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.primary)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withOpacity(.3)),
            ),
            child: Text(
              _isMenu
                  ? 'Un menu qui se vit, pas un menu de magazine : je génère les repas cuisinés, les courses qui vont avec, et je laisse tes soirs off tranquilles.'
                  : 'Tout vient de ta fiche — vérifie ces quatre points, je génère le reste.',
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: cs.onSurface.withOpacity(.9)),
            ),
          ),
          for (final p in _params) _paramRow(cs, p),
          if (vital != null && !_isMenu)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.anchor_rounded,
                      size: 14, color: cs.onSurface.withOpacity(.4)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Raccordé au vital : $vital — le plan peut en poser plus, la marge est voulue.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: cs.onSurface.withOpacity(.55)),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: TextStyle(fontSize: 13, color: cs.error)),
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _generating ? null : _generate,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            child: _generating
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('Génération… ~30 s'),
                    ],
                  )
                : Text(_isMenu
                    ? 'Générer le menu — ~30 s'
                    : 'Générer le plan — ~30 s'),
          ),
        ],
      ),
    );
  }

  Widget _paramRow(ColorScheme cs, _Param p) {
    final accent = p.offSlots ? cs.tertiary : null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editParam(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: accent?.withOpacity(.6) ?? cs.onSurface.withOpacity(.14)),
          color: cs.surfaceContainerHighest.withOpacity(.25),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: accent ?? cs.onSurface.withOpacity(.45))),
                  const SizedBox(height: 3),
                  Text(p.value,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Text('modifier',
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withOpacity(.35))),
          ],
        ),
      ),
    );
  }

  Future<void> _editParam(_Param p) async {
    final ctrl = TextEditingController(text: p.value);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.label, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (t) => Navigator.pop(ctx, t.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) setState(() => p.value = v);
  }
}

class _Param {
  final String label;
  String value;
  final bool offSlots; // « on ne touche pas » — mise en avant ambre
  _Param(this.label, this.value, {this.offSlots = false});
}

// ── Rendu (14b / 15b) ─────────────────────────────────────────────────────────

class ArtifactViewScreen extends StatefulWidget {
  final Artifact artifact;
  final Domain domain;

  const ArtifactViewScreen(
      {super.key, required this.artifact, required this.domain});

  @override
  State<ArtifactViewScreen> createState() => _ArtifactViewScreenState();
}

class _ArtifactViewScreenState extends State<ArtifactViewScreen> {
  final _sync = FirestoreSync();
  late Artifact _artifact;
  bool _regenerating = false;

  bool get _isMenu => _artifact.kind == 'weekly_menu';

  @override
  void initState() {
    super.initState();
    _artifact = widget.artifact;
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// ⟳ : régénère LA SUITE depuis les faits — le passé n'est jamais réécrit.
  Future<void> _regenerate() async {
    if (_regenerating) return;
    setState(() => _regenerating = true);
    try {
      final token = await _sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = _sync.uid;
      if (raw == null || raw.isEmpty || uid == null) {
        throw Exception('token indisponible');
      }
      final resp = await http
          .post(
            Uri.parse(_kGenerateUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $raw',
            },
            body: jsonEncode({
              'uid': uid,
              'kind': _artifact.kind,
              'domainId': _artifact.domainId,
              'params': _artifact.params,
              'artifactId': _artifact.id,
              'regenerateFrom': _ymd(DateTime.now()),
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final fresh = await _sync.fetchArtifact(_artifact.id);
      if (fresh != null && mounted) setState(() => _artifact = fresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Régénération échouée — l\'artefact actuel est intact.')));
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  // ── Composition déterministe du menu (plat par plat) ──────────────────────

  String _dayLabel(DateTime d, DateTime today) {
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'aujourd\'hui';
    if (diff == 1) return 'demain';
    return '${_shortDay(d)} ${d.day}';
  }

  /// Ajoute un plat : jour + plat (bibliothèque « Mes plats » ou nouveau,
  /// avec ingrédients) → entrée datée + ingrédients dans la liste de courses
  /// (au fil de l'eau, dédupliqués). Le plat entre dans la bibliothèque.
  Future<void> _addDish() async {
    final recipes = await _sync.fetchRecipes()
      ..sort((a, b) {
        final c = b.timesCooked.compareTo(a.timesCooked);
        if (c != 0) return c;
        return (b.lastCookedAt ?? DateTime(2000))
            .compareTo(a.lastCookedAt ?? DateTime(2000));
      });
    if (!mounted) return;
    final titleCtrl = TextEditingController();
    final ingCtrl = TextEditingController();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    var pickedDay = _ymd(today);
    String? pickedRecipeId;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;
          Text sectionLabel(String t) => Text(t,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: cs.onSurface.withOpacity(.45)));
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ajouter un plat',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                sectionLabel('QUEL JOUR ?'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in days)
                      ChoiceChip(
                        selected: pickedDay == _ymd(d),
                        onSelected: (_) =>
                            setLocal(() => pickedDay = _ymd(d)),
                        showCheckmark: false,
                        label: Text(_dayLabel(d, today)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (recipes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  sectionLabel('MES PLATS — DÉJÀ CUISINÉS'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in recipes.take(12))
                        ChoiceChip(
                          selected: pickedRecipeId == r.id,
                          onSelected: (_) => setLocal(() {
                            if (pickedRecipeId == r.id) {
                              pickedRecipeId = null;
                              titleCtrl.clear();
                              ingCtrl.clear();
                            } else {
                              pickedRecipeId = r.id;
                              titleCtrl.text = r.title;
                              ingCtrl.text = r.ingredients
                                  .map((i) => i.qty.isEmpty
                                      ? i.label
                                      : '${i.label} ${i.qty}')
                                  .join('\n');
                            }
                          }),
                          showCheckmark: false,
                          label: Text(r.timesCooked > 0
                              ? '${r.title} ×${r.timesCooked}'
                              : r.title),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  autofocus: recipes.isEmpty,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Plat',
                    hintText: 'Ex : Colombo de poulet',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ingCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Ingrédients — un par ligne (optionnel)',
                    hintText: 'Poulet 600 g\nRiz\nCitron vert',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.restaurant_menu, size: 16),
                    label: const Text('Ajouter au menu'),
                    onPressed: () {
                      if (titleCtrl.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, true);
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final title = titleCtrl.text.trim();
    final ings = ingCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => ShoppingItem(label: l))
        .toList();
    titleCtrl.dispose();
    ingCtrl.dispose();
    if (saved != true || title.isEmpty) return;

    _artifact.entries
        .add(ArtifactEntry(date: pickedDay, time: '19:00', title: title));
    // Courses AU FIL DE L'EAU : les ingrédients rejoignent la liste,
    // dédupliqués par libellé (non cochés — à acheter).
    final have =
        _artifact.shoppingList.map((s) => s.label.toLowerCase()).toSet();
    for (final i in ings) {
      if (have.add(i.label.toLowerCase())) _artifact.shoppingList.add(i);
    }
    await _sync.saveArtifact(_artifact);
    // Bibliothèque : le plat est archivé (réexploitable) ; ses ingrédients
    // sont conservés/complétés. Le compteur, lui, vit sur « ✓ Mangé ».
    Recipe? existing;
    for (final r in recipes) {
      if (r.id == pickedRecipeId ||
          r.title.toLowerCase() == title.toLowerCase()) {
        existing = r;
      }
    }
    if (existing == null) {
      await _sync.saveRecipe(Recipe(title: title, ingredients: ings));
    } else if (ings.isNotEmpty) {
      existing.ingredients = ings;
      await _sync.saveRecipe(existing);
    }
    if (mounted) setState(() {});
  }

  Future<void> _removeEntry(ArtifactEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer « ${e.title} » ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    _artifact.entries.remove(e);
    await _sync.saveArtifact(_artifact);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));

    // Semaine courante détaillée / suites repliées.
    final thisWeek = <ArtifactEntry>[];
    final later = <ArtifactEntry>[];
    final weekly = <ArtifactEntry>[]; // motif hebdo (weekday) — menus
    for (final e in _artifact.entries) {
      if (e.date != null) {
        final d = DateTime.tryParse(e.date!);
        if (d == null) continue;
        if (d.isBefore(nextMonday)) {
          if (!d.isBefore(monday)) thisWeek.add(e);
        } else {
          later.add(e);
        }
      } else if (e.weekday != null) {
        weekly.add(e);
      }
    }
    thisWeek.sort((a, b) => (a.date! + a.time).compareTo(b.date! + b.time));

    final generatedLabel =
        'GÉNÉRÉ LE ${_artifact.generatedAt.day} ${_monthName(_artifact.generatedAt)}'.toUpperCase();
    // Menu composé à la main (100 % déterministe) : pas de ⟳ IA.
    final manual = _artifact.params['manual'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_artifact.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
                'ARTEFACT · ${widget.domain.name.toUpperCase()} · $generatedLabel',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: cs.primary)),
          ],
        ),
        actions: [
          if (!manual)
            IconButton(
              tooltip: 'Régénérer la suite (le passé ne bouge pas)',
              icon: _regenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
              onPressed: _regenerate,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // Intention citée en tête — les mots du user, jamais reformulés.
          if (widget.domain.intention?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                '« ${widget.domain.intention} »'
                '${widget.domain.vitalMinimum.isNotEmpty ? ' — chaque semaine tient le vital : ${widget.domain.vitalMinimum.first.label}.' : ''}',
                style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withOpacity(.75)),
              ),
            ),
          if (thisWeek.isNotEmpty) ...[
            Text('SEMAINE 1 — CETTE SEMAINE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.primary)),
            const SizedBox(height: 8),
            for (final e in thisWeek) _entryRow(cs, e, dated: true),
            const SizedBox(height: 10),
          ],
          if (weekly.isNotEmpty) ...[
            if (thisWeek.isEmpty) const SizedBox(height: 4),
            for (final e in weekly) _entryRow(cs, e, dated: false),
            const SizedBox(height: 10),
          ],
          // Suites repliées.
          if (later.isNotEmpty)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text('La suite — ${later.length} entrées',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              children: [
                for (final e in later) _entryRow(cs, e, dated: true),
              ],
            ),
          // Composition déterministe : plat par plat, courses au fil de l'eau.
          if (_isMenu) ...[
            if (_artifact.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Menu vide — ajoute un premier plat : pas besoin de '
                  'remplir la semaine d\'un coup, un jour à la fois suffit.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: cs.onSurface.withOpacity(.55)),
                ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ajouter un plat'),
              onPressed: _addDish,
            ),
            const SizedBox(height: 10),
          ],
          // Courses — dérivées du menu.
          if (_isMenu && _artifact.shoppingList.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.onSurface.withOpacity(.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('COURSES — DÉRIVÉES DU MENU',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: cs.onSurface.withOpacity(.5))),
                      ),
                      Text('${_artifact.shoppingList.length} articles',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.4))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Cochable (fait en magasin) — persisté sur l'artefact,
                      // partagé avec la section @courses de l'onglet Actions.
                      for (final s in _artifact.shoppingList)
                        FilterChip(
                          selected: s.checked,
                          onSelected: (v) {
                            setState(() => s.checked = v);
                            _sync.saveArtifact(_artifact);
                          },
                          label: Text(
                              s.qty.isEmpty ? s.label : '${s.label} ${s.qty}',
                              style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.refresh_rounded,
                  size: 14, color: cs.onSurface.withOpacity(.4)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Vivant, pas gravé : les entrées partent dans le programme via la planification — si une semaine déraille, ⟳ régénère la suite depuis les faits (jamais de culpabilité rétroactive).',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: cs.onSurface.withOpacity(.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryRow(ColorScheme cs, ArtifactEntry e, {required bool dated}) {
    final lead = dated && e.date != null
        ? _shortDay(DateTime.tryParse(e.date!))
        : _weekdayFr(e.weekday);
    return GestureDetector(
      // Menu : long press = retirer le plat (la liste de courses ne bouge
      // pas — ses articles peuvent servir d'autres plats).
      onLongPress: _isMenu ? () => _removeEntry(e) : null,
      child: _entryRowBody(cs, e, lead),
    );
  }

  Widget _entryRowBody(ColorScheme cs, ArtifactEntry e, String lead) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: e.optional
                ? cs.onSurface.withOpacity(.12)
                : cs.primary.withOpacity(.3)),
        color: e.optional
            ? Colors.transparent
            : cs.primary.withOpacity(.04),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text('$lead ${e.time}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: cs.primary)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${e.title} — ${fmtMin(e.durationMin)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (e.detail?.isNotEmpty == true ||
                    e.portions != null ||
                    e.optional)
                  Text(
                    [
                      if (e.detail?.isNotEmpty == true) e.detail!,
                      if (e.portions != null) '${e.portions} portions',
                      if (e.optional) 'optionnelle, hors vital',
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: cs.onSurface.withOpacity(.55)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortDay(DateTime? d) {
    if (d == null) return '';
    return const ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'][d.weekday - 1];
  }

  String _weekdayFr(String? w) => switch (w) {
        'mon' => 'lun',
        'tue' => 'mar',
        'wed' => 'mer',
        'thu' => 'jeu',
        'fri' => 'ven',
        'sat' => 'sam',
        'sun' => 'dim',
        _ => w ?? '',
      };

  String _monthName(DateTime d) => const [
        '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
        'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
      ][d.month];
}

// ── Raccourcis Accueil « Mes programmes » ────────────────────────────────────
// Les artefacts (menu de la semaine, plan d'entraînement) étaient enterrés :
// Accueil → Gérer → « Mes domaines » → chips. Cette section les remonte en
// accès direct sur l'Accueil — masquée s'il n'y en a aucun.

class ArtifactShortcuts extends StatelessWidget {
  final List<Domain> domains;
  const ArtifactShortcuts({super.key, required this.domains});

  /// Création SANS session Orion. Menu = 100 % DÉTERMINISTE (pas d'IA) : un
  /// menu vide qu'on compose plat par plat depuis la bibliothèque, courses au
  /// fil de l'eau. Plan sport = cadrage → génération (inchangé).
  Future<void> _create(
      BuildContext context, List<Artifact> existing) async {
    var kind = 'weekly_menu';
    Domain? domain = domains.isNotEmpty ? domains.first : null;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nouveau programme',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'weekly_menu',
                        label: Text('Menu semaine'),
                        icon: Icon(Icons.restaurant_menu, size: 16)),
                    ButtonSegment(
                        value: 'training_plan',
                        label: Text('Plan sport'),
                        icon: Icon(Icons.fitness_center, size: 16)),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setLocal(() => kind = s.first),
                ),
                const SizedBox(height: 14),
                Text('SUR LE DOMAINE',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.45))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in domains)
                      ChoiceChip(
                        selected: domain?.id == d.id,
                        onSelected: (_) => setLocal(() => domain = d),
                        showCheckmark: false,
                        label: Text(d.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (kind == 'weekly_menu') ...[
                  const SizedBox(height: 10),
                  Text(
                    'Zéro IA : tu composes ton menu plat par plat depuis '
                    'tes plats déjà cuisinés, les courses suivent toutes '
                    'seules.',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(.55)),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: Icon(
                        kind == 'weekly_menu'
                            ? Icons.restaurant_menu
                            : Icons.auto_awesome,
                        size: 16),
                    label: Text(kind == 'weekly_menu'
                        ? 'Créer mon menu — plat par plat'
                        : 'Cadrer puis générer'),
                    onPressed: domain == null
                        ? null
                        : () async {
                            final d = domain!;
                            Navigator.pop(ctx);
                            if (kind == 'weekly_menu') {
                              // Un seul menu par domaine : s'il existe déjà,
                              // on l'ouvre au lieu d'en empiler un second.
                              Artifact? menu;
                              for (final a in existing) {
                                if (a.kind == 'weekly_menu' &&
                                    a.domainId == d.id) {
                                  menu = a;
                                }
                              }
                              if (menu == null) {
                                menu = Artifact(
                                    kind: 'weekly_menu',
                                    domainId: d.id,
                                    params: {'manual': true});
                                await FirestoreSync().saveArtifact(menu);
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ArtifactViewScreen(
                                    artifact: menu!, domain: d),
                              ));
                              return;
                            }
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ArtifactSetupScreen(
                                  domain: d, kind: kind),
                            ));
                          },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Artifact>>(
      stream: FirestoreSync().streamArtifacts(),
      builder: (ctx, snap) {
        final arts =
            (snap.data ?? const <Artifact>[]).where((a) => !a.deleted).toList();
        // Sans domaine, le cadrage n'a rien à pré-remplir — section muette.
        if (arts.isEmpty && domains.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mes programmes',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(.4),
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in arts)
                    ActionChip(
                      avatar: Icon(
                        a.kind == 'weekly_menu'
                            ? Icons.restaurant_menu
                            : Icons.fitness_center,
                        size: 14,
                        color: cs.primary,
                      ),
                      label: Text(a.title,
                          style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Domain? d;
                        for (final x in domains) {
                          if (x.id == a.domainId) d = x;
                        }
                        if (d == null) return;
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ArtifactViewScreen(artifact: a, domain: d!),
                        ));
                      },
                    ),
                  if (domains.isNotEmpty)
                    ActionChip(
                      avatar: Icon(Icons.add,
                          size: 14, color: cs.onSurface.withOpacity(.6)),
                      label: const Text('Créer…',
                          style: TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _create(context, arts),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
