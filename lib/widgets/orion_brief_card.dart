import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _kApi = 'https://orionbrief-dzos75b65q-uc.a.run.app';
const _kGold = Color(0xFFe8c94a);
const _kGoldDim = Color(0xFF8a7420);
const _kRisk = Color(0xFFE07B39);
const _kQuestion = Color(0xFF7AB8E5);
const _kLever = Color(0xFF8E7BE5);

const _kPrefFocus = 'orion_brief_focus';
const _kPrefBrief = 'orion_brief_cache';
const _kPrefBriefDate = 'orion_brief_cache_date';

// ── Model ────────────────────────────────────────────────────────────────────

class _Brief {
  final String date;
  final String focus;
  final String priorityAction;
  final String? risk;
  final String? question;
  final String? productivityLever;
  final String? feedback;

  const _Brief({
    required this.date,
    required this.focus,
    required this.priorityAction,
    this.risk,
    this.question,
    this.productivityLever,
    this.feedback,
  });

  factory _Brief.fromJson(Map<String, dynamic> j) => _Brief(
        date: j['date'] as String? ?? '',
        focus: j['focus'] as String? ?? '',
        priorityAction: j['priorityAction'] as String? ?? '',
        risk: j['risk'] as String?,
        question: j['question'] as String?,
        productivityLever: j['productivityLever'] as String?,
        feedback: j['feedback'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'focus': focus,
        'priorityAction': priorityAction,
        if (risk != null) 'risk': risk,
        if (question != null) 'question': question,
        if (productivityLever != null) 'productivityLever': productivityLever,
        if (feedback != null) 'feedback': feedback,
      };

  _Brief copyWith({String? feedback}) => _Brief(
        date: date,
        focus: focus,
        priorityAction: priorityAction,
        risk: risk,
        question: question,
        productivityLever: productivityLever,
        feedback: feedback ?? this.feedback,
      );
}

// ── History item model ────────────────────────────────────────────────────────

class _HistoryItem {
  final String date;
  final String focus;
  final String priorityAction;
  final String? risk;
  final String? question;
  final String? feedback;

  const _HistoryItem({
    required this.date,
    required this.focus,
    required this.priorityAction,
    this.risk,
    this.question,
    this.feedback,
  });

  factory _HistoryItem.fromJson(Map<String, dynamic> j) => _HistoryItem(
        date: j['date'] as String? ?? '',
        focus: j['focus'] as String? ?? '',
        priorityAction: j['priorityAction'] as String? ?? '',
        risk: j['risk'] as String?,
        question: j['question'] as String?,
        feedback: j['feedback'] as String?,
      );
}

// ── Card widget ───────────────────────────────────────────────────────────────

class OrionBriefCard extends StatefulWidget {
  const OrionBriefCard({super.key});

  @override
  State<OrionBriefCard> createState() => _OrionBriefCardState();
}

class _OrionBriefCardState extends State<OrionBriefCard>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _generating = false;
  bool _focusNotSet = false;
  bool _editingFocus = false;
  bool _offline = false;
  String? _error;

  String _focus = '';
  _Brief? _brief;
  bool _feedbackSent = false;

  final _focusCtrl = TextEditingController();

