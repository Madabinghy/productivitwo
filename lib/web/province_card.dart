import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

/// Carte d'une PROVINCE (= domaine de vie) pour le dashboard Royaume.
/// Niveau / prospérité / menace, tous DÉRIVÉS du vrai travail (extension Kingdom).
class ProvinceCard extends StatelessWidget {
  final AppLogic logic;
  final Domain domain;
  final VoidCallback onTap;
  const ProvinceCard(
      {required this.logic,
      required this.domain,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = domainColor(domain.id, logic.state.activeDomains) ?? cs.primary;
    final level = logic.provinceLevel(domain.id);
    final prosp = logic.provinceProsperity(domain.id);
    final net = prosp.leaves - prosp.webs;
    final threat = logic.provinceThreat(domain.id);
    final acts = logic.provinceActivityCount(domain.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(domain.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            _chip('Niv. $level', color, cs),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _stat('🏛️', '$acts ${acts > 1 ? 'activités' : 'activité'}', cs),
            const SizedBox(width: 14),
            _stat(
              net >= 0 ? '🍃' : '🕸️',
              net >= 0 ? '+$net prospérité' : '${-net} déclin',
              cs,
              color: net >= 0 ? Colors.green.shade600 : cs.error,
            ),
            const Spacer(),
            if (threat > 0)
              _chip('⚔️ $threat', cs.error, cs)
            else
              _chip('calme', Colors.green.shade600, cs),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(String emoji, String text, ColorScheme cs, {Color? color}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color ?? cs.onSurface.withOpacity(.7))),
      ]);

  Widget _chip(String text, Color c, ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withOpacity(.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: c)),
      );
}
