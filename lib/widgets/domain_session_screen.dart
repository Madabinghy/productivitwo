import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/artifact_screens.dart';
import 'package:productivitwo_v1/widgets/domain_onboarding_screen.dart';

/// Session de définition d'un domaine (maquettes 13a → 13c) : une vraie
/// conversation avec Orion, pas un formulaire. Chaque élément validé est ÉCRIT
/// en base par l'outil save_domain_definition côté serveur — le panneau « La
/// fiche se construit » reflète l'état RÉEL du doc Firestore, « reprendre plus
/// tard » est gratuit (draft). Moment fondateur → modèle premium plafonné.
class DomainSessionScreen extends StatefulWidget {
  final AppLogic logic;
  final String domainName;

  const DomainSessionScreen({
    super.key,
    required this.logic,
    required this.domainName,
  });

  @override
  State<DomainSessionScreen> createState() => _DomainSessionScreenState();
}

enum _Stage { intro, chat, result }

class _ChatMsg {
  final String role; // user | assistant
  final String content;
  _ChatMsg(this.role, this.content);
}

class _DomainSessionScreenState extends State<DomainSessionScreen> {
  static const String _kChatUrl =
      'https://definedomainchat-dzos75b65q-uc.a.run.app';

  final _sync = FirestoreSync();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  _Stage _stage = _Stage.intro;
  final List<_ChatMsg> _messages = [];
  bool _busy = false;
  Domain? _domain; // fiche réelle, streamée depuis Firestore
  StreamSubscription<List<Domain>>? _domainsSub;

  @override
  void initState() {
    super.initState();
    _domainsSub = _sync.streamDomains().listen((domains) {
      if (!mounted) return;
      final match = domains
          .where((d) =>
              d.name.trim().toLowerCase() ==
              widget.domainName.trim().toLowerCase())
          .toList();
      setState(() => _domain = match.isNotEmpty ? match.first : null);
      // La fiche est finalisée côté serveur → écran résultat.
      if (_stage == _Stage.chat && (_domain?.isDefined ?? false)) {
        _showResult();
      }
    });
  }

  @override
  void dispose() {
    _domainsSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _resumable =>
      _domain != null && _domain!.definitionStatus == 'draft';

  // ── Conversation ─────────────────────────────────────────────────────────────

  Future<void> _start() async {
    setState(() => _stage = _Stage.chat);
    await _send(
      _resumable
          ? 'Reprenons la session de définition là où on s\'était arrêtés.'
          : 'Commençons la session de définition du domaine « ${widget.domainName} ».',
      visible: false,
    );
  }

  Future<void> _send(String text, {bool visible = true}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    setState(() {
      if (visible) _messages.add(_ChatMsg('user', trimmed));
      _busy = true;
    });
    _scrollToEnd();
    try {
      final token = await _sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = _sync.uid;
      if (raw == null || raw.isEmpty || uid == null) {
        throw Exception('token indisponible');
      }
      // L'historique complet part au serveur (la session est côté client,
      // les FAITS sont côté Firestore via save_domain_definition).
      final history = [
        ..._messages.map((m) => {'role': m.role, 'content': m.content}),
        if (!visible) {'role': 'user', 'content': trimmed},
      ];
      final resp = await http
          .post(
            Uri.parse(_kChatUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $raw',
            },
            body: jsonEncode({
              'uid': uid,
              'domainName': widget.domainName,
              'messages': history,
            }),
          )
          .timeout(const Duration(seconds: 90));
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        throw Exception(body['error'] ?? 'HTTP ${resp.statusCode}');
      }
      if (mounted) {
        setState(() {
          _messages.add(_ChatMsg('assistant', body['message'] as String? ?? '…'));
        });
        if (body['finalized'] == true) _showResult();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _messages.add(_ChatMsg('assistant',
            'Connexion impossible — ta fiche est sauvegardée, reprends quand tu veux.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _showResult() {
    if (_stage == _Stage.result) return;
    setState(() => _stage = _Stage.result);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Domaine défini — je m\'en servirai chaque jour'),
      duration: Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stage == _Stage.intro
                  ? 'Définir un domaine'
                  : '${widget.domainName} — session de définition',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (_stage == _Stage.intro)
              Text('SESSION DE DÉFINITION · 15–20 MIN · UNE FOIS',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: cs.primary))
            else
              Text(_phaseLabel(),
                  style: TextStyle(
                      fontSize: 10.5, color: cs.onSurface.withOpacity(.5))),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        child: switch (_stage) {
          _Stage.intro => _intro(cs),
          _Stage.chat => _chat(cs),
          _Stage.result => _result(cs),
        },
      ),
    );
  }

