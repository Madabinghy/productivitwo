import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/pro_manager.dart';
import 'package:productivitwo_v1/widgets/paywall_sheet.dart';

// Palette ORION
const _bg = Color(0xFF0f0f0f);
const _surface = Color(0xFF181818);
const _surface2 = Color(0xFF1e1e1e);
const _gold = Color(0xFFe8c94a);
const _goldDim = Color(0xFF8a7420);
const _border = Color(0xFF2a2a2a);
const _muted = Color(0xFF747070);
const _text = Color(0xFFf0ece0);

const _webhookBase = 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';
const _countUrl = 'https://orionruncount-dzos75b65q-uc.a.run.app';

const _kLimitFree = 1;   // Gratuit : 1 activation/jour
const _kLimitPro  = 30;  // Pro : 30 activations/jour (test)

class OrionScreen extends StatefulWidget {
  final FirestoreSync sync;

  final bool embedded;

  const OrionScreen({super.key, required this.sync, this.embedded = false});

  static void show(BuildContext context, FirestoreSync sync) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrionScreen(sync: sync),
    ));
  }

  @override
  State<OrionScreen> createState() => _OrionScreenState();
}

class _OrionScreenState extends State<OrionScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _activating = false;

  int _runCount = 0;
  String _userNeeds = '';
  String? _activeToken;
  String? _error;

  final _replyCtrl = TextEditingController();
  final _needsCtrl = TextEditingController();

  String? _uid;
  List<_OrionMessage> _replyMessages = [];   // clarifications sans limite
  List<_OrionMessage> _messages = [];        // messages normaux, max 5

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _load();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _replyCtrl.dispose();
    _needsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = widget.sync.uid;
      if (uid == null) throw Exception('Non connecté');
      _uid = uid;

      final tokens = await widget.sync.fetchApiTokens();
      final activeTokens = tokens.where((t) => t.active).toList();
      if (activeTokens.isEmpty) {
        // Aucun token actif — on en crée un automatiquement
        final created = await widget.sync.ensureOnboardingToken();
        _activeToken = created.rawToken;
      } else {
        _activeToken = activeTokens.first.rawToken;
      }

      final futures = <Future>[
        FirebaseFirestore.instance
            .collection('users/$uid/orion_config')
            .doc('main')
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/assistant_messages')
            .where('status', isEqualTo: 'shown')
            .limit(20)
            .get(),
        if (_activeToken != null && _activeToken!.isNotEmpty)
          http.get(Uri.parse('$_countUrl?uid=$uid&token=$_activeToken'))
        else
          Future.value(null),
      ];

      final results = await Future.wait(futures);

      final configSnap = results[0] as DocumentSnapshot;
      final msgsSnap = results[1] as QuerySnapshot;

      if (configSnap.exists) {
        final d = configSnap.data() as Map<String, dynamic>;
        _userNeeds = (d['userNeeds'] as String?) ?? '';
        _needsCtrl.text = _userNeeds;
      }

      final allMessages = msgsSnap.docs.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        return _OrionMessage(
          id: d['id'] as String? ?? doc.id,
          text: d['text'] as String? ?? '',
          characterName: d['characterName'] as String? ?? 'ORION',
          status: d['status'] as String? ?? 'pending',
          targetDate: d['targetDate'] as String? ?? '',
          shownAt: _toDate(d['shownAt']),
          createdAt: _toDate(d['createdAt']),
          requiresReply: d['requiresReply'] as bool? ?? false,
        );
      }).toList();

      allMessages.sort((a, b) {
        final da = a.shownAt ?? a.createdAt ?? DateTime(0);
        final db = b.shownAt ?? b.createdAt ?? DateTime(0);
        return db.compareTo(da);
      });

      _replyMessages = allMessages.where((m) => m.requiresReply).toList();
      _messages = allMessages.where((m) => !m.requiresReply).take(5).toList();

      if (results.length > 2 && results[2] is http.Response) {
        final resp = results[2] as http.Response;
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          _runCount = (data['count'] as int?) ?? 0;
        }
      }
    } catch (e) {
      _error = _friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _activate() async {
    final uid = widget.sync.uid;
    if (uid == null || _activeToken == null || _activeToken!.isEmpty) {
      setState(() => _error = 'Aucun token API actif. Configure-en un via Tokens API.');
      return;
    }

    final isPro = ProManager.isPro;
    final limit = isPro ? _kLimitPro : _kLimitFree;
    if (_runCount >= limit) {
      setState(() => _error = isPro
          ? 'Limite journalière atteinte ($limit/jour).'
          : 'Limite journalière atteinte ($limit/jour). Passe à Pro pour continuer.');
      return;
    }

    setState(() {
      _activating = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse(_webhookBase),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'uid': uid,
          'token': _activeToken,
          'userNeeds': _needsCtrl.text.trim(),
          'userReply': _replyCtrl.text.trim(),
        }),
      );

      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        final pushed = data['pushed'] as int? ?? 0;
        final skipped = data['skipped'] as bool? ?? false;
        _replyCtrl.clear();
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              skipped
                  ? 'Limite atteinte — cycle ignoré'
                  : 'ORION a généré $pushed message${pushed > 1 ? 's' : ''}',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _surface2,
          ));
        }
      } else {
        setState(
            () => _error = data['error']?.toString() ?? 'Erreur inconnue');
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    }
    if (mounted) setState(() => _activating = false);
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ProManager.notifier,
      builder: (context, isPro, _) {
        final limitReached = !isPro && _runCount >= _kLimitFree;

        final content = _loading
            ? const Center(child: CircularProgressIndicator(color: _gold))
            : Column(
                children: [
                  Expanded(child: _buildBody(isPro)),
                  _buildReplyBar(isPro, limitReached),
                ],
              );

        if (widget.embedded) {
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Container(color: _bg, child: content),
          );
        }

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            backgroundColor: _bg,
            resizeToAvoidBottomInset: true,
            appBar: _buildAppBar(),
            body: content,
          ),
        );
      },
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      foregroundColor: _text,
      elevation: 0,
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: _pulseAnim.value,
              child: const Text(
                '◉',
                style: TextStyle(color: _gold, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'ORION',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.5,
              color: _gold,
            ),
          ),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: _border),
      ),
    );
  }

  Widget _buildBody(bool isPro) {
    final isFirstLaunch = _userNeeds.isEmpty && _messages.isEmpty;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        _StatusCard(isPro: isPro, runCount: _runCount),
        const SizedBox(height: 10),
        const _TipCard(),

        if (isFirstLaunch) ...[
          const SizedBox(height: 16),
          _OnboardingCard(
            needsDone: _userNeeds.isNotEmpty,
            activateDone: _runCount > 0,
            messagesDone: _messages.isNotEmpty,
          ),
        ],

        const SizedBox(height: 20),
        _SectionLabel('INSTRUCTIONS PERMANENTES'),
        const SizedBox(height: 4),
        const Text(
          'Lues à chaque cycle automatique (toutes les 6h)',
          style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: _muted),
        ),
        const SizedBox(height: 8),
        _buildNeedsField(),

        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _error!),
        ],

        const SizedBox(height: 28),
        _SectionLabel('MESSAGES ORION'),
        const SizedBox(height: 12),

        if (_replyMessages.isEmpty && _messages.isEmpty)
          _buildEmptyState()
        else ...[
          if (_replyMessages.isNotEmpty) ...[
            _SectionLabel('EN ATTENTE DE TA RÉPONSE (${_replyMessages.length})'),
            const SizedBox(height: 8),
            for (final m in _replyMessages) _MessageCard(message: m, sync: widget.sync, uid: _uid ?? ''),
            const SizedBox(height: 16),
          ],
          if (_messages.isNotEmpty) ...[
            if (_replyMessages.isNotEmpty) _SectionLabel('RÉCENTS'),
            if (_replyMessages.isNotEmpty) const SizedBox(height: 8),
            for (final m in _messages) _MessageCard(message: m, sync: widget.sync, uid: _uid ?? ''),
          ],
        ],
      ],
    );
  }

  Widget _buildNeedsField() {
    return TextField(
      controller: _needsCtrl,
      maxLines: 3,
      textInputAction: TextInputAction.done,
      onEditingComplete: () => FocusScope.of(context).unfocus(),
      style: const TextStyle(
          fontFamily: 'monospace', fontSize: 13, color: _text, height: 1.6),
      decoration: InputDecoration(
        hintText:
            'Ex: Rappelle-moi mes deadlines. Sois bref et actionnable.',
        hintStyle: const TextStyle(
            fontFamily: 'monospace', fontSize: 12, color: _muted),
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: const [
          Text('◉',
              style: TextStyle(color: _muted, fontSize: 28),
              textAlign: TextAlign.center),
          SizedBox(height: 12),
          Text(
            'Aucun message pour l\'instant.',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 13, color: _muted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Active ORION pour recevoir tes premiers conseils.',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: _muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar(bool isPro, bool limitReached) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safePadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, (bottomInset > 0 ? bottomInset : safePadding) + 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Réponse ponctuelle — envoyée au prochain cycle, puis effacée',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: _muted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replyCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _activating ? null : _activate(),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13, color: _text),
                  decoration: InputDecoration(
                    hintText: 'Ex : le projet X est repoussé, ignore-le…',
                    hintStyle: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, color: _muted),
                    filled: true,
                    fillColor: _surface2,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _gold, width: 1.5),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ActivateButton(
                activating: _activating,
                limitReached: limitReached,
                onTap: _activating || limitReached ? null : _activate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────────────────────

// ── Astuce MCP ────────────────────────────────────────────────────────────────

class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _goldDim.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✦', style: TextStyle(color: _gold, fontSize: 11)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ASTUCE — Connecte Claude Desktop à Productivitwo Web via MCP '
              '(menu ⋮ → Tokens API) pour piloter tes projets directement '
              'depuis claude.ai/Productivitwo Web, sans passer par ORION et '
              'sans limite quotidienne.',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: _muted,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte de statut ────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool isPro;
  final int runCount;

  const _StatusCard({required this.isPro, required this.runCount});

  @override
  Widget build(BuildContext context) {
    final limit = isPro ? _kLimitPro : _kLimitFree;
    final progress = (runCount / limit).clamp(0.0, 1.0);
    final barColor = progress >= 1.0 ? const Color(0xFFcf6679) : _gold;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PlanBadge(isPro: isPro),
              const Spacer(),
              Text(
                '$runCount / $limit activations aujourd\'hui',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: _border,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isPro
                ? '$_kLimitPro activations/jour · ORION tourne toutes les 6h.'
                : '$_kLimitFree activation/jour en version gratuite.\nPasse à Pro pour $_kLimitPro activations/jour.',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: _muted,
              height: 1.65,
            ),
          ),
          if (!isPro) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => showPaywallSheet(context),
              child: const Text(
                'Passer à Pro →',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _gold,
                  decoration: TextDecoration.underline,
                  decorationColor: _gold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  final bool isPro;
  const _PlanBadge({required this.isPro});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPro ? _gold.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPro ? _gold.withOpacity(0.35) : _border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPro) ...[
            const Text('★ ',
                style: TextStyle(color: _gold, fontSize: 9)),
          ],
          Text(
            isPro ? 'PRO' : 'GRATUIT',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isPro ? _gold : _muted,
            ),
          ),
          if (!isPro) ...[
            const Text(' · ∞',
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9, color: _muted)),
          ],
        ],
      ),
    );
  }
}

