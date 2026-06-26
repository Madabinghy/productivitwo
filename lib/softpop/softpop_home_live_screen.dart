import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Accueil « Soft Pop » branché sur les **vraies données** (AppLogic).
///
/// Premier écran de la refonte câblé sur l'existant : routines (`Activity` habit),
/// domaines (couleur), blocs Matin/Midi/Soir (`DayBlock`), séries réelles. Cocher
/// une routine appelle `incHabit` → vrai log persisté (Firestore via onChange).
///
/// Les monnaies de jeu (XP / 💎 / ⚡) ne sont PAS encore branchées (économie à
/// créer) : l'en-tête affiche donc des stats réelles existantes (série, routines
/// du jour, temps loggué).
class SoftPopHomeLiveScreen extends StatefulWidget {
  final AppLogic logic;
  const SoftPopHomeLiveScreen({super.key, required this.logic});

  @override
  State<SoftPopHomeLiveScreen> createState() => _SoftPopHomeLiveScreenState();
}

class _SoftPopHomeLiveScreenState extends State<SoftPopHomeLiveScreen> {
  AppLogic get logic => widget.logic;
  DateTime get _today => DateTime.now();

  @override
  void initState() {
    super.initState();
    _ensureDefaultBlocks();
  }

  // Réactivation des blocs : crée Matin/Midi/Soir par défaut s'il n'y en a aucun.
  void _ensureDefaultBlocks() {
    if (logic.state.blocks.isNotEmpty) return;
    logic.createBlock('Matin', emoji: '🌅');
    logic.createBlock('Midi', emoji: '☀️');
    logic.createBlock('Soir', emoji: '🌙');
  }

  DayBlock? _blockOf(String activityId) {
    for (final b in logic.state.blocks) {
      if (b.activityIds.contains(activityId)) return b;
    }
    return null;
  }

  void _assign(Activity a, String? blockId) {
    for (final b in logic.state.blocks) {
      if (b.activityIds.contains(a.id)) {
        logic.removeActivityFromBlock(b.id, a.id);
      }
    }
    if (blockId != null) logic.addActivityToBlock(blockId, a.id);
    setState(() {});
  }

