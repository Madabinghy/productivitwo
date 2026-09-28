import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

// Vue « Agent ORION » (route plein écran derrière le menu ⋯) : brief du
// stratège, historique, configuration, journal des cycles.

// ── ORION Brief — Stratège quotidien ──────────────────────────────────────────

class _OrionBriefSection extends StatefulWidget {
  const _OrionBriefSection();
  @override
  State<_OrionBriefSection> createState() => _OrionBriefSectionState();
}

class _OrionBriefSectionState extends State<_OrionBriefSection> {
  static const _api = 'https://orionbrief-dzos75b65q-uc.a.run.app';
  static const _gold = kBPrimary; // ex-or : palette alignée sur le thème

  bool _loading = true;
  String _focus = '';
  Map<String, dynamic>? _brief;
  bool _editingFocus = false;
  bool _focusNotSet = false;
  String? _error;
  final _focusCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    super.dispose();
  }

  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final idToken = await _getIdToken();
    if (idToken == null) {
      setState(() {
        _loading = false;
        _error = 'Non connecté';
      });
      return;
    }
    try {
      // Get focus
      final fRes = await http.post(
        Uri.parse(_api),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'action': 'getFocus'}),
      );
      final focus = (jsonDecode(fRes.body) as Map)['focus'] as String? ?? '';
      _focus = focus;
      _focusCtrl.text = focus;

      if (focus.trim().isEmpty) {
        setState(() {
          _loading = false;
          _focusNotSet = true;
          _editingFocus = true;
        });
        return;
      }

      // Get brief
      final bRes = await http.post(
        Uri.parse(_api),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'action': 'getBrief'}),
      );
      if (bRes.statusCode == 200) {
        _brief = jsonDecode(bRes.body) as Map<String, dynamic>;
        setState(() {
          _loading = false;
          _focusNotSet = false;
        });
      } else if (bRes.statusCode == 412) {
        setState(() {
          _loading = false;
          _focusNotSet = true;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Erreur ${bRes.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveFocus() async {
    final newFocus = _focusCtrl.text.trim();
    if (newFocus.isEmpty) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;
    setState(() => _loading = true);
    try {
      await http.post(
        Uri.parse(_api),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'action': 'setFocus', 'focus': newFocus}),
      );
      _focus = newFocus;
      _editingFocus = false;
      // Force régénération du brief avec le nouveau focus
      await _loadAll();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFeedback(String value) async {
    final brief = _brief;
    if (brief == null) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;
    final date = brief['date'] as String?;
    if (date == null) return;
    try {
      await http.post(
        Uri.parse(_api),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode(
            {'action': 'setFeedback', 'date': date, 'feedback': value}),
      );
      setState(() {
        _brief = {...brief, 'feedback': value};
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _SidebarCard(
      title: 'ORION · Stratège',
      titleColor: _gold,
      icon: Icons.auto_awesome_outlined,
      cs: cs,
      child: _buildContent(cs),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: cs.onSurface.withOpacity(.3))),
          const SizedBox(width: 8),
          Text('Chargement…',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.4))),
        ]),
      );
    }
    if (_error != null) {
      return Text(_error!, style: TextStyle(fontSize: 12, color: cs.error));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Focus
        _buildFocusBlock(cs),
        const SizedBox(height: 14),
        // Brief
        if (_focusNotSet)
          Text(
            'Définis ton focus au-dessus pour activer ton brief quotidien.',
            style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(.45),
                height: 1.5,
                fontStyle: FontStyle.italic),
          )
        else if (_brief != null)
          _buildBriefBlock(cs),
      ],
    );
  }

  Widget _buildFocusBlock(ColorScheme cs) {
    if (_editingFocus) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TON FOCUS DU MOMENT',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurface.withOpacity(.4))),
          const SizedBox(height: 6),
          TextField(
            controller: _focusCtrl,
            maxLines: 3,
            minLines: 2,
            maxLength: 280,
            decoration: InputDecoration(
              hintText:
                  'Ex : "Je lance ma formation avant fin juin. Tout converge vers ça."',
              hintStyle:
                  TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.3)),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(
              onPressed: _saveFocus,
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black87,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Enregistrer',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (_focus.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() {
                  _editingFocus = false;
                  _focusCtrl.text = _focus;
                }),
                child: Text('Annuler',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(.5))),
              ),
            ],
          ]),
        ],
      );
    }

    return InkWell(
      onTap: () => setState(() => _editingFocus = true),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('TON FOCUS',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: cs.onSurface.withOpacity(.4))),
              const Spacer(),
              Icon(Icons.edit_outlined,
                  size: 11, color: cs.onSurface.withOpacity(.3)),
            ]),
            const SizedBox(height: 6),
            Text(_focus,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(.85),
                    height: 1.5,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefBlock(ColorScheme cs) {
    final b = _brief!;
    final priorityAction = b['priorityAction'] as String? ?? '';
    final risk = b['risk'] as String?;
    final question = b['question'] as String?;
    final feedback = b['feedback'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BRIEF DU JOUR',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: _gold)),
        const SizedBox(height: 10),
        _briefRow(cs, '→', 'Action prioritaire', priorityAction, _gold),
        if (risk != null && risk.isNotEmpty) ...[
          const SizedBox(height: 10),
          _briefRow(cs, '⚠', 'Risque', risk, const Color(0xFFE07B39)),
        ],
        if (question != null && question.isNotEmpty) ...[
          const SizedBox(height: 10),
          _briefRow(cs, '?', 'Question', question, const Color(0xFF7AB8E5)),
        ],
        const SizedBox(height: 14),
        // Feedback + historique
        Row(children: [
          if (feedback == null) ...[
            _feedbackBtn(cs, '✓ Utile', () => _sendFeedback('useful')),
            const SizedBox(width: 8),
            _feedbackBtn(cs, '✗ Passe', () => _sendFeedback('skip')),
          ] else
            Text(
              feedback == 'useful' ? '✓ Marqué utile' : '✗ Brief passé',
              style:
                  TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4)),
            ),
          const Spacer(),
          InkWell(
            onTap: _openHistory,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history,
                    size: 12, color: cs.onSurface.withOpacity(.5)),
                const SizedBox(width: 4),
                Text('Historique',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(.5),
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ]),
      ],
    );
  }

  Future<void> _openHistory() async {
    final idToken = await _getIdToken();
    if (idToken == null) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: _BriefHistoryView(idToken: idToken, api: _api),
        ),
      ),
    );
  }

  Widget _briefRow(
      ColorScheme cs, String icon, String label, String text, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.05),
        borderRadius: BorderRadius.circular(8),
        border:
            Border(left: BorderSide(color: color.withOpacity(.5), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: color)),
          ]),
          const SizedBox(height: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withOpacity(.85),
                  height: 1.45)),
        ],
      ),
    );
  }

  Widget _feedbackBtn(ColorScheme cs, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withOpacity(.65),
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}