// ── Onboarding card ────────────────────────────────────────────────────────────

class _OnboardingCard extends StatelessWidget {
  final bool needsDone;
  final bool activateDone;
  final bool messagesDone;

  const _OnboardingCard({
    required this.needsDone,
    required this.activateDone,
    required this.messagesDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '◉  Bienvenue sur ORION',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _gold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'ORION est ton agent IA autonome. Il analyse ton contexte, anticipe tes besoins et te pousse des messages actionnables — sans que tu aies à lui demander.',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: _text,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 16),
          _Step(n: '1', label: 'Décris tes besoins ci-dessous', done: needsDone),
          _Step(n: '2', label: 'Appuie sur "Activer ORION"', done: activateDone),
          _Step(n: '3', label: 'Reçois tes premiers conseils', done: messagesDone),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String label;
  final bool done;

  const _Step({required this.n, required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _gold.withOpacity(0.12) : Colors.transparent,
              border: Border.all(color: done ? _gold : _border),
            ),
            child: done
                ? const Icon(Icons.check, size: 11, color: _gold)
                : Text(
                    n,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 9, color: _muted),
                  ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: done ? _text : _muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message card ───────────────────────────────────────────────────────────────

class _OrionMessage {
  final String id;
  final String text;
  final String characterName;
  final String status;
  final String targetDate;
  final DateTime? shownAt;
  final DateTime? createdAt;

  final bool requiresReply;

  const _OrionMessage({
    required this.id,
    required this.text,
    required this.characterName,
    required this.status,
    required this.targetDate,
    this.shownAt,
    this.createdAt,
    this.requiresReply = false,
  });
}

class _MessageCard extends StatelessWidget {
  final _OrionMessage message;
  final FirestoreSync sync;
  final String uid;
  const _MessageCard({required this.message, required this.sync, required this.uid});

  @override
  Widget build(BuildContext context) {
    final date = message.shownAt ?? message.createdAt;
    final dateStr = date != null ? _fmt(date) : message.targetDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _muted,
                  ),
                ),
                Text(
                  message.characterName,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: _gold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 10, color: _muted),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => FirebaseFirestore.instance
                      .collection('users/$uid/assistant_messages')
                      .doc(message.id)
                      .update({'status': 'dismissed'}),
                  child: const Icon(Icons.close, size: 14, color: _muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message.text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.65,
                color: _text,
              ),
            ),
            if (message.requiresReply) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _showReplySheet(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.subdirectory_arrow_right_rounded, size: 13, color: _gold),
                    SizedBox(width: 4),
                    Text(
                      'Répondre',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _gold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReplySheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18, right: 18, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '↳ ${message.text.length > 60 ? '${message.text.substring(0, 60)}…' : message.text}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: _text),
              decoration: InputDecoration(
                hintText: 'Dis à ORION quoi faire…',
                hintStyle: const TextStyle(color: _muted, fontSize: 12),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _gold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  await Future.wait([
                    sync.saveOrionQueueItem(
                      instruction: text,
                      context: message.text,
                    ),
                    if (message.requiresReply)
                      FirebaseFirestore.instance
                          .collection('users/$uid/assistant_messages')
                          .doc(message.id)
                          .update({'status': 'replied'}),
                  ]);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Envoyer à ORION',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _bg,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} · $h:$m';
  }
}

// ── Activate button ────────────────────────────────────────────────────────────

class _ActivateButton extends StatelessWidget {
  final bool activating;
  final bool limitReached;
  final VoidCallback? onTap;

  const _ActivateButton({
    required this.activating,
    required this.limitReached,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = limitReached
        ? _border
        : activating
            ? _goldDim
            : _gold;
    final fgColor = limitReached || activating ? _muted : _bg;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: activating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _muted),
              )
            : Text(
                limitReached ? 'Limite' : 'Activer',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fgColor,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.5,
        color: _muted,
      ),
    );
  }
}

String _friendlyError(Object e) {
  if (e is SocketException ||
      e is HandshakeException ||
      e.toString().contains('SocketException') ||
      e.toString().contains('Failed host lookup') ||
      e.toString().contains('Connection refused')) {
    return 'Connexion impossible — vérifie ta connexion internet.\n'
        'ORION a besoin d\'accès au réseau pour générer ta prochaine action stratégique.';
  }
  if (e.toString().contains('TimeoutException') ||
      e.toString().contains('timed out')) {
    return 'La requête a expiré — connexion trop lente ou serveur indisponible.\nRéessaie dans un instant.';
  }
  return e.toString();
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3b1218),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF7a2030).withOpacity(0.6)),
      ),
      child: Text(
        message,
        style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFFff8095),
            height: 1.5),
      ),
    );
  }
}
