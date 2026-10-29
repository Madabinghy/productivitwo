import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineReachedDays, kRoutineTiers;
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kEmberColor;
import 'package:productivitwo_v1/widgets/fiche.dart';

/// Braises, écrans (lot 2, maquette « Braises de rattrapage » 2026-10-30).

/// La réserve en trois flammes ; [extra] = la braise forgée ce soir (pointillé).
class EmberDots extends StatelessWidget {
  final int stock;
  final bool extra;
  final String? label;
  const EmberDots({super.key, required this.stock, this.extra = false, this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < kEmberCap; i++)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            i < stock ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
            size: 20,
            color: i < stock ? kEmberColor : (extra && i == stock ? kEmberColor.withValues(alpha: .7) : kBText4),
          ),
        ),
      if (label != null) ...[
        const SizedBox(width: 4),
        Flexible(child: Text(label!, style: const TextStyle(fontSize: 12, color: kBText3))),
      ],
    ]);
  }
}

String emberCountLabel(int n) => n == 0 ? 'aucune braise en réserve' : '$n braise${n > 1 ? 's' : ''} en réserve';

/// Une série cassée hier : « Rallumer · 🔥1 », ou en attente du +1 du jour
/// (bouton +1, annuler), ou indisponible avec la raison.
class LostSeriesRow extends StatelessWidget {
  final LostSeries lost;
  final int todayCount;
  final int target;
  final VoidCallback? onRekindle;
  final VoidCallback? onPlus;
  final VoidCallback? onCancel;
  const LostSeriesRow({super.key, required this.lost, this.todayCount = 0, this.target = 1, this.onRekindle, this.onPlus, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l = lost;
    final sub = l.pending
        ? 'rallumée · braise en attente · $todayCount / $target aujourd’hui'
        : (l.blocked ?? '${l.nextTier == null ? '' : 'palier ${l.nextTier} j dans ${l.nextTier! - l.length} j · '}rattrapable jusqu’à ce soir');
    final Widget action;
    if (l.pending) {
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        if (onCancel != null)
          IconButton(tooltip: 'Annuler le rallumage', visualDensity: VisualDensity.compact, onPressed: onCancel, icon: const Icon(Icons.close_rounded, size: 18, color: kBText3)),
        _pill('+1', kEmberColor, onPlus, filled: true),
      ]);
    } else if (l.rekindlable) {
      action = _pill('Rallumer · 🔥1', kEmberColor, onRekindle, filled: true);
    } else {
      action = _pill('Indisponible', kBText3, null);
    }
    return Opacity(
      opacity: l.blocked != null && !l.pending ? .7 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: l.pending ? kEmberColor.withValues(alpha: .5) : (l.rekindlable ? kBAlert.withValues(alpha: .35) : kBLine)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${l.name} · série de ${l.length} j cassée', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: l.pending ? kEmberColor : kBText3)),
            ]),
          ),
          const SizedBox(width: 8),
          action,
        ]),
      ),
    );
  }

  Widget _pill(String label, Color c, VoidCallback? onTap, {bool filled = false}) => SizedBox(
        height: 34,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: filled ? c : Colors.transparent,
            foregroundColor: filled ? const Color(0xFF1F0B02) : c,
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: c,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: filled ? null : BorderSide(color: c.withValues(alpha: .4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ),
      );
}

/// Section « PERDU HIER » : les séries cassées hier, puis la réserve. [all] =
/// aussi les séries indisponibles (feuille) ; sinon seulement l'actionnable.
class LostYesterdaySection extends StatelessWidget {
  final AppLogic logic;
  final bool all;
  final VoidCallback onChanged;
  final void Function(Activity routine) onPlus;
  const LostYesterdaySection({super.key, required this.logic, required this.onChanged, required this.onPlus, this.all = false});

  @override
  Widget build(BuildContext context) {
    final lost = logic.lostSeriesYesterday().where((l) => all || l.pending || l.rekindlable).toList();
    if (lost.isEmpty) return const SizedBox.shrink();
    final ledger = logic.emberLedgerNow();
    Activity? act(String id) => logic.state.activeActivities.where((a) => a.id == id).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(2, 6, 2, 2),
        child: Row(children: [
          Text('PERDU HIER', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
          InfoDot(kRuleEmbers, size: 16),
          Spacer(),
          Text('rattrapable jusqu’à ce soir', style: TextStyle(fontSize: 11, color: kBText4)),
        ]),
      ),
      for (final l in lost)
        LostSeriesRow(
          lost: l,
          todayCount: _todayCount(logic, l.activityId),
          target: (act(l.activityId)?.habitTarget ?? 1).clamp(1, 999),
          onRekindle: () async {
            final a = act(l.activityId);
            if (a == null) return;
            final ok = await showRekindleSheet(context, logic: logic, routine: a, lost: l);
            if (ok) onChanged();
          },
          onPlus: () {
            final a = act(l.activityId);
            if (a != null) onPlus(a);
          },
          onCancel: () async {
            await logic.cancelRekindle(l.activityId);
            onChanged();
          },
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        child: EmberDots(stock: ledger.available, label: emberCountLabel(ledger.available)),
      ),
    ]);
  }

  static int _todayCount(AppLogic logic, String id) {
    final today = logic.livedTodayYmd;
    return logic.state.habitHits.where((h) => h.habitId == id && ymdOf(livedDate(h.ts, logic.dayStartMin)) == today).length;
  }
}