  String _phaseLabel() {
    final d = _domain;
    if (d == null) return '1/3 · intention';
    if (d.intention == null || d.intention!.isEmpty) return '1/3 · intention';
    if (d.vitalMinimum.isEmpty) return '2/3 · minimum vital';
    return '3/3 · modalités & artefacts';
  }

  // ── 13a : l'entrée (le contrat) ──────────────────────────────────────────────

  /// Heures des 6 dernières semaines par activité du domaine (dossier 19a).
  /// Liste vide = domaine sans activités connues ; minutes à 0 = activité qui
  /// existe mais rien de loggué (la matière de la confrontation).
  List<({String name, int minutes})> _domainFacts() {
    final d = _domain;
    if (d == null) return const [];
    final since = DateTime.now().subtract(const Duration(days: 42));
    final now = DateTime.now();
    final out = <({String name, int minutes})>[];
    for (final a in widget.logic.state.activities) {
      if (a.deleted || a.domainId != d.id) continue;
      var min = 0;
      for (final s in widget.logic.state.sessions) {
        if (s.activityId != a.id || s.startAt.isBefore(since)) continue;
        min += (s.endAt ?? now).difference(s.startAt).inMinutes;
      }
      out.add((name: a.name, minutes: min));
    }
    out.sort((x, y) => y.minutes.compareTo(x.minutes));
    return out;
  }

