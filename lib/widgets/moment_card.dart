
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/ring_painter.dart';

/// « Une carte, une fiche » (2026-10, handoff `docs/specs/une-carte-une-fiche-2026-10`) :
/// la *carte du moment* commune à tous les onglets — étiquette en capitales +
/// pastille, anneau à gauche, titre, ligne « reste / état », UN bouton plein et
/// « Fiche ». Même silhouette que MAINTENANT et « Routine du moment ».
class MomentCard extends StatelessWidget {
  final Color accent;
  final String eyebrow;
  final String? pill;
  final VoidCallback? onPill;
  /// 0..1 ; null = anneau vide.
  final double? ring;
  final Color? ringColor;
  final String ringBig;
  final String ringSmall;
  final String? context_;
  final IconData? contextIcon;
  final String title;
  final String sub;
  final Color? subColor;
  final String primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  /// Bouton plein remplacé par un bouton contour (ex. « Arrêter »).
  final bool primaryOutlined;
  final VoidCallback? onFiche;
  final String ficheLabel;
  final String? chainLabel;
  final VoidCallback? onChain;

  const MomentCard({
    super.key,
    required this.accent,
    required this.eyebrow,
    this.pill,
    this.onPill,
    required this.ring,
    this.ringColor,
    required this.ringBig,
    required this.ringSmall,
    this.context_,
    this.contextIcon,
    required this.title,
    required this.sub,
    this.subColor,
    required this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.primaryOutlined = false,
    this.onFiche,
    this.ficheLabel = 'Fiche',
    this.chainLabel,
    this.onChain,
  });

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(eyebrow,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
          ),
          if (pill != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onPill,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                child: Text(pill!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: accent)),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          MomentRing(value: ring, color: ringColor ?? accent, big: ringBig, small: ringSmall),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (context_ != null)
                Row(children: [
                  Icon(contextIcon ?? Icons.circle, size: contextIcon == null ? 8 : 13, color: accent),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(context_!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.text2))),
                ]),
              const SizedBox(height: 4),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.15, color: pal.text)),
              const SizedBox(height: 5),
              Text(sub,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: subColor == null ? null : FontWeight.w700,
                      color: subColor ?? pal.text3,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _primary(pal)),
          if (onFiche != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: onFiche,
                style: OutlinedButton.styleFrom(
                    foregroundColor: pal.text2,
                    side: BorderSide(color: pal.track),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                child: Text(ficheLabel),
              ),
            ),
          ],
        ]),
        if (chainLabel != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onChain,
            style: TextButton.styleFrom(foregroundColor: accent, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            icon: const Icon(Icons.playlist_play_rounded, size: 22),
            label: Text(chainLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ]),
    );
  }

  Widget _primary(NowPalette pal) {
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      if (primaryIcon != null) ...[Icon(primaryIcon, size: 20), const SizedBox(width: 6)],
      Flexible(child: Text(primaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
    if (primaryOutlined) {
      return SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: onPrimary,
          style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: .5)),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          child: label,
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPrimary,
        style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: pal.track,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        child: label,
      ),
    );
  }
}

/// Anneau 96 px de la carte du moment : valeur 0..1, grand chiffre + légende.
class MomentRing extends StatelessWidget {
  final double? value;
  final Color color;
  final String big;
  final String small;
  final double size;
  const MomentRing({super.key, required this.value, required this.color, required this.big, required this.small, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: RingPainter(progress: (value ?? 0).clamp(0.0, 1.0), color: color, stroke: 9, trackColor: pal.track, cap: StrokeCap.round),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(big,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
          Text(small, style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: pal.text3)),
        ]),
      ]),
    );
  }
}
