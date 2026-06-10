import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

/// Boutique d'Or (Phase D) : dépense de pièces d'or en consommables stratégiques
/// (gel de série, sursis, joker) et cosmétiques (titres). Achats transactionnels.
Future<void> showGoldShopSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GoldShopSheet(logic: logic, sync: sync),
  );
}

const _kGold = Color(0xFFD4A017);

/// Titres cosmétiques achetables (id = libellé affiché).
const _kTitles = <(String, int)>[
  ('Le Stratège', 15),
  ('Maître du Temps', 25),
  ('Architecte', 40),
];

class _GoldShopSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _GoldShopSheet({required this.logic, required this.sync});

  @override
  State<_GoldShopSheet> createState() => _GoldShopSheetState();
}

class _GoldShopSheetState extends State<_GoldShopSheet> {
  AppLogic get logic => widget.logic;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Solde à jour des gains du jour (dépensables de suite) à l'ouverture.
    logic.reconcileLiveGold(widget.sync);
  }

  int get _gold => logic.gold;
  int get _level => logic.effectiveLevel();
  int _inv(String k) => logic.state.goldInventory[k] ?? 0;

  Future<void> _buyConsumable(String key, int price, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.sync
        .purchaseGold(price: price, label: 'Achat : $label', incInventory: key);
    if (ok) {
      // Optimiste local (l'or est autoritatif Firestore ; pull reconvergera).
      logic.state.gold -= price;
      logic.state.goldInventory[key] = _inv(key) + 1;
      logic.onChange();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '$label acheté.' : 'Solde insuffisant.'),
    ));
  }

  Future<void> _buyTitle(String title, int price) async {
    if (_busy) return;
    final owned = logic.state.cosmeticsOwned.contains(title);
    if (owned) {
      // Déjà possédé → activer (gratuit).
      logic.state.activeTitle = title;
      logic.onChange();
      await widget.sync.purchaseGold(price: 0, label: 'Titre actif : $title', setActiveTitle: title);
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.sync.purchaseGold(
        price: price, label: 'Titre : $title',
        addCosmetic: title, setActiveTitle: title);
    if (ok) {
      logic.state.gold -= price;
      logic.state.cosmeticsOwned.add(title);
      logic.state.activeTitle = title;
      logic.onChange();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Titre « $title » débloqué.' : 'Solde insuffisant.'),
    ));
  }

  Future<void> _useGel() async {
    final habits =
        logic.state.activeActivities.where((a) => a.isHabit).toList();
    if (habits.isEmpty) return;
    final activity = await showModalBottomSheet<Activity>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Geler quelle routine ?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final a in habits)
            ListTile(title: Text(a.name), onTap: () => Navigator.pop(ctx, a)),
        ]),
      ),
    );
    if (activity == null || !mounted) return;
    // Choix du jour : aujourd'hui / demain / +2j
    final now = DateTime.now();
    final day = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Geler quel jour ?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final (i, label) in const [
            (0, "Aujourd'hui"),
            (1, 'Demain'),
            (2, 'Dans 2 jours'),
          ])
            ListTile(
              title: Text(label),
              onTap: () =>
                  Navigator.pop(ctx, now.add(Duration(days: i))),
            ),
        ]),
      ),
    );
    if (day == null || !mounted) return;
    final ymd = yyyymmdd(day);
    final ok = await widget.sync.useGel(activity.id, ymd);
    if (ok) {
      logic.state.goldInventory['gel'] = _inv('gel') - 1;
      logic.state.goldGelDays.add('${activity.id}_$ymd');
      logic.onChange();
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '🧊 « ${activity.name} » gelée — pas de pénalité ce jour-là.'
          : 'Aucun gel disponible.'),
    ));
  }

  Future<void> _useShield() async {
    final tasks = <ProjectTask>[];
    for (final p in logic.currentProjects) {
      if (p.status != 'active') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        tasks.add(t);
      }
    }
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucune tâche active à protéger.')));
      return;
    }
    final task = await showModalBottomSheet<ProjectTask>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Protéger quelle tâche ?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final t in tasks)
                ListTile(title: Text(t.title), onTap: () => Navigator.pop(ctx, t)),
            ]),
          ),
        ]),
      ),
    );
    if (task == null || !mounted) return;
    final now = DateTime.now();
    final ymds = [
      for (int i = 0; i < GoldEconomy.shieldDaysPerUse; i++)
        '${task.id}_${yyyymmdd(now.add(Duration(days: i)))}'
    ];
    final ok = await widget.sync.useShield(ymds);
    if (ok) {
      logic.state.goldInventory['shield'] = _inv('shield') - 1;
      logic.state.goldTaskShieldDays.addAll(ymds);
      logic.onChange();
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '🛡️ « ${task.title} » protégée du retard ${GoldEconomy.shieldDaysPerUse} j.'
          : 'Aucun bouclier disponible.'),
    ));
  }

  Future<void> _useBoost() async {
    final today = DateTime.now();
    final ymds = [
      for (int i = 0; i < GoldEconomy.boostDaysPerUse; i++)
        yyyymmdd(today.add(Duration(days: i)))
    ];
    if (ymds.every((d) => logic.state.goldBoostDays.contains(d))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Multiplicateur déjà actif sur ces jours.')));
      return;
    }
    final ok = await widget.sync.useBoostDays(ymds);
    if (ok) {
      logic.state.goldInventory['boost'] = _inv('boost') - 1;
      for (final d in ymds) {
        if (!logic.state.goldBoostDays.contains(d)) {
          logic.state.goldBoostDays.add(d);
        }
      }
      logic.onChange();
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '✨ Gains d\'or ×2 activés pour ${GoldEconomy.boostDaysPerUse} jours !'
          : 'Aucun multiplicateur disponible.'),
    ));
  }

  // ── 🧪 DEV / TEST (temporaire) ──────────────────────────────────────────────
  Future<void> _devAddGold() async {
    await widget.sync.devAddGold(100);
    logic.state.gold += 100;
    logic.onChange();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('🧪 +100 or')));
    }
  }

  Future<void> _devAddXp() async {
    await widget.sync.devAddXp(100);
    logic.state.goldLifetime += 100;
    logic.onChange();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('🧪 +100 XP')));
    }
  }

  Future<void> _devReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset complet ?'),
        content: const Text(
            'Remet à zéro : or, XP/niveau, expédition et inventaire. Action de test.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tout remettre à zéro')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.sync.devReset();
    String fmt(DateTime d) => '${d.year}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    logic.state.gold = 0;
    logic.state.goldLifetime = 0;
    logic.state.unlockedLevel = 1;
    logic.state.expeditionCleared.clear();
    logic.state.expeditionRevealed.clear();
    logic.state.expeditionPos = null;
    logic.state.expeditionPicked.clear();
    logic.state.expeditionEntities.clear();
    logic.state.expeditionChallenges.clear();
    logic.state.collection.clear();
    logic.state.lastFreeStepYmd = null;
    logic.state.goldInventory.clear();
    // Aligné sur sync.devReset : curseur hier (le jour de reset se matérialise
    // demain), epoch aujourd'hui (l'historique repart d'ici), flottant remis à 0.
    logic.state.goldLastProcessedDay = fmt(now.subtract(const Duration(days: 1)));
    logic.state.goldTodayGain = 0;
    logic.state.goldTodayGainYmd = null;
    logic.state.goldEpochYmd = fmt(now);
    logic.onChange();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('🧪 Économie remise à zéro')));
    }
  }

  Future<void> _useRepair() async {
    final habits =
        logic.state.activeActivities.where((a) => a.isHabit).toList();
    if (habits.isEmpty) return;
    final activity = await showModalBottomSheet<Activity>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Réparer quelle routine ?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final a in habits)
            ListTile(title: Text(a.name), onTap: () => Navigator.pop(ctx, a)),
        ]),
      ),
    );
    if (activity == null || !mounted) return;
    final tgt = logic.activeHabitTarget(activity);
    final now = DateTime.now();
    final missed = <DateTime>[];
    for (int i = 1; i <= 14; i++) {
      final d = now.subtract(Duration(days: i));
      final ymd = yyyymmdd(d);
      if (logic.habitValueOn(activity.id, d) < tgt &&
          !logic.state.goldGelDays.contains('${activity.id}_$ymd')) {
        missed.add(d);
      }
    }
    if (missed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun jour manqué récent à réparer.')));
      return;
    }
    const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                  'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    final day = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Réparer quel jour manqué ?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final d in missed)
                ListTile(
                  title: Text('${d.day} ${mois[d.month - 1]}'),
                  onTap: () => Navigator.pop(ctx, d),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (day == null || !mounted) return;
    final ymd = yyyymmdd(day);
    final ok = await widget.sync.useRepair(activity.id, ymd);
    if (ok) {
      logic.state.goldInventory['repair'] = _inv('repair') - 1;
      logic.state.goldGelDays.add('${activity.id}_$ymd');
      logic.onChange();
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '🧬 Série de « ${activity.name} » réparée (${day.day} ${mois[day.month - 1]}).'
          : 'Aucune réparation disponible.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(children: [
            const Text('🛒', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            const Text('Boutique',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            goldAmount('$_gold',
                fontSize: 16, weight: FontWeight.bold, color: _kGold),
          ]),
          const SizedBox(height: 4),
          Text(
              'Dépense ton or pour te protéger des pertes. Les items se débloquent '
              'au fil des niveaux, et leurs prix montent à chaque niveau (niveau $_level).',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 16),

          for (final it in <({
            String key,
            String emoji,
            String title,
            String subtitle,
            int base,
            Future<void> Function()? use,
          })>[
            (
              key: 'gel',
              emoji: '🧊',
              title: 'Gel de série',
              subtitle: 'Protège une routine d\'un jour off (annule le −1 or/j).',
              base: GoldEconomy.shopGel,
              use: _useGel,
            ),
            (
              key: 'sursis',
              emoji: '⏳',
              title: 'Sursis de deadline',
              subtitle:
                  'Se consomme en repoussant la deadline d\'une tâche (sans coût).',
              base: GoldEconomy.shopSursis,
              use: null,
            ),
            (
              key: 'joker',
              emoji: '🗑️',
              title: 'Joker de suppression',
              subtitle: 'Annule le coût d\'une suppression (auto à la prochaine).',
              base: GoldEconomy.shopJoker,
              use: null,
            ),
            (
              key: 'shield',
              emoji: '🛡️',
              title: 'Bouclier anti-retard',
              subtitle:
                  'Gèle le −1 or/j de retard d\'une tâche pendant ${GoldEconomy.shieldDaysPerUse} jours.',
              base: GoldEconomy.shopShield,
              use: _useShield,
            ),
            (
              key: 'boost',
              emoji: '✨',
              title: 'Multiplicateur ×2 (${GoldEconomy.boostDaysPerUse} j)',
              subtitle:
                  'Double tes gains d\'or pendant ${GoldEconomy.boostDaysPerUse} jours (routines, temps, actions).',
              base: GoldEconomy.shopBoost,
              use: _useBoost,
            ),
            (
              key: 'repair',
              emoji: '🧬',
              title: 'Réparation de série',
              subtitle: 'Regèle un jour manqué passé pour sauver une série cassée.',
              base: GoldEconomy.shopRepair,
              use: _useRepair,
            ),
          ])
            Builder(builder: (_) {
              final price = GoldEconomy.scaledPrice(it.base, _level);
              final minLvl = GoldEconomy.itemMinLevel[it.key] ?? 1;
              final locked = _level < minLvl;
              return _ShopItem(
                emoji: it.emoji,
                title: it.title,
                subtitle: it.subtitle,
                price: price,
                owned: _inv(it.key),
                affordable: _gold >= price,
                busy: _busy,
                locked: locked,
                minLevel: minLvl,
                onBuy: () => _buyConsumable(it.key, price, it.title),
                onUse: (!locked && _inv(it.key) > 0) ? it.use : null,
                cs: cs,
              );
            }),

          const SizedBox(height: 20),
          Text('ARMES D\'EXPÉDITION',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 4),
          Text(
              'Pour éliminer les nuisibles qui apparaissent sur la carte quand ta semaine décline. Consommables : 1 arme = 1 élimination.',
              style:
                  TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 8),
          for (final t in const <({String key, String emoji, String title, String subtitle})>[
            (key: 'epee', emoji: '🗡️', title: 'Épée', subtitle: 'Tue un serpent 🐍 (−5 or/jour tant qu\'il vit).'),
            (key: 'sandale', emoji: '🩴', title: 'Sandale', subtitle: 'Écrase une araignée 🕷️ ou un scorpion 🦂.'),
          ])
            Builder(builder: (_) {
              final price =
                  GoldEconomy.scaledPrice(GoldEconomy.weaponBasePrice(t.key), _level);
              return _ShopItem(
                emoji: t.emoji,
                title: t.title,
                subtitle: t.subtitle,
                price: price,
                owned: _inv(t.key),
                affordable: _gold >= price,
                busy: _busy,
                locked: false,
                minLevel: 1,
                onBuy: () => _buyConsumable(t.key, price, t.title),
                onUse: null,
                cs: cs,
              );
            }),

          const SizedBox(height: 20),
          Text('TITRES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 8),
          for (final (title, price) in _kTitles)
            _TitleItem(
              title: title,
              price: price,
              owned: logic.state.cosmeticsOwned.contains(title),
              active: logic.state.activeTitle == title,
              affordable: _gold >= price,
              busy: _busy,
              onTap: () => _buyTitle(title, price),
              cs: cs,
            ),

          // ── 🧪 DEV / TEST (temporaire — à retirer avant prod) ─────────────
          const SizedBox(height: 20),
          Text('🧪 TEST (à supprimer)',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: cs.error.withOpacity(.8))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _devAddXp, child: const Text('+100 XP')),
            OutlinedButton(onPressed: _devAddGold, child: const Text('+100 or')),
            OutlinedButton(
              onPressed: _devReset,
              style: OutlinedButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Reset (XP & or)'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  final String emoji, title, subtitle;
  final int price, owned;
  final bool affordable, busy, locked;
  final int minLevel;
  final VoidCallback? onBuy;
  final VoidCallback? onUse;
  final ColorScheme cs;
  const _ShopItem({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.owned,
    required this.affordable,
    required this.busy,
    required this.locked,
    required this.minLevel,
    required this.onBuy,
    required this.onUse,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? .55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Text(locked ? '🔒' : emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (owned > 0 && !locked) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: _kGold.withOpacity(.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('×$owned',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _kGold)),
                    ),
                  ],
                ]),
                Text(locked ? 'Débloqué au niveau $minLevel' : subtitle,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: locked ? FontStyle.italic : FontStyle.normal,
                        color: cs.onSurface.withOpacity(.55))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (locked)
            Icon(Icons.lock_outline,
                size: 18, color: cs.onSurface.withOpacity(.4))
          else
            Column(children: [
              if (onUse != null)
                TextButton(
                    onPressed: busy ? null : onUse,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child:
                        const Text('Utiliser', style: TextStyle(fontSize: 12))),
              FilledButton(
                onPressed: (busy || !affordable) ? null : onBuy,
                style: FilledButton.styleFrom(
                    backgroundColor: _kGold,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$price', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 3),
                  const GoldIcon(size: 13, color: Colors.white),
                ]),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _TitleItem extends StatelessWidget {
  final String title;
  final int price;
  final bool owned, active, affordable, busy;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _TitleItem({
    required this.title,
    required this.price,
    required this.owned,
    required this.active,
    required this.affordable,
    required this.busy,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(active ? Icons.emoji_events : Icons.emoji_events_outlined,
            size: 18, color: active ? _kGold : cs.onSurface.withOpacity(.4)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  color: active ? _kGold : null)),
        ),
        if (active)
          Text('Actif',
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withOpacity(.45)))
        else if (owned)
          TextButton(
              onPressed: busy ? null : onTap,
              style:
                  TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Activer', style: TextStyle(fontSize: 12)))
        else
          FilledButton(
            onPressed: (busy || !affordable) ? null : onTap,
            style: FilledButton.styleFrom(
                backgroundColor: _kGold,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$price', style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 3),
              const GoldIcon(size: 13, color: Colors.white),
            ]),
          ),
      ]),
    );
  }
}
