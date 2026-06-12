import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';

const _kGold = Color(0xFFD4A017);
const _kRed = Color(0xFFFF2B2B);
const _kBlue = Color(0xFF0EA5E9);
const _kGreen = Color(0xFF22C55E);

// Arme de combat social : les nuisibles « Le Monde » sont des routines → couteau.
const _kWorldWeapon = 'couteau';
const _kNuisibleEmoji = '🐀';

/// Ouvre « Le Monde » : feed des routines relâchées + onglet de relâche.
Future<void> showWorldSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.6),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFF0E0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: _WorldSheet(logic: logic, sync: sync),
      ),
    ),
  );
}

String _freqLabel(String freq) => switch (freq) {
      'weekly' => 'hebdo',
      'monthly' => 'mensuel',
      _ => 'quotidien',
    };

class _WorldSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _WorldSheet({required this.logic, required this.sync});

  @override
  State<_WorldSheet> createState() => _WorldSheetState();
}

class _WorldSheetState extends State<_WorldSheet> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

  bool _loading = true;
  String? _busyId; // id d'action en cours (anti double-clic)
  List<WorldNuisible> _feed = const [];
  List<WorldNuisible> _myReleases = const [];
  Map<String, int> _combats = const {}; // nuisibleId → PV restants
  Set<String> _follows = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final results = await Future.wait([
      sync.fetchWorldNuisibles(),
      sync.fetchMyReleases(),
      sync.fetchWorldCombats(),
      sync.fetchMyFollows(),
    ]);
    if (!mounted) return;
    setState(() {
      _feed = results[0] as List<WorldNuisible>;
      _myReleases = results[1] as List<WorldNuisible>;
      _combats = results[2] as Map<String, int>;
      _follows = results[3] as Set<String>;
      _loading = false;
    });
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _engage(WorldNuisible n) async {
    setState(() => _busyId = n.id);
    await sync.engageWorldCombat(n.id, n.hp);
    await _reload();
    if (mounted) setState(() => _busyId = null);
  }

  Future<void> _strike(WorldNuisible n) async {
    if (logic.weaponsAvailable(_kWorldWeapon) <= 0) {
      _toast('Plus de ${logic.weaponName(_kWorldWeapon)} — gagne-en en tenant tes routines.',
          color: _kRed);
      return;
    }
    setState(() => _busyId = n.id);
    logic.spendWeaponForWorld(_kWorldWeapon, sync);
    final left = (_combats[n.id] ?? n.hp) - 1;
    await sync.setWorldCombatHp(n.id, left);
    if (left <= 0) {
      final err = await sync.followNuisible(n.id, true);
      if (err == null) {
        _toast('💥 Vaincu ! Tu suis maintenant @${n.ownerPseudo}.',
            color: _kGreen);
      } else {
        _toast(err, color: _kRed);
      }
    }
    await _reload();
    if (mounted) setState(() => _busyId = null);
  }

  Future<void> _unfollow(WorldNuisible n) async {
    setState(() => _busyId = n.id);
    final err = await sync.followNuisible(n.id, false);
    if (err != null) _toast(err, color: _kRed);
    await _reload();
    if (mounted) setState(() => _busyId = null);
  }

  Future<void> _release(Activity a) async {
    if (logic.releaseTokensAvailable <= 0) {
      _toast('Aucun jeton de relâche — capture des nuisibles pour en gagner.',
          color: _kRed);
      return;
    }
    final id = '${sync.uid}_${a.id}';
    final streak = logic.habitCurrentStreak(a.id);
    final hp = GoldEconomy.worldNuisibleHp(streak, logic.effectiveLevel());
    final domName = logic.state.activeDomains
        .where((d) => d.id == a.domainId)
        .map((d) => d.name)
        .firstOrNull;
    final freq = switch (logic.effectiveHabitFreq(a)) {
      HabitFreq.weekly => 'weekly',
      HabitFreq.monthly => 'monthly',
      HabitFreq.daily => 'daily',
    };
    final nuisible = WorldNuisible(
      id: id,
      ownerUid: sync.uid ?? '',
      ownerPseudo: '',
      routineId: a.id,
      name: a.name,
      freq: freq,
      target: logic.activeHabitTarget(a),
      domainName: domName,
      hp: hp,
      streak: streak,
      createdAt: DateTime.now(),
    );
    setState(() => _busyId = a.id);
    if (!logic.consumeReleaseToken(sync)) {
      if (mounted) setState(() => _busyId = null);
      return;
    }
    final err = await sync.releaseNuisible(nuisible);
    if (err != null) {
      _toast(err, color: _kRed);
    } else {
      _toast('🌍 « ${a.name} » est relâchée dans Le Monde.', color: _kGold);
    }
    await _reload();
    if (mounted) setState(() => _busyId = null);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(children: [
              const Text('🌍 Le Monde',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const TabBar(
            labelColor: _kGold,
            unselectedLabelColor: Colors.white54,
            indicatorColor: _kGold,
            tabs: [
              Tab(text: 'Combats publics'),
              Tab(text: 'Mes routines'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [_buildFeed(), _buildMine()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    final uid = sync.uid;
    final others = _feed.where((n) => n.ownerUid != uid).toList();
    if (others.isEmpty) {
      return _empty('Personne n\'a encore relâché de routine.',
          'Reviens plus tard — ou relâche la tienne pour lancer le mouvement.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: others.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _feedCard(others[i]),
    );
  }

  Widget _feedCard(WorldNuisible n) {
    final following = _follows.contains(n.id);
    final engaged = _combats.containsKey(n.id);
    final hpLeft = _combats[n.id] ?? n.hp;
    final hpFrac = n.hp > 0 ? (hpLeft / n.hp).clamp(0.0, 1.0) : 0.0;
    final busy = _busyId == n.id;
    final avail = logic.weaponsAvailable(_kWorldWeapon);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF160C0C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: following
                ? _kGreen.withOpacity(.4)
                : _kRed.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text(_kNuisibleEmoji, style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(
                      '@${n.ownerPseudo} · ${_freqLabel(n.freq)}'
                      '${n.streak > 0 ? ' · 🔥 ${n.streak}' : ''}',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.white.withOpacity(.5))),
                ],
              ),
            ),
            _pill('👁 ${n.spectatorCount}', Colors.white.withOpacity(.5)),
          ]),
          if (engaged && !following) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: hpFrac,
                minHeight: 5,
                backgroundColor: Colors.white.withOpacity(.08),
                color: _kRed.withOpacity(.8),
              ),
            ),
            const SizedBox(height: 4),
            Text('❤️ $hpLeft / ${n.hp} PV',
                style: TextStyle(
                    fontSize: 10.5, color: Colors.white.withOpacity(.55))),
          ],
          const SizedBox(height: 12),
          if (following)
            _pill('✓ Tu suis @${n.ownerPseudo}', _kGreen, filled: true,
                onTap: busy ? null : () => _unfollow(n))
          else if (!engaged)
            _actionBtn('⚔️ Engager le combat', _kRed,
                busy ? null : () => _engage(n))
          else
            _actionBtn(
                '${logic.weaponEmoji(_kWorldWeapon)} Frapper  ($avail)',
                avail > 0 ? _kBlue : Colors.grey,
                busy ? null : () => _strike(n)),
        ],
      ),
    );
  }

  Widget _buildMine() {
    final next = logic.totalCaptures % GoldEconomy.capturesPerReleaseToken;
    final tokens = logic.releaseTokensAvailable;
    final releasedIds = _myReleases.map((n) => n.routineId).toSet();
    final habits = logic.state.activeActivities
        .where((a) => a.isHabit && !releasedIds.contains(a.id))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bandeau jetons
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [_kGold.withOpacity(.18), _kGold.withOpacity(.04)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kGold.withOpacity(.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('🎟️', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Text('$tokens jeton${tokens > 1 ? 's' : ''} de relâche',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: next / GoldEconomy.capturesPerReleaseToken,
                  minHeight: 5,
                  backgroundColor: Colors.white.withOpacity(.08),
                  color: _kGold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  'Prochain jeton dans ${GoldEconomy.capturesPerReleaseToken - next} capture(s)',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withOpacity(.5))),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_myReleases.isNotEmpty) ...[
          _sectionTitle('Mes routines relâchées'),
          for (final n in _myReleases) _mineCard(n),
          const SizedBox(height: 18),
        ],
        _sectionTitle('Relâcher une routine'),
        if (habits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Aucune routine disponible à relâcher.',
                style: TextStyle(color: Colors.white.withOpacity(.5))),
          )
        else
          for (final a in habits) _releasableCard(a, tokens > 0),
      ],
    );
  }

  Widget _mineCard(WorldNuisible n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160C0C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withOpacity(.3)),
      ),
      child: Row(children: [
        const Text(_kNuisibleEmoji, style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(n.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        _pill('👁 ${n.spectatorCount} spectateur${n.spectatorCount > 1 ? 's' : ''}',
            _kGreen),
      ]),
    );
  }

  Widget _releasableCard(Activity a, bool canRelease) {
    final busy = _busyId == a.id;
    final streak = logic.habitCurrentStreak(a.id);
    final hp = GoldEconomy.worldNuisibleHp(streak, logic.effectiveLevel());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160C0C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.1)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              Text('Difficulté ❤️ $hp${streak > 0 ? ' · 🔥 $streak' : ''}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withOpacity(.5))),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _actionBtn(
          'Relâcher',
          canRelease ? _kGold : Colors.grey,
          (busy || !canRelease) ? null : () => _release(a),
          compact: true,
        ),
      ]),
    );
  }

  // ── Petits composants ──────────────────────────────────────────────────────

  Widget _empty(String title, String sub) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌍', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 6),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withOpacity(.5))),
            ],
          ),
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white70,
                letterSpacing: .3)),
      );

  Widget _pill(String text, Color color,
      {bool filled = false, VoidCallback? onTap}) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
    return onTap == null
        ? w
        : InkWell(
            borderRadius: BorderRadius.circular(20), onTap: onTap, child: w);
  }

  Widget _actionBtn(String label, Color color, VoidCallback? onTap,
      {bool compact = false}) {
    return SizedBox(
      width: compact ? null : double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(.4),
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 12, vertical: compact ? 8 : 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