  late AnimationController _fadeCtrl;
  late List<Animation<double>> _fadeAnims;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnims = List.generate(3, (i) {
      final start = i * 0.2;
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _fadeCtrl,
          curve: Interval(start, (start + 0.4).clamp(0.0, 1.0), curve: Curves.easeOut),
        ),
      );
    });
    _init();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _focusCtrl.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedFocus = prefs.getString(_kPrefFocus) ?? '';
    final cachedBriefJson = prefs.getString(_kPrefBrief);
    final cachedBriefDate = prefs.getString(_kPrefBriefDate);
    final todayStr = _today();

    _focusCtrl.text = cachedFocus;
    _focus = cachedFocus;

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = !connectivity.contains(ConnectivityResult.none);

    if (!isOnline) {
      _offline = true;
      if (cachedBriefJson != null) {
        try {
          _brief = _Brief.fromJson(jsonDecode(cachedBriefJson) as Map<String, dynamic>);
        } catch (_) {}
      }
      if (mounted) setState(() => _loading = false);
      return;
    }

    // If today's brief is already cached, show it immediately then validate with server
    if (cachedBriefJson != null && cachedBriefDate == todayStr) {
      try {
        _brief = _Brief.fromJson(jsonDecode(cachedBriefJson) as Map<String, dynamic>);
        if (mounted) setState(() { _loading = false; });
        _fadeCtrl.forward(from: 0);
        // Still sync focus from server in background
        _syncFocusFromServer();
        return;
      } catch (_) {}
    }

    await _loadFromServer();
  }

  Future<void> _syncFocusFromServer() async {
    final idToken = await _getIdToken();
    if (idToken == null) return;
    try {
      final res = await http.post(
        Uri.parse(_kApi),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getFocus'}),
      );
      if (res.statusCode == 200) {
        final focus = (jsonDecode(res.body) as Map)['focus'] as String? ?? '';
        if (mounted && focus != _focus) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kPrefFocus, focus);
          setState(() {
            _focus = focus;
            _focusCtrl.text = focus;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadFromServer() async {
    if (mounted) setState(() { _loading = true; _error = null; _offline = false; });

    final idToken = await _getIdToken();
    if (idToken == null) {
      if (mounted) setState(() { _loading = false; _error = 'Non connecté'; });
      return;
    }

    try {
      // Get focus
      final fRes = await http.post(
        Uri.parse(_kApi),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getFocus'}),
      );
      final focus = (jsonDecode(fRes.body) as Map)['focus'] as String? ?? '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefFocus, focus);

      if (focus.trim().isEmpty) {
        if (mounted) setState(() { _loading = false; _focusNotSet = true; _editingFocus = true; _focus = focus; _focusCtrl.text = focus; });
        return;
      }

      _focus = focus;
      _focusCtrl.text = focus;

      // Get brief
      final bRes = await http.post(
        Uri.parse(_kApi),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getBrief'}),
      );
      if (bRes.statusCode == 200) {
        final b = _Brief.fromJson(jsonDecode(bRes.body) as Map<String, dynamic>);
        await prefs.setString(_kPrefBrief, jsonEncode(b.toJson()));
        await prefs.setString(_kPrefBriefDate, _today());
        if (mounted) setState(() { _loading = false; _brief = b; _focusNotSet = false; _feedbackSent = b.feedback != null; });
        _fadeCtrl.forward(from: 0);
      } else if (bRes.statusCode == 412) {
        if (mounted) setState(() { _loading = false; _focusNotSet = true; });
      } else {
        if (mounted) setState(() { _loading = false; _error = 'ORION est indisponible, réessaie dans quelques instants'; });
      }
    } catch (_) {
      // Network error — show cache if available
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kPrefBrief);
      if (cached != null) {
        try {
          final b = _Brief.fromJson(jsonDecode(cached) as Map<String, dynamic>);
          if (mounted) setState(() { _loading = false; _brief = b; _offline = true; _feedbackSent = b.feedback != null; });
          _fadeCtrl.forward(from: 0);
          return;
        } catch (_) {}
      }
      if (mounted) setState(() { _loading = false; _error = 'ORION est indisponible, réessaie dans quelques instants'; });
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveFocus() async {
    final newFocus = _focusCtrl.text.trim();
    if (newFocus.isEmpty) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;
    setState(() => _generating = true);
    try {
      await http.post(
        Uri.parse(_kApi),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'setFocus', 'focus': newFocus}),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefFocus, newFocus);
      // Invalidate cached brief so it regenerates
      await prefs.remove(_kPrefBriefDate);
      _focus = newFocus;
      _editingFocus = false;
      await _loadFromServer();
    } catch (_) {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _sendFeedback(String value) async {
    final brief = _brief;
    if (brief == null || _feedbackSent) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;
    try {
      await http.post(
        Uri.parse(_kApi),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'setFeedback', 'date': brief.date, 'feedback': value}),
      );
      final updated = brief.copyWith(feedback: value);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefBrief, jsonEncode(updated.toJson()));
      if (mounted) setState(() { _brief = updated; _feedbackSent = true; });
    } catch (_) {}
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrionHistoryScreen()),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(cs),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (_loading)
              _buildLoader(cs)
            else if (_offline && _brief == null)
              _buildOfflineEmpty(cs)
            else if (_error != null)
              _buildError(cs)
            else
              _buildContent(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, size: 14, color: _kGold),
        const SizedBox(width: 6),
        const Text(
          'ORION Stratège',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kGold, letterSpacing: 0.3),
        ),
        const Spacer(),
        if (_offline)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Hors ligne',
              style: TextStyle(fontSize: 10, color: cs.onErrorContainer, fontWeight: FontWeight.w600),
            ),
          ),
        if (!_offline && _brief != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openHistory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history, size: 13, color: cs.onSurface.withOpacity(.45)),
                const SizedBox(width: 4),
                Text(
                  'Historique',
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.45), fontWeight: FontWeight.w500),
                ),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGold.withOpacity(.7)),
        ),
        const SizedBox(width: 10),
        Text(
          'ORION analyse ta situation…',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45)),
        ),
      ]),
    );
  }

  Widget _buildOfflineEmpty(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Pas de connexion. Connecte-toi pour accéder à ton brief ORION.',
        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5), height: 1.5),
      ),
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_error!, style: TextStyle(fontSize: 12, color: cs.error, height: 1.5)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _loadFromServer,
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('Réessayer', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
        ),
      ],
    );
  }

  Widget _buildContent(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFocusBlock(cs),
        if (!_editingFocus) ...[
          const SizedBox(height: 14),
          if (_focusNotSet)
            Text(
              'Définis ton focus au-dessus pour générer ton brief quotidien.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45), height: 1.5, fontStyle: FontStyle.italic),
            )
          else if (_brief != null)
            _buildBriefBlock(cs),
        ],
      ],
    );
  }

  Widget _buildFocusBlock(ColorScheme cs) {
    if (_editingFocus || _brief == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TON FOCUS DU MOMENT',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: cs.onSurface.withOpacity(.4)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _focusCtrl,
            maxLines: 3,
            minLines: 2,
            maxLength: 280,
            decoration: InputDecoration(
              hintText: 'Ex : "Je lance ma formation avant fin juin. Tout converge vers ça."',
              hintStyle: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.3)),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _focusCtrl,
              builder: (_, val, __) => FilledButton(
                onPressed: (_generating || val.text.trim().isEmpty) ? null : _saveFocus,
                style: FilledButton.styleFrom(
                  backgroundColor: _kGold,
                  foregroundColor: Colors.black87,
                  disabledBackgroundColor: _kGoldDim,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: _generating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black54))
                    : const Text('Générer mon brief →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            if (_focus.isNotEmpty && _brief != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() { _editingFocus = false; _focusCtrl.text = _focus; }),
                child: Text('Annuler', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
              ),
            ],
          ]),
        ],
      );
    }

    // Compact focus display (tap to edit)
    return GestureDetector(
      onTap: () => setState(() => _editingFocus = true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FOCUS',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: cs.onSurface.withOpacity(.4)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _focus,
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.85), height: 1.45, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, size: 13, color: cs.onSurface.withOpacity(.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefBlock(ColorScheme cs) {
    final b = _brief!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BRIEF DU JOUR',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: _kGold),
        ),
        const SizedBox(height: 10),
        // Ligne urgente épinglée en tête (si présente) — la seule alerte du jour
        if (b.risk != null && b.risk!.isNotEmpty) ...[
          FadeTransition(
            opacity: _fadeAnims[1],
            child: _urgentBanner(cs, b.risk!),
          ),
          const SizedBox(height: 10),
        ],
        FadeTransition(
          opacity: _fadeAnims[0],
          child: _briefRow(cs, '→', 'Action prioritaire', b.priorityAction, _kGold),
        ),
        if (b.question != null && b.question!.isNotEmpty) ...[
          const SizedBox(height: 10),
          FadeTransition(
            opacity: _fadeAnims[2],
            child: _briefRow(cs, '?', 'Question stratégique', b.question!, _kQuestion),
          ),
        ],
        if (b.productivityLever != null && b.productivityLever!.isNotEmpty) ...[
          const SizedBox(height: 10),
          FadeTransition(
            opacity: _fadeAnims[2],
            child: _briefRow(cs, '📊', 'Levier du jour', b.productivityLever!, _kLever),
          ),
        ],
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 10),
        _buildFeedbackRow(cs),
      ],
    );
  }

  Widget _urgentBanner(ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _kRisk.withOpacity(.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRisk.withOpacity(.55), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠', style: TextStyle(fontSize: 14, color: _kRisk)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'À NE PAS RATER AUJOURD\'HUI',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _kRisk,
                      letterSpacing: 0.4),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(.9),
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _briefRow(ColorScheme cs, String icon, String label, String text, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.2), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: 13, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color.withOpacity(.8), letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.85), height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackRow(ColorScheme cs) {
    if (_feedbackSent || _brief?.feedback != null) {
      final fb = _brief?.feedback;
      return Text(
        fb == 'useful' ? '✓ Marqué utile' : '✗ Brief passé',
        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4)),
      );
    }
    return Row(
      children: [
        Text(
          'Ce brief était utile ?',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.55)),
        ),
        const SizedBox(width: 12),
        _feedbackBtn('👍', () => _sendFeedback('useful')),
        const SizedBox(width: 8),
        _feedbackBtn('👎', () => _sendFeedback('skip')),
      ],
    );
  }

  Widget _feedbackBtn(String emoji, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

// ── History Screen ────────────────────────────────────────────────────────────

class OrionHistoryScreen extends StatefulWidget {
  const OrionHistoryScreen({super.key});

  @override
  State<OrionHistoryScreen> createState() => _OrionHistoryScreenState();
}

class _OrionHistoryScreenState extends State<OrionHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<_HistoryItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _loading = false; _error = 'Non connecté'; });
      return;
    }
    final idToken = await user.getIdToken();
    try {
      final res = await http.post(
        Uri.parse(_kApi),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'history', 'limit': 30}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final briefs = (data['briefs'] as List<dynamic>? ?? [])
            .map((e) => _HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() { _loading = false; _items = briefs; });
      } else {
        setState(() { _loading = false; _error = 'Erreur ${res.statusCode}'; });
      }
    } catch (_) {
      setState(() { _loading = false; _error = 'ORION est indisponible, réessaie dans quelques instants'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 14, color: _kGold),
            SizedBox(width: 8),
            Text('Historique ORION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        centerTitle: true,
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGold),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 40, color: _kGold.withOpacity(.4)),
            const SizedBox(height: 12),
            Text(
              "Aucun brief pour l'instant",
              style: TextStyle(color: cs.onSurface.withOpacity(.5), fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Génère ton premier brief ORION depuis le dashboard.',
              style: TextStyle(color: cs.onSurface.withOpacity(.35), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _items.length,
      itemBuilder: (_, i) => _HistoryTile(item: _items[i], cs: cs),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  final _HistoryItem item;
  final ColorScheme cs;

  const _HistoryTile({required this.item, required this.cs});

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _expanded = false;

  String _formatDate(String date) {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        final months = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'août', 'sep', 'oct', 'nov', 'déc'];
        final month = int.parse(parts[1]);
        return '${parts[2]} ${months[month - 1]} ${parts[0]}';
      }
    } catch (_) {}
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cs = widget.cs;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.onSurface.withOpacity(.1)),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _formatDate(item.date),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kGold),
                  ),
                  if (item.feedback != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      item.feedback == 'useful' ? '✓' : '✗',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4)),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurface.withOpacity(.4),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.focus,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.6), fontStyle: FontStyle.italic),
                maxLines: _expanded ? null : 1,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _historyRow(cs, '→', item.priorityAction, _kGold),
                if (item.risk != null && item.risk!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _historyRow(cs, '⚠', item.risk!, _kRisk),
                ],
                if (item.question != null && item.question!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _historyRow(cs, '?', item.question!, _kQuestion),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyRow(ColorScheme cs, String icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: TextStyle(fontSize: 13, color: color)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.8), height: 1.5),
          ),
        ),
      ],
    );
  }
}
