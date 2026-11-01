import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// « Mon coach » (Espace Coach V1.1, côté coaché) — mobile ET web.
///
/// Le lien coach-coaché vit côté serveur (brique coaching : fiche
/// `coaching/{id}` server-only, consentement par lien web `coachConsent`).
/// Ici le coaché gère SON partage via `coacheeApi` :
/// - voir le lien (coach, consentement, périmètre) ;
/// - choisir les domaines partagés (opt-in) + la granularité ;
/// - tout révoquer, immédiatement.
/// Le rôle coach, lui, vit dans la console web (bouton 🎓 → console 8a).
/// Mobile : Paramètres → Mon coach (AppLogic fourni, domaines locaux).
/// Web : icône AppBar (logic null → domaines chargés depuis Firestore).

const _kCoacheeApiUrl = 'https://coacheeapi-dzos75b65q-uc.a.run.app';

Future<Map<String, dynamic>> _coacheeCall(Map<String, dynamic> body) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Non connecté');
  final idToken = await user.getIdToken();
  final resp = await http
      .post(
        Uri.parse(_kCoacheeApiUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 30));
  final data = resp.body.isNotEmpty
      ? jsonDecode(resp.body) as Map<String, dynamic>
      : <String, dynamic>{};
  if (resp.statusCode >= 400) {
    throw Exception((data['error'] as String?) ?? 'HTTP ${resp.statusCode}');
  }
  return data;
}

class CoachSpaceScreen extends StatefulWidget {
  /// Mobile : l'AppLogic fournit les domaines locaux. Web : null →
  /// les domaines sont chargés depuis Firestore (même source de vérité).
  final AppLogic? logic;

  const CoachSpaceScreen({super.key, this.logic});

  @override
  State<CoachSpaceScreen> createState() => _CoachSpaceScreenState();
}