  Future<void> _pickMoment(Activity a) async {
    final blocks = [...logic.state.blocks]
      ..sort((x, y) => x.order.compareTo(y.order));
    final current = _blockOf(a.id);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SoftPop.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SoftPop.rCard)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SoftPop.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ranger « ${a.name} »',
                  style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s12),
              for (final b in blocks)
                ListTile(
                  leading: Text(b.emoji ?? '•',
                      style: const TextStyle(fontSize: 20)),
                  title: Text(b.name, style: SoftPop.ui(size: 15)),
                  trailing: current?.id == b.id
                      ? const Icon(Icons.check_circle, color: SoftPop.teal)
                      : null,
                  onTap: () {
                    _assign(a, b.id);
                    Navigator.pop(ctx);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.clear, color: SoftPop.inkMuted),
                title: Text('Aucun moment',
                    style: SoftPop.ui(size: 15, color: SoftPop.inkSecondary)),
                trailing: current == null
                    ? const Icon(Icons.check_circle, color: SoftPop.teal)
                    : null,
                onTap: () {
                  _assign(a, null);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _palette = [
    SoftPop.violet, SoftPop.coral, SoftPop.teal, SoftPop.amber, SoftPop.pink,
  ];

  Color _domainColor(String? domainId) {
    final doms = logic.state.activeDomains;
    final idx = doms.indexWhere((d) => d.id == domainId);
    if (idx >= 0 && doms[idx].colorValue != null) {
      return Color(doms[idx].colorValue!);
    }
    return idx >= 0 ? _palette[idx % _palette.length] : SoftPop.violet;
  }

  // Routines « du jour » : quotidiennes, ou ayant déjà une valeur aujourd'hui.
  List<Activity> get _todayHabits {
    return logic.state.activeActivities.where((a) {
      if (!a.isHabit) return false;
      if (logic.effectiveHabitFreq(a) == HabitFreq.daily) return true;
      return logic.habitValueOn(a.id, _today) > 0;
    }).toList();
  }

  bool _done(Activity a) {
    final tgt = logic.activeHabitTarget(a);
    return tgt > 0 && logic.habitValueOn(a.id, _today) >= tgt;
  }

  void _toggle(Activity a) {
    final tgt = logic.activeHabitTarget(a).clamp(1, 1 << 30);
    final cur = logic.habitValueOn(a.id, _today);
    final delta = _done(a) ? -cur : (tgt - cur);
    logic.incHabit(a.id, delta, _today);
    setState(() {});
    if (delta > 0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('« ${a.name} » ✓',
              style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
          backgroundColor: SoftPop.teal,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 900),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SoftPop.rChip)),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final habits = _todayHabits;
    final total = habits.length;
    final doneCount = habits.where(_done).length;
    final bestStreak = habits.isEmpty
        ? 0
        : habits.map((a) => logic.habitCurrentStreak(a.id)).fold(0, (m, s) => s > m ? s : m);
    final mins = logic.totalForDay(_today).inMinutes;

    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Accueil · données réelles')),
        body: habits.isEmpty
            ? _empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
                children: [
                  _header(),
                  const SizedBox(height: SoftPop.s12),
                  _statsRow(bestStreak, doneCount, total, mins),
                  const SizedBox(height: SoftPop.s12),
                  _progressCard(doneCount, total),
                  const SizedBox(height: SoftPop.s20),
                  Text('Aujourd’hui',
                      style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
                  const SizedBox(height: SoftPop.s12),
                  ..._blocks(habits),
                ],
              ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          const PomoMascot(size: 42),
          const SizedBox(width: SoftPop.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Salut 👋',
                    style: SoftPop.ui(size: 13, color: SoftPop.inkMuted)),
                Text('Belle journée qui démarre',
                    style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );

  Widget _statsRow(int streak, int done, int total, int mins) {
    final h = mins ~/ 60, m = mins % 60;
    final timeLabel = h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}min';
    return Row(
      children: [
        Expanded(child: _stat('🔥', '$streak', 'série', SoftPop.coral)),
        const SizedBox(width: SoftPop.s8),
        Expanded(child: _stat('✓', '$done/$total', 'faites', SoftPop.teal)),
        const SizedBox(width: SoftPop.s8),
        Expanded(child: _stat('⏱', timeLabel, 'aujourd’hui', SoftPop.violet)),
      ],
    );
  }

  Widget _stat(String emoji, String value, String label, Color c) => SoftCard(
        radius: SoftPop.rChip,
        padding: const EdgeInsets.symmetric(vertical: SoftPop.s12),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: SoftPop.s4),
            Text(value, style: SoftPop.mono(size: 15, color: c)),
            Text(label, style: SoftPop.ui(size: 10, color: SoftPop.inkMuted)),
          ],
        ),
      );

  Widget _progressCard(int done, int total) => SoftCard(
        radius: SoftPop.rCardSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Routines du jour',
                    style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                Text('$done / $total',
                    style: SoftPop.mono(size: 12, color: SoftPop.tealDark)),
              ],
            ),
            const SizedBox(height: SoftPop.s8),
            SoftXpBar(
                value: total == 0 ? 0 : done / total,
                gradient:
                    const LinearGradient(colors: [SoftPop.violet, SoftPop.teal])),
          ],
        ),
      );

  // Groupe les routines par DayBlock (Matin/Midi/Soir) SI des blocs existent.
  // Sinon (UI blocs désactivée → aucun DayBlock) : liste plate, sans sous-titre.
  List<Widget> _blocks(List<Activity> habits) {
    final out = <Widget>[];
    final placed = <String>{};
    final blocks = [...logic.state.blocks]..sort((a, b) => a.order.compareTo(b.order));
    for (final b in blocks) {
      final items = habits.where((a) => b.activityIds.contains(a.id)).toList();
      if (items.isEmpty) continue;
      placed.addAll(items.map((a) => a.id));
      out.addAll(_section(b.emoji ?? '•', b.name, items));
    }
    final rest = habits.where((a) => !placed.contains(a.id)).toList();
    if (out.isEmpty) {
      // Aucun bloc : liste plate directe sous « Aujourd'hui ».
      for (final a in rest) {
        out.add(_tile(a));
        out.add(const SizedBox(height: SoftPop.s8));
      }
      return out;
    }
    if (rest.isNotEmpty) out.addAll(_section('🕐', 'À tout moment', rest));
    return out;
  }

  List<Widget> _section(String emoji, String label, List<Activity> items) {
    final done = items.where(_done).length;
    return [
      Padding(
        padding: const EdgeInsets.only(
            top: SoftPop.s8, bottom: SoftPop.s8, left: SoftPop.s4),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: SoftPop.s8),
            Text(label,
                style: SoftPop.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: SoftPop.inkSecondary)),
            const SizedBox(width: SoftPop.s8),
            Text('$done/${items.length}',
                style: SoftPop.mono(size: 11, color: SoftPop.inkMuted)),
          ],
        ),
      ),
      for (final a in items) ...[
        _tile(a),
        const SizedBox(height: SoftPop.s8),
      ],
    ];
  }

  Widget _tile(Activity a) {
    final c = _domainColor(a.domainId);
    final done = _done(a);
    final tgt = logic.activeHabitTarget(a);
    final val = logic.habitValueOn(a.id, _today);
    final streak = logic.habitCurrentStreak(a.id);
    final target =
        tgt > 1 ? '$val/$tgt${a.unit != null ? ' ${a.unit}' : ''}' : 'objectif du jour';
    return SoftCard(
      padding: const EdgeInsets.all(SoftPop.s12),
      radius: SoftPop.rCardSm,
      onTap: () => _toggle(a),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              a.iconCode != null
                  // ignore: non_const_argument_for_const_parameter
                  ? IconData(a.iconCode!, fontFamily: 'MaterialIcons')
                  : Icons.bolt,
              size: 19,
              color: c,
            ),
          ),
          const SizedBox(width: SoftPop.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: SoftPop.ui(
                        size: 14,
                        weight: FontWeight.w600,
                        color: done ? SoftPop.inkMuted : SoftPop.ink)),
                Row(
                  children: [
                    Text(target,
                        style: SoftPop.ui(size: 10, color: SoftPop.inkMuted)),
                    if (streak > 0) ...[
                      const SizedBox(width: SoftPop.s8),
                      Text('🔥 $streak j',
                          style: SoftPop.ui(size: 10, color: SoftPop.coralDark)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _momentBtn(a),
          const SizedBox(width: SoftPop.s8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? SoftPop.teal : Colors.transparent,
              border: done
                  ? null
                  : Border.all(
                      color: SoftPop.inkMuted.withValues(alpha: .4), width: 2),
            ),
            child: done
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        ],
      ),
    );
  }

  // Bouton d'assignation à un moment : montre l'emoji du bloc courant, ou un +.
  Widget _momentBtn(Activity a) {
    final b = _blockOf(a.id);
    return InkWell(
      borderRadius: BorderRadius.circular(SoftPop.rPill),
      onTap: () => _pickMoment(a),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SoftPop.s8, vertical: SoftPop.s4),
        decoration: BoxDecoration(
          color: SoftPop.violetSoft,
          borderRadius: BorderRadius.circular(SoftPop.rPill),
        ),
        child: b != null
            ? Text(b.emoji ?? b.name, style: const TextStyle(fontSize: 14))
            : const Icon(Icons.more_time, size: 16, color: SoftPop.violet),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(SoftPop.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PomoMascot(size: 88),
              const SizedBox(height: SoftPop.s20),
              Text('Aucune routine pour aujourd’hui',
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s8),
              Text('Ajoute des routines dans l’app pour les voir ici.',
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(size: 14, color: SoftPop.inkSecondary)),
            ],
          ),
        ),
      );
}
