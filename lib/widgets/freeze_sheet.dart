import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/rest_periods.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;

/// Gel d'une activité ou d'une routine sur une période (2026-11-02, retour
/// user : vacances sans intervention, « pas avant lundi »). Les jours gelés ne
/// réclament rien et ne cassent rien (séries, Métronome, Montre suisse,
/// journée parfaite) — même mécanisme que la veille d'un domaine, pour UNE chose.

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _label(String ymd) {
  final d = DateTime.parse(ymd);
  return '${d.day} ${_months[d.month - 1]}';
}

/// « Gelée jusqu'au 3 janv. » / « Gelée du 20 déc. au 3 janv. » (à venir).
String freezeLabel(RestPeriod p, String todayYmd) =>
    p.from.compareTo(todayYmd) <= 0 ? 'Gelée jusqu\'au ${_label(p.to)}' : 'Gelée du ${_label(p.from)} au ${_label(p.to)}';

/// Petit bouton à poser en haut d'une fiche : « ❄ Geler » ou l'état du gel
/// (tap = dégeler ou changer la période).
class FreezeChip extends StatelessWidget {
  final AppLogic logic;
  final Activity activity;
  final VoidCallback? onChanged;
  const FreezeChip({super.key, required this.logic, required this.activity, this.onChanged});

  static const ice = Color(0xFF7FC8F8);

  @override
  Widget build(BuildContext context) {
    final p = logic.freezeOf(activity.id);
    final today = logic.livedTodayYmd;
    return ActionChip(
      avatar: Icon(Icons.ac_unit, size: 16, color: ice),
      label: Text(p == null ? 'Geler une période' : freezeLabel(p, today)),
      side: BorderSide(color: ice.withValues(alpha: p == null ? .35 : .8)),
      backgroundColor: p == null ? null : ice.withValues(alpha: .12),
      onPressed: () async {
        await showFreezeSheet(context, logic: logic, activity: activity);
        onChanged?.call();
      },
    );
  }
}

Future<void> showFreezeSheet(BuildContext context, {required AppLogic logic, required Activity activity}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final today = DateTime.parse(logic.livedTodayYmd);
      final current = logic.freezeOf(activity.id);
      // « Pas avant lundi » = gelée jusqu'à dimanche inclus.
      final sunday = today.add(Duration(days: DateTime.sunday - today.weekday));
      Future<void> apply(DateTime from, DateTime to) async {
        Navigator.pop(ctx);
        await logic.freezeActivity(activity.id, _ymd(from), _ymd(to));
        final p = logic.freezeOf(activity.id);
        if (p != null && context.mounted) {
          ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
            content: Text('${activity.name} · ${freezeLabel(p, logic.livedTodayYmd).toLowerCase()} · rien ne se casse'),
            duration: const Duration(seconds: 4),
          ));
        }
      }

      Widget preset(String title, String detail, DateTime from, DateTime to) => ListTile(
            leading: const Icon(Icons.ac_unit, color: FreezeChip.ice),
            title: Text(title),
            subtitle: Text(detail),
            onTap: () => apply(from, to),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Geler « ${activity.name} »', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Les jours gelés ne réclament rien et ne cassent rien : série, Métronome, Montre suisse, journée parfaite.',
                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .6))),
            if (current != null) ...[
              const SizedBox(height: 10),
              Card(
                color: FreezeChip.ice.withValues(alpha: .12),
                child: ListTile(
                  leading: const Icon(Icons.ac_unit, color: FreezeChip.ice),
                  title: Text(freezeLabel(current, logic.livedTodayYmd)),
                  trailing: TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await logic.unfreezeActivity(activity.id);
                    },
                    child: const Text('Dégeler'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            preset('Aujourd\'hui seulement', _label(_ymd(today)), today, today),
            preset('Pas avant lundi', 'jusqu\'au ${_label(_ymd(sunday))} inclus', today, sunday),
            preset('Une semaine', 'jusqu\'au ${_label(_ymd(today.add(const Duration(days: 6))))}', today, today.add(const Duration(days: 6))),
            preset('Deux semaines', 'jusqu\'au ${_label(_ymd(today.add(const Duration(days: 13))))}', today, today.add(const Duration(days: 13))),
            ListTile(
              leading: const Icon(Icons.date_range, color: FreezeChip.ice),
              title: const Text('Choisir les dates…'),
              subtitle: const Text('vacances, déplacement — peut commencer plus tard'),
              onTap: () async {
                final r = await showDateRangePicker(
                  context: ctx,
                  firstDate: today,
                  lastDate: today.add(const Duration(days: 365)),
                  locale: const Locale('fr', 'FR'),
                  helpText: 'Période gelée',
                );
                if (r == null) return;
                await apply(r.start, r.end);
              },
            ),
          ]),
        ),
      );
    },
  );
}