class _CoachSpaceScreenState extends State<CoachSpaceScreen> {
  bool _loading = true;
  String? _error;
  bool _linked = false;
  String _coachName = 'Ton coach';
  String _consent = 'pending';
  List<String> _domainIds = [];
  String _granularity = 'status';
  bool _shareState = false; // granularité « état » : élan, effort, humeur
  bool _shareGames = false; // parole tenue, Montre suisse, Métronome, posé la veille
  bool _shareSleep = false; // sommeil (à part : c'est intime)
  List<Domain> _domains = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _domains = widget.logic?.state.activeDomains ??
          await FirestoreSync().fetchDomains();
      final r = await _coacheeCall({'action': 'getLink'});
      _linked = r['linked'] == true;
      if (_linked) {
        _coachName = (r['coachName'] as String?) ?? 'Ton coach';
        _consent = (r['consent'] as String?) ?? 'pending';
        final sharing = (r['sharing'] as Map?) ?? const {};
        _domainIds =
            (sharing['domainIds'] as List?)?.cast<String>() ?? <String>[];
        _granularity =
            sharing['granularity'] == 'detail' ? 'detail' : 'status';
        _shareState = sharing['state'] == true;
        _shareGames = sharing['games'] == true;
        _shareSleep = sharing['sleep'] == true;
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Éditeur de périmètre : domaines OPT-IN + granularité, validés serveur.
  Future<void> _editSharing() async {
    final domains = _domains;
    final selected = _domainIds.toSet();
    var granularity = _granularity;
    var shareState = _shareState;
    var shareGames = _shareGames;
    var shareSleep = _shareSleep;

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
                      width: 2, color: sel ? cs.primary : cs.outlineVariant),
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
              Text('Ce que $_coachName verra',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'Il voit ce que tu as fait, pas tes états. Un domaine non '
                  'partagé n\'apparaît nulle part, même agrégé.',
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
                    'Statuts + temps par activité + programme du jour.'),
              ]),
              const SizedBox(height: 14),
              Text('MON ÉTAT',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: shareState,
                onChanged: (v) => setLocal(() => shareState = v),
                title: const Text('Partager mon élan, mes efforts et mon humeur',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Les pointages de la semaine (élan moyen, fois où j\u2019ai fait quand même). '
                    'Sans ce réglage, il voit mes badges mais pas mes états.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.65))),
              ),
              const SizedBox(height: 10),
              Text('MES JEUX DE LA JOURNÉE',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: shareGames,
                onChanged: (v) => setLocal(() => shareGames = v),
                title: const Text('Partager parole tenue, Montre suisse, Métronome, journée posée la veille',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Une case par jour sur 7 jours : tenu, manqué ou rien à mesurer. Quand la Montre suisse coince, '
                    'il voit le nom de l\u2019activité seulement si son domaine est partagé.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.65))),
              ),
              const SizedBox(height: 6),
              Text('MON SOMMEIL',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: shareSleep,
                onChanged: (v) => setLocal(() => shareSleep = v),
                title: const Text('Partager mon sommeil',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Durée des 7 dernières nuits, dette, heure de coucher face à ton bloc Sommeil, et l\u2019effet '
                    'd\u2019une nuit courte sur ta flemme du lendemain. Désactivé tant que tu ne l\u2019actives pas.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.65))),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Enregistrer le partage'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Chaque changement est horodaté et journalisé (RGPD).',
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(.45)),
                ),
              ),
            ],
          ),
        );
      }),
    );
    if (saved != true) return;
    try {
      await _coacheeCall({
        'action': 'updateSharing',
        'domainIds': selected.toList(),
        'granularity': granularity,
        'state': shareState,
        'games': shareGames,
        'sleep': shareSleep,
      });
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showClosingSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _revoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Révoquer le partage ?'),
        content: const Text(
            'Ton coach perd immédiatement tout accès, y compris à '
            'l\'historique. Tu gardes l\'app et toutes tes données. '
            'Tu pourras ré-accepter plus tard via un nouveau lien.'),
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
    try {
      await _coacheeCall({'action': 'revoke'});
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showClosingSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Ce que le coach voit et ne voit pas, d'après le partage en cours.
  Widget _sharedList(ColorScheme cs) {
    final any = _domainIds.isNotEmpty;
    final seen = <(bool, String, String)>[
      (any, 'Tes engagements', 'tenus ou en retard, dans les domaines partagés'),
      (any && _granularity == 'detail', 'Ton temps et ton programme', 'temps par activité, blocs du jour, nombre d\u2019idées en attente'),
      (any, 'Tes badges', 'paliers obtenus ; séries des routines des domaines partagés seulement'),
      (_shareState, 'Ton état', 'élan, efforts, humeur de la semaine'),
      (_shareGames, 'Tes jeux de la journée', 'parole tenue, Montre suisse, Métronome, posé la veille'),
      (_shareSleep, 'Ton sommeil', 'durée, dette, heure de coucher, effet sur le lendemain'),
    ];
    Widget row(bool on, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(on ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18, color: on ? cs.primary : cs.onSurface.withOpacity(.35)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: on ? null : cs.onSurface.withOpacity(.5))),
                Text(on ? sub : 'non partagé · $sub',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.55))),
              ]),
            ),
          ]),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 6),
          child: Text(t,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withOpacity(.45))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: label('CE QUE ${_coachName.toUpperCase()} VOIT')),
        const InfoDot(kRuleCoachSharing),
      ]),
      for (final (_, t, sub) in seen.where((e) => e.$1)) row(true, t, sub),
      if (seen.every((e) => !e.$1)) Text('Rien pour l\u2019instant.', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.55))),
      const SizedBox(height: 8),
      label('CE QU\u2019IL NE VOIT PAS'),
      for (final (_, t, sub) in seen.where((e) => !e.$1)) row(false, t, sub),
      row(false, 'Les domaines que tu ne partages pas', 'nulle part, même agrégés dans un total'),
      row(false, 'Le texte de tes idées et de tes notes', 'ni ta boîte d\u2019idées, ni le détail de tes actions'),
      row(false, 'De quoi télécharger tes données', 'il lit le cockpit, il n\u2019exporte rien'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final domainNames = {for (final d in _domains) d.id: d.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Mon coach')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                          'Impossible de joindre le serveur — tire pour '
                          'réessayer.\n($_error)',
                          style: TextStyle(fontSize: 12.5, color: cs.error)),
                    ),
                  if (!_linked) ...[
                    Icon(Icons.supervisor_account_outlined,
                        size: 40, color: cs.onSurface.withOpacity(.25)),
                    const SizedBox(height: 12),
                    Text(
                      'Pas de coach relié pour l\'instant.\n\n'
                      'Si tu travailles avec un coach, il t\'enverra un lien '
                      'de consentement (WhatsApp, mail…). Accepter ouvre le '
                      'lien mais ne partage RIEN : c\'est ici que tu '
                      'choisiras ensuite quels domaines de vie il peut voir, '
                      'et à quel niveau de détail.',
                      style: TextStyle(
                          fontSize: 14, color: cs.onSurface.withOpacity(.65)),
                    ),
                  ] else if (_consent == 'granted') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_coachName,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          if (_domainIds.isEmpty)
                            Text(
                                'Le lien est actif, mais il ne voit encore RIEN, même pas les statuts. À toi de choisir.',
                                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.7)))
                          else
                            Text('Domaines partagés : ${_domainIds.map((id) => domainNames[id] ?? '…').join(' · ')}',
                                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.7))),
                          const SizedBox(height: 12),
                          Row(children: [
                            FilledButton(
                              onPressed: _editSharing,
                              child: Text(_domainIds.isEmpty
                                  ? 'Choisir ce que je partage'
                                  : 'Modifier le partage'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _revoke,
                              child: Text('Révoquer',
                                  style: TextStyle(color: cs.error)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sharedList(cs),
                  ] else ...[
                    Text(
                      _consent == 'revoked'
                          ? 'Tu as révoqué l\'accès de $_coachName — il ne '
                              'voit plus rien. Pour reprendre, demande-lui un '
                              'nouveau lien de consentement.'
                          : '$_coachName t\'a proposé un accompagnement. '
                              'Accepte (ou refuse) via le lien de '
                              'consentement qu\'il t\'a envoyé — rien ne '
                              's\'active sans toi.',
                      style: TextStyle(
                          fontSize: 14, color: cs.onSurface.withOpacity(.65)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Consentement explicite, granulaire, révocable — '
                      'à tout moment, en deux taps, sans préavis.',
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
}