  Widget _intro(ColorScheme cs) {
    final facts = _domainFacts();
    final vivant = facts.any((f) => f.minutes > 0);
    final vide = _domain != null && !vivant;
    return ListView(
      key: const ValueKey('intro'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color:
                    (vide ? cs.tertiary : cs.primary).withOpacity(.3)),
          ),
          child: Text(
            vivant
                ? 'Ici je ne pars pas de zéro — je te regarde travailler depuis six semaines. Voilà ce que je sais déjà. On va juste décider ce que tout ça sert.'
                : vide
                    ? 'Ici, rien — pas une heure, pas un bloc en six semaines. Ce vide est la première chose à regarder : il ne veut pas dire que ce domaine va bien. Une promesse : on n\'instrumente pas ta vie privée — on décide ce qui est non négociable, et je le défendrai.'
                    : 'Une vraie conversation, pas un formulaire. Je vais creuser jusqu\'à ce qu\'on tienne une intention qui te ressemble — puis on la rendra exécutable. Tout ce qu\'on décide est écrit et me servira chaque jour.',
            style: TextStyle(
                fontSize: 14, height: 1.5, color: cs.onSurface.withOpacity(.9)),
          ),
        ),
        // ── 19a : le dossier — les faits avant la conversation ────────────────
        if (vivant) ...[
          const SizedBox(height: 16),
          Text('LE DOSSIER — SIX SEMAINES DE FAITS',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurface.withOpacity(.4))),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final f in facts.take(2))
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (f.minutes == 0 ? cs.tertiary : cs.primary)
                              .withOpacity(.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${(f.minutes / 60).round()} h',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: f.minutes == 0
                                    ? cs.tertiary
                                    : cs.primary)),
                        Text('${f.name.toUpperCase()} · 6 SEM.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                                color: cs.onSurface.withOpacity(.5))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text('CE QU\'ON AURA À LA FIN',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.onSurface.withOpacity(.4))),
        const SizedBox(height: 10),
        _deliverable(cs, Icons.format_quote_rounded,
            'Une intention formulée avec tes mots — le « pourquoi » que je défendrai dans les arbitrages'),
        _deliverable(cs, Icons.horizontal_rule_rounded,
            'Un minimum vital mesurable — le plancher sous lequel on ne descend pas'),
        _deliverable(cs, Icons.article_outlined,
            'Des modalités concrètes (créneaux, fréquence) et les artefacts à générer'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(_resumable
              ? 'Reprendre — ${widget.domainName.toLowerCase()}'
              : 'Commencer — ${widget.domainName.toLowerCase()}'),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Reprendre plus tard — la session se sauvegarde à chaque étape',
            style:
                TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45)),
          ),
        ),
      ],
    );
  }

  Widget _deliverable(ColorScheme cs, IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withOpacity(.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: cs.onSurface.withOpacity(.85))),
          ),
        ],
      ),
    );
  }

  // ── 13b : la conversation + panneau fiche ────────────────────────────────────

  Widget _chat(ColorScheme cs) {
    return Column(
      key: const ValueKey('chat'),
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _messages.length + (_busy ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i >= _messages.length) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              return _bubble(cs, _messages[i]);
            },
          ),
        ),
        // Chips de validation rapide (cible tactile ≥ 44 px).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _quickChip(cs, 'On la garde', filled: true),
              const SizedBox(width: 8),
              _quickChip(cs, 'Reformuler'),
            ],
          ),
        ),
        _fichePanel(cs),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: TextField(
              controller: _inputCtrl,
              enabled: !_busy,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) {
                _inputCtrl.clear();
                _send(v);
              },
              decoration: InputDecoration(
                hintText: 'Réponds avec tes mots…',
                hintStyle: TextStyle(
                    fontSize: 13.5, color: cs.onSurface.withOpacity(.35)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: IconButton(
                  icon: Icon(Icons.send_rounded, size: 19, color: cs.primary),
                  onPressed: _busy
                      ? null
                      : () {
                          final v = _inputCtrl.text;
                          _inputCtrl.clear();
                          _send(v);
                        },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickChip(ColorScheme cs, String label, {bool filled = false}) {
    return SizedBox(
      height: 44,
      child: filled
          ? FilledButton(
              onPressed: _busy ? null : () => _send(label),
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 18)),
              child: Text(label, style: const TextStyle(fontSize: 13)),
            )
          : OutlinedButton(
              onPressed: _busy ? null : () => _send(label),
              style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 18)),
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
    );
  }

  Widget _bubble(ColorScheme cs, _ChatMsg m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primary.withOpacity(.14)
              : cs.surfaceContainerHighest.withOpacity(.45),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(m.content,
            style: TextStyle(
                fontSize: 14, height: 1.45, color: cs.onSurface.withOpacity(.92))),
      ),
    );
  }

  /// « La fiche se construit » — reflète l'état RÉEL du doc Firestore.
  Widget _fichePanel(ColorScheme cs) {
    final d = _domain;
    final intentionOk = d?.intention?.isNotEmpty == true;
    final vitalOk = d?.vitalMinimum.isNotEmpty == true;
    final modsOk =
        d != null && (d.modalities.isNotEmpty || d.wantedArtifacts.isNotEmpty);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(.35)),
        color: cs.primary.withOpacity(.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LA FICHE SE CONSTRUIT',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.primary)),
          const SizedBox(height: 8),
          _ficheRow(cs, intentionOk,
              intentionOk ? '« ${d!.intention} »' : 'Intention — en cours…',
              italic: intentionOk),
          _ficheRow(
              cs,
              vitalOk,
              vitalOk
                  ? d!.vitalMinimum.map((v) => v.label).join(' · ')
                  : 'Minimum vital${intentionOk ? ' — en cours…' : ''}'),
          _ficheRow(
              cs,
              modsOk,
              modsOk
                  ? [...d.modalities, ...d.wantedArtifacts].join(' · ')
                  : 'Modalités & artefacts'),
        ],
      ),
    );
  }

  Widget _ficheRow(ColorScheme cs, bool done, String text,
      {bool italic = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(done ? Icons.check_rounded : Icons.circle_outlined,
              size: 14,
              color: done ? cs.primary : cs.onSurface.withOpacity(.35)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontStyle: italic ? FontStyle.italic : null,
                color: done
                    ? cs.onSurface.withOpacity(.85)
                    : cs.onSurface.withOpacity(.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 13c : le résultat ────────────────────────────────────────────────────────

  Widget _result(ColorScheme cs) {
    final d = _domain;
    return ListView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (d != null) DomainCard(domain: d),
        const SizedBox(height: 18),
        if (d != null && d.wantedArtifacts.isNotEmpty) ...[
          Text('ON REND ÇA EXÉCUTABLE ?',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurface.withOpacity(.4))),
          const SizedBox(height: 10),
          for (final a in d.wantedArtifacts)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                // Génération structurée : la rangée pointe vers le CADRAGE
                // (14a/15a) — 3-4 paramètres pré-remplis depuis la fiche.
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ArtifactSetupScreen(
                      domain: d, kind: artifactKindFromLabel(a)),
                ));
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Générer $a',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.arrow_forward_rounded,
                        size: 16, color: cs.primary),
                  ],
                ),
              ),
            ),
        ],
        // Pont vers le flux du soir existant (check-in → poser demain + prep).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: cs.onSurface.withOpacity(.25)),
          ),
          child: Row(
            children: [
              Text('ce soir',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: cs.onSurface.withOpacity(.45))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Au check-in : on pose demain avec la première séance — et sa prep.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: cs.onSurface.withOpacity(.7)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: const Text('Terminé'),
        ),
      ],
    );
  }
}

