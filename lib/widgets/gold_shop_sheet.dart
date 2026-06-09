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

  int get _gold => logic.gold;
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
          Text('Dépense ton or pour te protéger des pertes.',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 16),

          _ShopItem(
            emoji: '🧊',
            title: 'Gel de série',
            subtitle: 'Protège une routine d\'un jour off (annule le −1 or/j).',
            price: GoldEconomy.shopGel,
            owned: _inv('gel'),
            affordable: _gold >= GoldEconomy.shopGel,
            busy: _busy,
            onBuy: () => _buyConsumable('gel', GoldEconomy.shopGel, 'Gel de série'),
            onUse: _inv('gel') > 0 ? _useGel : null,
            cs: cs,
          ),
          _ShopItem(
            emoji: '⏳',
            title: 'Sursis de deadline',
            subtitle: 'Décale une deadline une fois sans coût (à consommer).',
            price: GoldEconomy.shopSursis,
            owned: _inv('sursis'),
            affordable: _gold >= GoldEconomy.shopSursis,
            busy: _busy,
            onBuy: () =>
                _buyConsumable('sursis', GoldEconomy.shopSursis, 'Sursis de deadline'),
            onUse: null,
            cs: cs,
          ),
          _ShopItem(
            emoji: '🗑️',
            title: 'Joker de suppression',
            subtitle: 'Annule le coût d\'une suppression (auto à la prochaine).',
            price: GoldEconomy.shopJoker,
            owned: _inv('joker'),
            affordable: _gold >= GoldEconomy.shopJoker,
            busy: _busy,
            onBuy: () =>
                _buyConsumable('joker', GoldEconomy.shopJoker, 'Joker de suppression'),
            onUse: null,
            cs: cs,
          ),

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
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  final String emoji, title, subtitle;
  final int price, owned;
  final bool affordable, busy;
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
    required this.onBuy,
    required this.onUse,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (owned > 0) ...[
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
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(children: [
          if (onUse != null)
            TextButton(
                onPressed: busy ? null : onUse,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: const Text('Utiliser', style: TextStyle(fontSize: 12))),
          FilledButton(
            onPressed: (busy || !affordable) ? null : onBuy,
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
      ]),
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
