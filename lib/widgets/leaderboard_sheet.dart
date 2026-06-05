import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';

/// Classement XP global (Phase 1). Si l'utilisateur n'a pas de pseudo / n'est
/// pas opt-in, propose de rejoindre le classement.
Future<void> showLeaderboardSheet(BuildContext context, FirestoreSync sync) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LeaderboardSheet(sync: sync),
  );
}

const _periods = [
  ('xpWeek', 'Semaine'),
  ('xpMonth', 'Mois'),
  ('xpTotal', 'Total'),
];

class _LeaderboardSheet extends StatefulWidget {
  final FirestoreSync sync;
  const _LeaderboardSheet({required this.sync});

  @override
  State<_LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<_LeaderboardSheet> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _period = 'xpWeek';

  final _pseudoCtrl = TextEditingController();
  bool _joining = false;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pseudoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await widget.sync.fetchMyProfile();
    final optedIn = profile?['optedIn'] == true;
    final entries = optedIn ? await widget.sync.fetchLeaderboard(_period) : <Map<String, dynamic>>[];
    if (mounted) {
      setState(() {
        _profile = profile;
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _join() async {
    final pseudo = _pseudoCtrl.text.trim();
    if (pseudo.length < 3) {
      setState(() => _joinError = 'Au moins 3 caractères');
      return;
    }
    setState(() {
      _joining = true;
      _joinError = null;
    });
    final err = await widget.sync.claimPseudo(pseudo, true);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _joining = false;
        _joinError = err;
      });
      return;
    }
    setState(() => _joining = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final optedIn = _profile?['optedIn'] == true;
    final myUid = widget.sync.uid;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const Text('🏆', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Classement',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
              ]),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!optedIn)
              _buildJoin(cs)
            else
              _buildBoard(cs, myUid),
          ],
        ),
      ),
    );
  }

  Widget _buildJoin(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rejoins le classement : choisis un pseudo public et compare ton XP avec les autres.',
          style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.7)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pseudoCtrl,
          maxLength: 20,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            hintText: 'Ton pseudo (lettres, chiffres, _)',
            errorText: _joinError,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ton pseudo et ton XP seront visibles par les autres. Tu peux te retirer à tout moment.',
          style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.45)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _joining ? null : _join,
            icon: _joining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.emoji_events_outlined, size: 18),
            label: Text(_joining ? 'Inscription…' : 'Rejoindre le classement'),
          ),
        ),
      ],
    );
  }

  Widget _buildBoard(ColorScheme cs, String? myUid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final p in _periods)
              ChoiceChip(
                label: Text(p.$2),
                selected: _period == p.$1,
                onSelected: (_) {
                  setState(() => _period = p.$1);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Personne dans le classement pour l\'instant.',
                style: TextStyle(
                    color: cs.onSurface.withOpacity(.5),
                    fontStyle: FontStyle.italic)),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _entries.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
              itemBuilder: (_, i) {
                final e = _entries[i];
                final isMe = e['uid'] == myUid;
                final rank = i + 1;
                final medal = rank == 1
                    ? '🥇'
                    : rank == 2
                        ? '🥈'
                        : rank == 3
                            ? '🥉'
                            : '$rank';
                return Container(
                  color: isMe ? cs.primary.withOpacity(.08) : null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(medal,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e['pseudo']}${isMe ? ' (toi)' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isMe ? FontWeight.w800 : FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('Nv ${e['level']}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.45))),
                      const SizedBox(width: 10),
                      Text('⭐ ${e['xp']}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.primary)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
