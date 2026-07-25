import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_summary.dart';

/// Espace Coach (V1.1 — US-1 consentement + US-2 cockpit minimal).
/// Un rôle « coach » sur le même compte, pas une seconde app :
/// - côté coaché : rejoindre un coach par code, choisir CE QUI est partagé
///   (domaines opt-in + granularité), modifier ou révoquer à tout moment ;
/// - côté coach : inviter, et voir pour chaque coaché les engagements de la
///   semaine, la tendance 4 semaines et la dernière activité — rien d'autre.
/// La donnée est partagée, l'interprétation reste humaine.

// Échelle de couleur des paliers (design espace-coach, README §Échelle).
const _kAmber = Color(0xFFF2A93B);
const _kCoral = Color(0xFFFF6B5E);

Color _tierColor(ColorScheme cs, int pct) {
  if (pct >= 85) return cs.primary;
  if (pct >= 60) return _kAmber;
  return _kCoral;
}

class CoachSpaceScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;

  const CoachSpaceScreen({super.key, required this.logic, required this.sync});

  @override
  State<CoachSpaceScreen> createState() => _CoachSpaceScreenState();
}

class _CoachSpaceScreenState extends State<CoachSpaceScreen> {
  bool _loading = true;
  CoachLink? _myCoach; // lien actif où JE suis le coaché
  List<CoachLink> _asCoach = []; // liens où JE suis le coach
  final Map<String, Map<String, dynamic>> _summaries = {};
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final myCoach = await widget.sync.myCoachLinkAsCoachee();
    final asCoach = await widget.sync.myCoachLinksAsCoach();
    final summaries = <String, Map<String, dynamic>>{};
    for (final l in asCoach.where((l) => l.isActive)) {
      final s = await widget.sync.fetchCoachSummary(l.id);
      if (s != null) summaries[l.id] = s;
    }
    if (!mounted) return;
    setState(() {
      _myCoach = myCoach;
      _asCoach = asCoach;
      _summaries
        ..clear()
        ..addAll(summaries);
      _loading = false;
    });
  }

  // ── Côté coaché ─────────────────────────────────────────────────────────────

  Future<void> _joinWithCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final link = await widget.sync.getCoachLinkByCode(code);
    if (!mounted) return;
    if (link == null || link.status != 'invited') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Code inconnu ou invitation déjà utilisée. Vérifie avec ton coach.')));
      return;
    }
    await _showPerimeterSheet(link, accepting: true);
  }

  /// Choix du périmètre : domaines OPT-IN (aucun par défaut) + granularité.
  /// Sert à l'acceptation ET à la modification.
  Future<void> _showPerimeterSheet(CoachLink link,
      {required bool accepting}) async {
    final domains = widget.logic.state.activeDomains;
    final selected = accepting
        ? <String>{}
        : link.sharedDomainIds.toSet();
    var granularity = accepting ? 'status' : link.granularity;
    final nameCtrl = TextEditingController(text: link.coacheeName ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        Widget granCard(String value, String title, String body) {
          final sel = granularity == value;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setLocal(() => granularity = value),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      width: 2,
                      color: sel ? cs.primary : cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(.65))),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  accepting
                      ? 'Ce que ton coach verra'
                      : 'Modifier le partage',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'Rien n\'est partagé sans ton accord. Tu choisis les '
                  'domaines, tu peux tout couper à tout moment.',
                  style: TextStyle(
                      fontSize: 13.5, color: cs.onSurface.withOpacity(.6))),
              const SizedBox(height: 16),
              Text('DOMAINES PARTAGÉS',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in domains)
                    FilterChip(
                      selected: selected.contains(d.id),
                      onSelected: (v) => setLocal(() =>
                          v ? selected.add(d.id) : selected.remove(d.id)),
                      label: Text(d.name),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (selected.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Aucun domaine partagé : ton coach ne verra rien, '
                      'même pas les statuts.',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withOpacity(.5))),
                ),
              const SizedBox(height: 14),
              Text('GRANULARITÉ',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 8),
              Row(children: [
                granCard('status', 'Statuts seulement',
                    'Engagements tenus / en retard. Pas de détail.'),
                const SizedBox(width: 8),
                granCard('detail', 'Détail',
                    'Statuts + temps par activité de la semaine.'),
              ]),
              if (accepting) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Ton prénom (vu par le coach)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(accepting
                      ? 'Accepter et partager'
                      : 'Enregistrer le partage'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Consentement horodaté et journalisé. Un domaine non '
                  'partagé n\'apparaît nulle part, même agrégé.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(.45)),
                ),
              ),
            ],
          ),
        );
      }),
    );
    if (saved != true) {
      nameCtrl.dispose();
      return;
    }

    if (accepting) {
      final err = await widget.sync.acceptCoachInvite(
        link,
        sharedDomainIds: selected.toList(),
        granularity: granularity,
        coacheeName:
            nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      );
      if (!mounted) {
        nameCtrl.dispose();
        return;
      }
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        nameCtrl.dispose();
        return;
      }
      _codeCtrl.clear();
    } else {
      await widget.sync.updateCoachConsent(link.id,
          sharedDomainIds: selected.toList(), granularity: granularity);
    }
    nameCtrl.dispose();
    // Résumé réécrit tout de suite avec le nouveau périmètre (même vide :
    // le coach voit « rien n'est partagé » plutôt qu'un résumé périmé).
    await widget.sync.writeCoachSummary(
      link.id,
      buildCoachSummary(widget.logic.state,
          domainIds: selected.toList(), granularity: granularity),
    );
    await _reload();
  }

  Future<void> _revoke(CoachLink link, {required bool iAmCoach}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(iAmCoach ? 'Retirer ce coaché ?' : 'Révoquer le partage ?'),
        content: Text(iAmCoach
            ? 'Le lien sera coupé et tu perdras l\'accès à son résumé.'
            : 'Ton coach perd immédiatement tout accès, y compris à '
                'l\'historique. Tu gardes l\'app et toutes tes données.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.sync.revokeCoachLink(link.id);
    await _reload();
  }

  // ── Côté coach ──────────────────────────────────────────────────────────────

  Future<void> _invite() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inviter un coaché'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Un code d\'invitation sera généré. Ton coaché le saisit '
                'dans Paramètres → Espace coach, puis choisit lui-même ce '
                'qu\'il partage.'),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ton prénom (vu par le coaché)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Générer le code')),
        ],
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      return;
    }
    final link = await widget.sync.createCoachInvite(
        coachName:
            nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim());
    nameCtrl.dispose();
    if (link == null || !mounted) return;
    await _showCode(link.id);
    await _reload();
  }

  Future<void> _showCode(String code) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code d\'invitation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(code,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Text(
                'Transmets-le à ton coaché (SMS, mail…). Il reste valable '
                'jusqu\'à utilisation.',
                style: TextStyle(fontSize: 12.5)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Code copié')));
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copier'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _openCoacheeDetail(CoachLink link) {
    final s = _summaries[link.id];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        if (s == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
                'Aucun chiffre à afficher : rien n\'est partagé, même pas '
                'les statuts — ou ${link.coacheeName ?? 'ce coaché'} n\'a '
                'pas encore ouvert l\'app depuis l\'acceptation.',
                style: TextStyle(
                    fontSize: 14, color: cs.onSurface.withOpacity(.7))),
          );
        }
        final engagements =
            (s['engagements'] as List?)?.whereType<Map>().toList() ?? [];
        final weeks = (s['weeks'] as List?)?.whereType<Map>().toList() ?? [];
        final timeMin = s['timeMinByActivity'] is Map
            ? Map<String, dynamic>.from(s['timeMinByActivity'] as Map)
            : null;
        final domains = s['domains'] is Map
            ? Map<String, dynamic>.from(s['domains'] as Map)
            : <String, dynamic>{};
        final updatedAt = DateTime.tryParse(s['updatedAt']?.toString() ?? '');

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(link.coacheeName ?? 'Coaché',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              Text(
                  'Partage : ${domains.values.join(' · ')} — '
                  '${s['granularity'] == 'detail' ? 'détail' : 'statuts seulement'}',
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.6))),
              const SizedBox(height: 16),
              Text('SA SEMAINE',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 6),
              for (final e in engagements)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(
                        e['kept'] == true
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: e['kept'] == true
                            ? cs.primary
                            : cs.onSurface.withOpacity(.35)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('${e['label']}',
                            style: const TextStyle(fontSize: 13.5))),
                    Text('${e['done']} / ${e['target']}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              if (engagements.isEmpty)
                Text('Aucun engagement hebdo dans le périmètre partagé.',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurface.withOpacity(.55))),
              const SizedBox(height: 16),
              Text('4 DERNIÈRES SEMAINES',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 8),
              Row(children: [
                for (final w in weeks) ...[
                  Expanded(
                    child: Column(children: [
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: _tierColor(
                                  cs, (w['pct'] as num?)?.toInt() ?? 0)
                              .withOpacity(.25),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: _tierColor(
                                  cs, (w['pct'] as num?)?.toInt() ?? 0)),
                        ),
                        alignment: Alignment.center,
                        child: Text('${w['pct']} %',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                    ]),
                  ),
                  if (w != weeks.last) const SizedBox(width: 6),
                ],
              ]),
              if (timeMin != null && timeMin.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('TEMPS DE LA SEMAINE',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.45))),
                const SizedBox(height: 6),
                for (final e in timeMin.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                          child: Text(e.key,
                              style: const TextStyle(fontSize: 13.5))),
                      Text('${e.value} min',
                          style: const TextStyle(
                              fontSize: 13, fontFamily: 'monospace')),
                    ]),
                  ),
              ],
              const SizedBox(height: 14),
              if (updatedAt != null)
                Text(
                    'Mis à jour à la dernière ouverture de son app '
                    '(${updatedAt.day.toString().padLeft(2, '0')}/'
                    '${updatedAt.month.toString().padLeft(2, '0')} '
                    '${updatedAt.hour.toString().padLeft(2, '0')}:'
                    '${updatedAt.minute.toString().padLeft(2, '0')}). '
                    'Il voit ce que tu vois — rien de plus, rien d\'autre.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withOpacity(.45))),
            ],
          ),
        );
      },
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actives = _asCoach.where((l) => l.isActive).toList();
    final invites = _asCoach.where((l) => l.status == 'invited').toList();

    Widget sectionLabel(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(t,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: cs.onSurface.withOpacity(.45))),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Espace coach')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // ── Mon coach (côté coaché) ────────────────────────────────
                  sectionLabel('MON COACH'),
                  if (_myCoach != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_myCoach!.coachName ?? 'Ton coach',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                              _myCoach!.sharedDomainIds.isEmpty
                                  ? 'Rien n\'est partagé pour l\'instant.'
                                  : 'Partage : '
                                      '${_myCoach!.sharedDomainIds.length} domaine(s) — '
                                      '${_myCoach!.granularity == 'detail' ? 'détail' : 'statuts seulement'}. '
                                      'Il voit ce que tu as fait, pas tes états.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(.65))),
                          const SizedBox(height: 10),
                          Row(children: [
                            OutlinedButton(
                              onPressed: () => _showPerimeterSheet(_myCoach!,
                                  accepting: false),
                              child: const Text('Modifier le partage'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () =>
                                  _revoke(_myCoach!, iAmCoach: false),
                              child: Text('Révoquer',
                                  style: TextStyle(color: cs.error)),
                            ),
                          ]),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                        'Ton coach t\'a donné un code ? Saisis-le : tu '
                        'choisiras ensuite exactement ce qu\'il voit.',
                        style: TextStyle(
                            fontSize: 13.5,
                            color: cs.onSurface.withOpacity(.65))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _codeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: 'Ex : K7PMQ2WX',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _joinWithCode(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: _joinWithCode,
                          child: const Text('Rejoindre')),
                    ]),
                  ],

                  // ── Mes coachés (côté coach) ───────────────────────────────
                  sectionLabel('MES COACHÉS'),
                  if (actives.isEmpty && invites.isEmpty)
                    Text(
                        'Tu accompagnes quelqu\'un ? Invite-le : il garde la '
                        'main complète sur ce qu\'il partage.',
                        style: TextStyle(
                            fontSize: 13.5,
                            color: cs.onSurface.withOpacity(.65))),
                  for (final l in actives) _coacheeTile(cs, l),
                  for (final l in invites)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(Icons.hourglass_empty,
                          size: 20, color: cs.onSurface.withOpacity(.45)),
                      title: Text('Invitation en attente — code ${l.id}',
                          style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        tooltip: 'Copier le code',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _showCode(l.id),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _invite,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Inviter un coaché'),
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Le partage est choisi par le coaché : consentement '
                      'explicite, granulaire, révocable. Un domaine non '
                      'partagé n\'apparaît nulle part, même agrégé.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(.45)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Ligne coaché : les 3 chiffres de l'US-2 — engagements de la semaine,
  /// tendance 4 semaines, dernière activité. Lecture seule.
  Widget _coacheeTile(ColorScheme cs, CoachLink l) {
    final s = _summaries[l.id];
    final kept = (s?['keptCount'] as num?)?.toInt() ?? 0;
    final total = (s?['totalCount'] as num?)?.toInt() ?? 0;
    final weeks = (s?['weeks'] as List?)?.whereType<Map>().toList() ?? [];
    final lastPct =
        weeks.isNotEmpty ? (weeks.last['pct'] as num?)?.toInt() ?? 0 : 0;
    final prevPct = weeks.length >= 2
        ? (weeks[weeks.length - 2]['pct'] as num?)?.toInt() ?? 0
        : lastPct;
    final lastAt =
        DateTime.tryParse(s?['lastActivityAt']?.toString() ?? '');
    final pct = total == 0 ? 0 : ((kept / total) * 100).round();
    final color = s == null || total == 0
        ? cs.onSurface.withOpacity(.4)
        : _tierColor(cs, pct);
    final trendUp = lastPct >= prevPct;

    String lastLabel;
    if (lastAt == null) {
      lastLabel = '—';
    } else {
      final days = DateTime.now().difference(lastAt).inDays;
      lastLabel = days <= 0 ? 'aujourd\'hui' : (days == 1 ? 'hier' : 'il y a $days j');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withOpacity(.18),
          child: Text(
            (l.coacheeName?.trim().isNotEmpty ?? false)
                ? l.coacheeName!.trim()[0].toUpperCase()
                : '?',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        title: Text(l.coacheeName ?? 'Coaché',
            style:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: Text(
            s == null
                ? 'Rien de partagé (ou app pas encore rouverte).'
                : 'Dernière activité : $lastLabel',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(.55))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (s != null && total > 0) ...[
            Text('$kept / $total',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color)),
            const SizedBox(width: 6),
            Icon(trendUp ? Icons.trending_up : Icons.trending_down,
                size: 18, color: trendUp ? cs.primary : _kCoral),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Retirer ce coaché',
            icon: Icon(Icons.link_off,
                size: 18, color: cs.onSurface.withOpacity(.4)),
            onPressed: () => _revoke(l, iAmCoach: true),
          ),
        ]),
        onTap: () => _openCoacheeDetail(l),
      ),
    );
  }
}