// ── ORION Brief — Historique ─────────────────────────────────────────────────

class _BriefHistoryView extends StatefulWidget {
  final String idToken;
  final String api;
  const _BriefHistoryView({required this.idToken, required this.api});
  @override
  State<_BriefHistoryView> createState() => _BriefHistoryViewState();
}

class _BriefHistoryViewState extends State<_BriefHistoryView> {
  bool _loading = true;
  List<Map<String, dynamic>> _briefs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.post(
        Uri.parse(widget.api),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'action': 'history', 'limit': 30}),
      );
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Erreur ${res.statusCode}';
        });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _loading = false;
        _briefs = (data['briefs'] as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _fmtDate(String yyyymmdd) {
    try {
      final d = DateTime.parse(yyyymmdd);
      const m = [
        'jan',
        'fév',
        'mar',
        'avr',
        'mai',
        'juin',
        'juil',
        'aoû',
        'sep',
        'oct',
        'nov',
        'déc'
      ];
      const w = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
      return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
    } catch (_) {
      return yyyymmdd;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const gold = kBPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
          child: Row(children: [
            Icon(Icons.auto_awesome_outlined, size: 16, color: gold),
            const SizedBox(width: 8),
            Text('Historique ORION',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Fermer',
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _briefs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                                'Aucun brief sauvegardé pour le moment.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface.withOpacity(.4),
                                    fontStyle: FontStyle.italic)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _briefs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (_, i) =>
                              _briefCard(cs, gold, _briefs[i]),
                        ),
        ),
      ],
    );
  }

  Widget _briefCard(ColorScheme cs, Color gold, Map<String, dynamic> b) {
    final date = b['date'] as String? ?? '';
    final focus = b['focus'] as String?;
    final priorityAction = b['priorityAction'] as String? ?? '';
    final risk = b['risk'] as String?;
    final question = b['question'] as String?;
    final feedback = b['feedback'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_fmtDate(date),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gold,
                    letterSpacing: 0.3)),
            const Spacer(),
            if (feedback != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (feedback == 'useful' ? Colors.green : cs.onSurface)
                      .withOpacity(.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  feedback == 'useful' ? '✓ utile' : '✗ passé',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: feedback == 'useful'
                        ? Colors.green.shade700
                        : cs.onSurface.withOpacity(.4),
                  ),
                ),
              ),
          ]),
          if (focus != null && focus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Focus : "$focus"',
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withOpacity(.45))),
          ],
          const SizedBox(height: 10),
          _briefLine(cs, gold, '→', 'Action', priorityAction),
          if (risk != null && risk.isNotEmpty) ...[
            const SizedBox(height: 6),
            _briefLine(cs, const Color(0xFFE07B39), '⚠', 'Risque', risk),
          ],
          if (question != null && question.isNotEmpty) ...[
            const SizedBox(height: 6),
            _briefLine(cs, const Color(0xFF7AB8E5), '?', 'Question', question),
          ],
        ],
      ),
    );
  }

  Widget _briefLine(
      ColorScheme cs, Color color, String icon, String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          alignment: Alignment.center,
          child: Text(icon,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withOpacity(.85),
                  height: 1.5)),
        ),
      ],
    );
  }
}