// ── Fiche domaine (partagée : résultat 13c + vue « Mes domaines » 4a) ─────────

class DomainCard extends StatelessWidget {
  final Domain domain;
  final VoidCallback? onTap;
  // 18c : « session demain 18 h 30 » — prochaine session posée d'un domaine
  // `named` (nommé, pas défini). Null = pas de session trouvée cette semaine.
  final String? sessionLabel;
  const DomainCard(
      {super.key, required this.domain, this.onTap, this.sessionLabel});

  bool get _named => domain.definitionStatus == 'named';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color =
        domain.colorValue != null ? Color(domain.colorValue!) : cs.primary;
    final dateLabel = _named
        ? ''
        : domain.renegotiatedAt != null
            ? 'renégocié le ${_frDate(domain.renegotiatedAt!)}'
            : domain.definedAt != null
                ? 'défini le ${_frDate(domain.definedAt!)}'
                : domain.definitionStatus == 'draft'
                    ? 'session en cours'
                    : 'à définir';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Fiche `named` : en retrait (pas encore une fiche — juste un nom).
          border: Border.all(
              color: color.withOpacity(_named ? .45 : .35),
              style: BorderStyle.solid),
          color: _named ? Colors.transparent : color.withOpacity(.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(domain.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Text(dateLabel,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface.withOpacity(.45))),
              ],
            ),
            if (_named) ...[
              const SizedBox(height: 6),
              Text(
                sessionLabel != null
                    ? 'session $sessionLabel — rien à faire d\'ici là'
                    : 'session à poser — le coach n\'y touche pas d\'ici là',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withOpacity(.5)),
              ),
            ],
            if (domain.intention?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              // L'intention : LES MOTS DU USER — jamais reformulée par l'UI.
              Text('« ${domain.intention} »',
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.9))),
            ],
            if (domain.vitalMinimum.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Minimum vital : ${domain.vitalMinimum.map((v) => v.label).join(' · ')}',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(.6)),
              ),
            ],
            if (domain.modalities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Modalités : ${domain.modalities.join(' · ')}',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.6)),
                ),
              ),
            // Suivi déclaré (20c) : décidé aussi ce qu'on ne mesure pas.
            if (domain.tracking == 'declared')
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Suivi : déclaré au rapport du dimanche — pas de chrono, pas de blocs, pas de score',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.6)),
                ),
              ),
            if (domain.protectedSlots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Territoire défendu : ${domain.protectedSlots.map(_slotFr).join(' · ')} — la proposition n\'y posera jamais un bloc',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.6)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _slotFr(String code) {
    final p = code.split('_');
    const days = {
      'mon': 'lun', 'tue': 'mar', 'wed': 'mer', 'thu': 'jeu',
      'fri': 'ven', 'sat': 'sam', 'sun': 'dim',
    };
    const parts = {
      'morning': 'matin', 'afternoon': 'après-midi',
      'evening': 'soir', 'day': 'journée',
    };
    return '${days[p.first] ?? p.first} ${parts[p.length > 1 ? p[1] : ''] ?? ''}'
        .trim();
  }

  static String _frDate(DateTime d) {
    const months = [
      '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${months[d.month]}';
  }
}

// ── Vue « Mes domaines » (maquette 4a) ────────────────────────────────────────