/// Feuille « Rallumer X ? » : les six derniers jours, prix, condition,
/// résultat, trace. Renvoie true si le rallumage est armé.
Future<bool> showRekindleSheet(BuildContext context, {required AppLogic logic, required Activity routine, required LostSeries lost}) async {
  final ok = await showFiche<bool>(context, builder: (ctx, scroll) {
    final today = logic.livedTodayYmd;
    final reached = routineReachedDays(routine, logic.state.habitHits, dayStartMin: logic.dayStartMin);
    final bridged = logic.bridgedOf(routine.id);
    final ledger = logic.emberLedgerNow();
    final target = (routine.habitTarget ?? 1).clamp(1, 999);
    final doneToday = reached.contains(today);
    final after = lost.length + 2;
    final nextTier = kRoutineTiers.where((t) => t > after).firstOrNull;
    const days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    Widget cell(String ymd) {
      final d = DateTime.parse(ymd);
      final label = days[d.weekday - 1];
      final isToday = ymd == today, isLost = ymd == lost.lostYmdOf(today);
      final Color? fill;
      final Color border;
      final Color fg;
      if (isToday) {
        fill = doneToday ? const Color(0xFF2FB3A3) : null;
        border = const Color(0xFF2FB3A3);
        fg = doneToday ? kBBg : const Color(0xFF2FB3A3);
      } else if (isLost) {
        fill = kEmberColor.withValues(alpha: .18);
        border = kEmberColor;
        fg = kEmberColor;
      } else if (reached.contains(ymd) || bridged.contains(ymd)) {
        fill = const Color(0xFF2FB3A3).withValues(alpha: .55);
        border = Colors.transparent;
        fg = kBBg;
      } else {
        fill = kBRaised;
        border = Colors.transparent;
        fg = kBText3;
      }
      return Expanded(
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(7), border: Border.all(color: border, width: 1.5)),
          child: Text(isLost ? '🔥' : label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      );
    }

    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(k, style: const TextStyle(fontSize: 13, color: kBText3))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, color: kBText))),
          ]),
        );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        FicheHeader(title: 'Rallumer ${routine.name} ?', chip: 'série cassée hier', chipColor: kEmberColor, kpi: 'Série de ${lost.length} j tenue jusqu’à avant-hier'),
        const SizedBox(height: 14),
        Row(children: [for (var i = 5; i >= 0; i--) cell(ymdShift(today, -i))]),
        const SizedBox(height: 4),
        Row(children: [
          Text('${lost.length} jour${lost.length > 1 ? 's' : ''} tenu${lost.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: kBText4)),
          const Spacer(),
          const Text('hier comblé · aujourd’hui à faire', style: TextStyle(fontSize: 11, color: kBText4)),
        ]),
        const SizedBox(height: 14),
        kv('Prix', '1 braise · réserve ${ledger.available} → ${ledger.available - 1}'),
        kv('Condition', doneToday ? '${routine.name} est déjà atteinte aujourd’hui' : 'atteindre ${routine.name} aujourd’hui (0 / $target)'),
        kv('Résultat', 'série de $after j ce soir${nextTier == null ? '' : ' · palier $nextTier j dans ${nextTier - after} j'}'),
        kv('Trace', 'hier marqué d’une braise dans l’historique de la série'),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kEmberColor, foregroundColor: const Color(0xFF1F0B02), shape: const StadiumBorder()),
            onPressed: () async {
              await logic.rekindle(routine.id);
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            icon: const Icon(Icons.local_fire_department_rounded),
            label: const Text('Rallumer avec une braise', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          doneToday
              ? 'La braise est brûlée tout de suite : la routine est déjà faite.'
              : 'Si ${routine.name} n’est pas atteinte avant la bascule, la braise revient dans la réserve.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: kBText3),
        ),
      ],
    );
  });
  return ok == true;
}

extension LostSeriesYmd on LostSeries {
  String lostYmdOf(String todayYmd) => ymdShift(todayYmd, -1);
}

/// Bloc « Braises » de « Badges en jeu » : réserve, prochaine braise, historique.
class EmberLedgerPanel extends StatelessWidget {
  final EmberLedger ledger;
  final Map<String, String> names;
  const EmberLedgerPanel({super.key, required this.ledger, this.names = const {}});

  @override
  Widget build(BuildContext context) {
    final events = ledger.history.where((e) => e.kind != EmberEventKind.capped).take(5).toList();
    String date(String ymd) {
      const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
      final d = DateTime.parse(ymd);
      return '${d.day} ${months[d.month - 1]}';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: kEmberColor.withValues(alpha: .3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('BRAISES', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
          const InfoDot(kRuleEmbers, size: 16),
          const Spacer(),
          Text('${ledger.available} sur $kEmberCap', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kEmberColor)),
        ]),
        const SizedBox(height: 8),
        EmberDots(stock: ledger.available, label: ledger.available >= kEmberCap ? 'réserve pleine' : 'prochaine : une journée parfaite'),
        if (events.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Text(e.kind == EmberEventKind.earned ? '+1' : '−1', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kEmberColor)),
                ),
                Expanded(
                  child: Text(
                    e.kind == EmberEventKind.earned ? 'Journée parfaite' : '${names[e.activityId] ?? 'Série'} rallumée',
                    style: const TextStyle(fontSize: 13, color: kBText),
                  ),
                ),
                Text(date(e.ymd), style: const TextStyle(fontSize: 12, color: kBText3)),
              ]),
            ),
        ],
      ]),
    );
  }
}