// ── Peintre ligne pointillée ──────────────────────────────────────────────────

// ── Sidebar widgets ───────────────────────────────────────────────────────────

class _SidebarCard extends StatelessWidget {
  final String title;
  final Color? titleColor;
  final IconData icon;
  final ColorScheme cs;
  final Widget child;

  const _SidebarCard({
    required this.title,
    required this.icon,
    required this.cs,
    required this.child,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = titleColor ?? cs.onSurface.withOpacity(0.65);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ── Vue ORION ─────────────────────────────────────────────────────────────────

class OrionView extends StatefulWidget {
  final FirestoreSync sync;
  const OrionView({super.key, required this.sync});

  @override
  State<OrionView> createState() => OrionViewState();
}

class OrionViewState extends State<OrionView> {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _config;
  int _runCount = 0;
  bool _loading = true;
  bool _triggering = false;
  final _customCtrl = TextEditingController();

  static const _webhookUrl = 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';

  // Actions pré-établies
  // taskId non vide = déterministe ($0), need non vide = LLM (coût API)
  static const _presets = [
    (
      icon: '📋',
      label: 'Analyser mes retards',
      taskId: 'overdue_summary',
      need: ''
    ),
    (
      icon: '📅',
      label: 'Deadlines de la semaine',
      taskId: 'weekly_deadlines',
      need: ''
    ),
    (
      icon: '🗄',
      label: 'Archiver projets inactifs',
      taskId: 'archive_inactive',
      need: ''
    ),
    (
      icon: '📊',
      label: 'Rapport de progression',
      taskId: 'progress_report',
      need: ''
    ),
    (
      icon: '🧹',
      label: 'Nettoyer messages expirés',
      taskId: 'clean_expired',
      need: ''
    ),
    (
      icon: '🎯',
      label: 'Bilan de semaine',
      taskId: '',
      need:
          'Fais un bilan de ma semaine et propose des ajustements pour la suivante'
    ),
    (
      icon: '⚡',
      label: 'Optimiser plan du jour',
      taskId: '',
      need:
          'Optimise mon plan du jour en fonction de mes priorités et deadlines'
    ),
    (
      icon: '🔗',
      label: 'Lier objectifs et tâches',
      taskId: '',
      need: 'Lie mes objectifs GTD aux tâches Gantt correspondantes'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = widget.sync.uid;
      if (uid == null) return;

      final tokens = await widget.sync.fetchApiTokens();
      final token = tokens.where((t) => t.active).firstOrNull?.rawToken ?? '';

      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users/$uid/orion_logs')
            .orderBy('cycleAt', descending: true)
            .limit(15)
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/assistant_messages')
            .orderBy('targetDate', descending: true)
            .limit(30)
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/orion_config')
            .doc('main')
            .get(),
        // Compteur via HTTP (orion_runs est hors users/{uid}, règles Firestore restrictives)
        if (token.isNotEmpty)
          http.get(Uri.parse(
              'https://orionruncount-dzos75b65q-uc.a.run.app?uid=$uid&token=$token'))
        else
          Future.value(null),
      ]);

      final logsSnap = results[0] as QuerySnapshot;
      final msgsSnap = results[1] as QuerySnapshot;
      final configSnap = results[2] as DocumentSnapshot;
      final countResp = results[3];

      int runCount = 0;
      if (countResp is http.Response && countResp.statusCode == 200) {
        final data = jsonDecode(countResp.body) as Map<String, dynamic>;
        runCount = (data['count'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _logs = logsSnap.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
          _messages = msgsSnap.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
          _config = configSnap.exists
              ? configSnap.data() as Map<String, dynamic>
              : null;
          _runCount = runCount;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerWithPreset(
      {required String taskId, required String need}) async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.rawToken;
    if (uid == null || token == null) return;

    final isDeterministic = taskId.isNotEmpty;
    setState(() => _triggering = true);
    try {
      final body = isDeterministic
          ? {'uid': uid, 'token': token, 'taskId': taskId}
          : {'uid': uid, 'token': token, 'userNeeds': need};
      final url = isDeterministic
          ? 'https://orionwebhook-dzos75b65q-uc.a.run.app'
          : _webhookUrl;
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200 && mounted) {
        final label = isDeterministic
            ? taskId
            : need.substring(0, need.length.clamp(0, 40));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isDeterministic
                ? 'Tâche ORION exécutée : $label'
                : 'ORION activé (LLM) : $label…'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _triggering = false);
  }

  Future<void> _triggerNow() async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.rawToken;
    if (uid == null || token == null) return;

    setState(() => _triggering = true);
    try {
      final resp = await http.post(
        Uri.parse('https://orionwebhook-dzos75b65q-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cycle ORION déclenché'),
              behavior: SnackBarBehavior.floating),
        );
        await Future.delayed(const Duration(seconds: 2));
        _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _triggering = false);
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    final pendingMsgs =
        _messages.where((m) => m['status'] == 'pending').toList();
    final shownMsgs = _messages.where((m) => m['status'] == 'shown').toList();
    final otherMsgs = _messages
        .where((m) => m['status'] != 'pending' && m['status'] != 'shown')
        .toList();

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: cs.onSurface.withOpacity(0.45))),
        );

    Widget msgChip(String status) {
      final colors = {
        'pending': Colors.blue,
        'shown': Colors.green,
        'dismissed': Colors.orange,
        'expired': Colors.grey,
      };
      final c = colors[status] ?? Colors.grey;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(status,
            style:
                TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
          children: [
            // ── Brief du stratège (ex-carte Focus — lot 5 : tout ORION ici) ─
            const _OrionBriefSection(),
            const SizedBox(height: 20),
            // ── En-tête ──────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: cs.primaryContainer, shape: BoxShape.circle),
                child:
                    Icon(Icons.smart_toy_outlined, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Agent ORION',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('$_runCount / 50 activations aujourd\'hui',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
              ]),
              const SizedBox(width: 12),
              // Badge plan tarifaire
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Gratuit ',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.7))),
                    TextSpan(
                        text: '∞',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary)),
                    TextSpan(
                        text: '  ·  Pro ',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.5))),
                    TextSpan(
                        text: '5/j',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withOpacity(0.7))),
                  ]),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_outlined, size: 14),
                label: const Text('Rafraîchir'),
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _triggering
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_outlined, size: 16),
                label: const Text('Déclencher'),
                onPressed: _triggering ? null : _triggerNow,
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _runCount / 50,
                minHeight: 4,
                backgroundColor: cs.onSurface.withOpacity(0.08),
                color: _runCount >= 50 ? cs.error : cs.primary,
              ),
            ),

            // ── Comment ça marche ────────────────────────────────────────
            const SizedBox(height: 20),
            const _OrionHowItWorksCard(),

            // ── Config actuelle ───────────────────────────────────────────
            if (_config != null) ...[
              const SizedBox(height: 24),
              sectionLabel('INSTRUCTIONS ACTUELLES'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((_config!['userNeeds'] as String? ?? '')
                          .isNotEmpty) ...[
                        Text('Besoins :',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withOpacity(0.5))),
                        const SizedBox(height: 4),
                        Text(_config!['userNeeds'] as String,
                            style: const TextStyle(fontSize: 14)),
                      ],
                      if ((_config!['userReply'] as String? ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                            'Dernière réponse (${_config!['replyTimestamp'] ?? ''}) :',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withOpacity(0.5))),
                        const SizedBox(height: 4),
                        Text(_config!['userReply'] as String,
                            style: TextStyle(fontSize: 14, color: cs.primary)),
                      ],
                    ]),
              ),
            ],

            // ── Actions pré-établies ─────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('ACTIONS RAPIDES'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets
                  .map((p) => ActionChip(
                        avatar:
                            Text(p.icon, style: const TextStyle(fontSize: 14)),
                        label:
                            Text(p.label, style: const TextStyle(fontSize: 13)),
                        backgroundColor: p.taskId.isNotEmpty
                            ? Colors.green.withOpacity(0.08)
                            : cs.surfaceContainerHighest.withOpacity(0.5),
                        side: p.taskId.isNotEmpty
                            ? BorderSide(color: Colors.green.withOpacity(0.3))
                            : null,
                        onPressed: _triggering
                            ? null
                            : () => _triggerWithPreset(
                                taskId: p.taskId, need: p.need),
                      ))
                  .toList(),
            ),

            // ── Demande libre ────────────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('DEMANDE LIBRE'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _customCtrl,
                    enabled: !_triggering,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText:
                          'Ex : Crée un projet "Lancement produit" avec 3 phases, analyse mes retards…',
                      hintStyle: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(.4)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isEmpty) return;
                      _triggerWithPreset(taskId: '', need: t);
                      _customCtrl.clear();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: _triggering
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Envoyer'),
                  onPressed: _triggering
                      ? null
                      : () {
                          final t = _customCtrl.text.trim();
                          if (t.isEmpty) return;
                          _triggerWithPreset(taskId: '', need: t);
                          _customCtrl.clear();
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),

            // ── Logs des cycles récents ───────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('CYCLES RÉCENTS (${_logs.length})'),
            if (_logs.isEmpty)
              Text('Aucun cycle enregistré',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.4),
                      fontStyle: FontStyle.italic))
            else
              for (final log in _logs) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: ExpansionTile(
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    title: Row(children: [
                      Text(_fmtTs(log['cycleAt']),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      const SizedBox(width: 10),
                      if (log['skipped'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: cs.errorContainer.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('skippé',
                              style: TextStyle(fontSize: 10, color: cs.error)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('${log['pushed'] ?? 0} message(s)',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    subtitle: (log['userNeeds'] as String? ?? '').isNotEmpty
                        ? Text(
                            '"${(log['userNeeds'] as String).substring(0, ((log['userNeeds'] as String).length).clamp(0, 60))}…"',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)
                        : null,
                    children: [
                      if (log['skipped'] == true &&
                          log['skippedReason'] != null)
                        Text(log['skippedReason'] as String,
                            style: TextStyle(fontSize: 13, color: cs.error)),
                      for (final action in (log['actions'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• $action',
                              style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ],

            // ── Messages ORION ────────────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('MESSAGES ORION (${_messages.length})'),
            if (_messages.isEmpty)
              Text('Aucun message',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.4),
                      fontStyle: FontStyle.italic))
            else
              for (final group in [
                ('EN ATTENTE', pendingMsgs),
                ('AFFICHÉS', shownMsgs),
                ('AUTRES', otherMsgs),
              ]) ...[
                if ((group.$2).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(group.$1,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: cs.onSurface.withOpacity(0.4))),
                  ),
                  for (final msg in group.$2)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                            left: BorderSide(
                                color: cs.primary.withOpacity(0.4), width: 3)),
                      ),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(msg['text'] as String? ?? '',
                                        style: const TextStyle(fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Text(msg['targetDate'] as String? ?? '',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSurface
                                                  .withOpacity(0.45))),
                                      const SizedBox(width: 8),
                                      Text(
                                          'condition: ${(msg['condition'] as Map?)?.entries.map((e) => '${e.key}=${e.value}').join(', ') ?? ''}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSurface
                                                  .withOpacity(0.4))),
                                    ]),
                                  ]),
                            ),
                            const SizedBox(width: 8),
                            msgChip(msg['status'] as String? ?? ''),
                          ]),
                    ),
                ],
              ],
          ],
        ),
      ),
    );
  }
}