class DomainsScreen extends StatefulWidget {
  final AppLogic logic;
  const DomainsScreen({super.key, required this.logic});

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  final _sessionSync = FirestoreSync();
  // 18c : domainId → « demain 18 h 30 » (prochaine session posée, 7 jours).
  Map<String, String> _sessionLabels = const {};

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _loadSessionLabels();
  }

  Future<void> _loadSessionLabels() async {
    final now = DateTime.now();
    final labels = <String, String>{};
    final days = await Future.wait(List.generate(7, (i) {
      final d = now.add(Duration(days: i));
      final ymd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return _sessionSync.fetchDailySchedule(ymd).catchError((_) => null);
    }));
    const weekdays = [
      'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
    ];
    for (var i = 0; i < days.length; i++) {
      final day = now.add(Duration(days: i));
      final dayName = i == 0
          ? 'aujourd\'hui'
          : i == 1
              ? 'demain'
              : weekdays[day.weekday - 1];
      for (final b in days[i]?.blocks ?? const <ScheduleBlock>[]) {
        if (b.kind != 'session' || b.domainId == null) continue;
        if (b.status == 'deleted' || b.status == 'done') continue;
        final p = b.startTime.split(':');
        final h = int.tryParse(p.first) ?? 0;
        final m = p.length > 1 && p[1] != '00' ? ' ${p[1]}' : '';
        labels.putIfAbsent(b.domainId!, () => '$dayName $h h$m');
      }
    }
    if (mounted) setState(() => _sessionLabels = labels);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sync = FirestoreSync();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes domaines',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: StreamBuilder<List<Domain>>(
        stream: sync.streamDomains(),
        builder: (ctx, snap) {
          final domains = (snap.data ?? logic.state.activeDomains)
              .where((d) => !d.deleted)
              .toList()
            // Fiches actives d'abord, puis en session, puis juste nommées.
            ..sort((a, b) => _statusRank(a).compareTo(_statusRank(b)));
          final defined = domains.where((d) => d.isDefined).toList();
          final named =
              domains.where((d) => d.definitionStatus == 'named').toList();
          return StreamBuilder<List<Artifact>>(
            stream: sync.streamArtifacts(),
            builder: (ctx2, artSnap) {
              final artifacts = artSnap.data ?? const <Artifact>[];
              return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // Onboarding (18a) : rien n'est encore nommé ni défini.
              if (domains.every((d) =>
                  d.definitionStatus == 'none' ||
                  d.definitionStatus == '')) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.flag_rounded, size: 16),
                  label: const Text('Nommer tes domaines — 2 min'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: () => Navigator.of(ctx)
                      .push(MaterialPageRoute(
                        builder: (_) => DomainOnboardingScreen(logic: logic),
                      ))
                      .then((_) => _loadSessionLabels()),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Nommer d\'abord, définir ensuite — le n° 1 tout de suite, les autres cette semaine.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5, color: cs.onSurface.withOpacity(.45)),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              for (final d in domains) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: DomainCard(
                    domain: d,
                    sessionLabel: _sessionLabels[d.id],
                    onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => DomainSessionScreen(
                          logic: logic, domainName: d.name),
                    )),
                  ),
                ),
                // Artefacts du domaine (plan, menu) — sources de blocs.
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final a in artifacts
                          .where((a) => a.domainId == d.id))
                        ActionChip(
                          avatar: Icon(Icons.article_outlined,
                              size: 14, color: cs.primary),
                          label: Text(a.title,
                              style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              Navigator.of(ctx).push(MaterialPageRoute(
                            builder: (_) => ArtifactViewScreen(
                                artifact: a, domain: d),
                          )),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('+ Définir un domaine avec Orion'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: () async {
                  final ctrl = TextEditingController();
                  final name = await showDialog<String>(
                    context: ctx,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Quel domaine ?',
                          style: TextStyle(fontSize: 16)),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            hintText: 'Santé, Business, Perso…'),
                        onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dctx),
                            child: const Text('Annuler')),
                        FilledButton(
                            onPressed: () =>
                                Navigator.pop(dctx, ctrl.text.trim()),
                            child: const Text('Commencer')),
                      ],
                    ),
                  );
                  if (name != null && name.isNotEmpty && ctx.mounted) {
                    Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => DomainSessionScreen(
                          logic: logic, domainName: name),
                    ));
                  }
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  // 18c : un domaine nommé n'existe pas encore pour le coach.
                  defined.isNotEmpty && named.isNotEmpty
                      ? 'Le coach travaille déjà avec ${defined.map((d) => d.name).join(' et ')} — les autres domaines s\'ajoutent sans rien casser.'
                      : 'Intention · minimum vital · modalités — la colonne vertébrale du coach.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(.45)),
                ),
              ),
            ],
              );
            },
          );
        },
      ),
    );
  }

  static int _statusRank(Domain d) => switch (d.definitionStatus) {
        'active' => 0,
        'draft' => 1,
        'suspended' => 2,
        'named' => 3,
        _ => 4,
      };
}