// ── Comment ça marche — ORION ─────────────────────────────────────────────────

class _OrionHowItWorksCard extends StatefulWidget {
  const _OrionHowItWorksCard();

  @override
  State<_OrionHowItWorksCard> createState() => _OrionHowItWorksCardState();
}

class _OrionHowItWorksCardState extends State<_OrionHowItWorksCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          // ── Header cliquable ──────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded,
                      size: 16, color: cs.primary.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Comment ça marche ?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────
          if (_expanded) ...[
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Schéma 3 acteurs
                  LayoutBuilder(builder: (ctx, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final actors = [
                      _OrionActor(
                        icon: '✦',
                        iconColor: const Color(0xFF6366f1),
                        title: 'Claude',
                        subtitle: 'claude.ai · Claude Desktop',
                        description:
                            'Tu lui parles en langage naturel. Via MCP, il lit et modifie tes données directement : crée des projets, planifie tes journées, gère tes objectifs.',
                        cs: cs,
                      ),
                      _OrionActor(
                        icon: '◉',
                        iconColor: const Color(0xFF10b981),
                        title: 'ORION',
                        subtitle: 'Agent autonome · toutes les 6h',
                        description:
                            'Tourne en arrière-plan sans que tu aies à lui demander. Il analyse ton contexte, détecte tes retards et te pousse des messages actionnables sur iOS.',
                        cs: cs,
                      ),
                      _OrionActor(
                        icon: '⬡',
                        iconColor: const Color(0xFF8b5cf6),
                        title: 'App web',
                        subtitle: 'Projets · Documents · Pilotage',
                        description:
                            'Ton tableau de bord Gantt. Tu peux aussi déclencher ORION manuellement, voir ses logs et configurer ses instructions depuis ici.',
                        cs: cs,
                      ),
                    ];

                    return narrow
                        ? Column(
                            children: actors
                                .map((a) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: a,
                                    ))
                                .toList(),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: actors[0]),
                              _Arrow(cs: cs),
                              Expanded(child: actors[1]),
                              _Arrow(cs: cs),
                              Expanded(child: actors[2]),
                            ],
                          );
                  }),

                  const SizedBox(height: 20),

                  // Firestore — socle commun
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFf97316).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFf97316).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Text('🗄', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Firestore — tes données, partagées en temps réel',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Domaines · Activités · Projets Gantt · Plan du jour · Messages ORION',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withOpacity(0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Flux en 4 étapes
                  Text(
                    'Le flux en pratique',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.55),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final step in [
                    (
                      '1',
                      'Tu configures tes données',
                      'Depuis l\'app iOS ou en demandant à Claude de le faire.'
                    ),
                    (
                      '2',
                      'ORION analyse toutes les 6h',
                      'Il lit ton contexte complet et génère 1 à 3 messages ciblés.'
                    ),
                    (
                      '3',
                      'Tu reçois une notification push',
                      'Le message apparaît dans l\'app iOS avec une action directe.'
                    ),
                    (
                      '4',
                      'Tu peux aussi déclencher manuellement',
                      'Via les actions rapides ci-dessous ou en activant depuis iOS.'
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(top: 1, right: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              step.$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step.$2,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(step.$3,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withOpacity(0.5))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrionActor extends StatelessWidget {
  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;
  final ColorScheme cs;

  const _OrionActor({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon,
                style: TextStyle(
                    fontSize: 16,
                    color: iconColor,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: iconColor.withOpacity(0.8),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(description,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.55),
                  height: 1.5)),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final ColorScheme cs;
  const _Arrow({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Icon(Icons.sync_alt_rounded,
          size: 18, color: cs.onSurface.withOpacity(0.2)),
    );
  }
}
