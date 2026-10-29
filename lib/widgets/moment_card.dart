
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/ring_painter.dart';

/// Geste rare d'une carte du moment, rangé dans la feuille « ⋯ Autres ».
class MomentAction {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  /// Sous-titre (« retirer la dernière occurrence »).
  final String? hint;
  final bool destructive;
  const MomentAction(this.label, {this.icon, this.onTap, this.hint, this.destructive = false});
}

/// Légende sous le visuel : texte à gauche, chiffre à droite.
class MomentLegend extends StatelessWidget {
  final String left;
  final String? right;
  const MomentLegend(this.left, {super.key, this.right});

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(child: Text(left, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.text3))),
        if (right != null) ...[
          const SizedBox(width: 8),
          Text(right!, style: TextStyle(fontSize: 11.5, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ]),
    );
  }
}

/// Feuille « Autres gestes » commune aux cartes du moment.
Future<void> showMomentActions(BuildContext context, {required String title, required List<MomentAction> actions}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: cs.onSurface.withValues(alpha: .5))),
          ),
          for (final a in actions)
            ListTile(
              dense: true,
              enabled: a.onTap != null,
              leading: a.icon == null ? null : Icon(a.icon, size: 20, color: a.destructive ? cs.error : null),
              title: Text(a.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: a.destructive ? cs.error : null)),
              subtitle: a.hint == null ? null : Text(a.hint!, style: const TextStyle(fontSize: 12)),
              onTap: a.onTap == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      a.onTap!();
                    },
            ),
        ]),
      );
    },
  );
}

/// « Une carte, une fiche » (2026-10, handoff `docs/specs/une-carte-une-fiche-2026-10`) :
/// la *carte du moment* commune à tous les onglets — étiquette en capitales +
/// pastille, anneau à gauche, titre, ligne « reste / état », UN bouton plein et
/// « Fiche ». Même silhouette que MAINTENANT et « Routine du moment ».
/// **Grammaire de Projets** (maquette « Cartes du moment », 2026-10) : une seule
/// ligne de contexte, un [visual] pleine largeur à la place d'une sous-ligne
/// dense, un bouton de deux ou trois mots sur toute la largeur, puis une ligne
/// de liens discrets (fiche · geste secondaire · « ⋯ Autres » → feuille
/// [moreActions]).
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
  /// Bouton fiche en ICÔNE seule (retour user 2026-10-30 : « Détail » prenait
  /// un tiers de la ligne) ; `ficheLabel` devient l'infobulle.
  final IconData? ficheIcon;
  final String? chainLabel;
  final VoidCallback? onChain;
  /// Icône du lien secondaire (défaut : file « Enchaîner ») ; null = texte seul.
  final IconData? chainIcon;
  /// Contenu libre sous la ligne d'état (ex. pilule chrono d'une routine).
  final Widget? detail;
  /// Rangée de gestes sur mesure : remplace le bouton plein + « Fiche ».
  final Widget? actions;
  /// Visuel pleine largeur entre le titre et le bouton (points d'étapes,
  /// briques, barres par jour, frise des blocs).
  final Widget? visual;
  /// Gestes rares → lien « ⋯ Autres » + feuille.
  final List<MomentAction> moreActions;
  /// Titre de la feuille « Autres » (défaut : le titre de la carte).
  final String? moreTitle;

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
    this.ficheIcon,
    this.chainLabel,
    this.onChain,
    this.chainIcon = Icons.playlist_play_rounded,
    this.detail,
    this.actions,
    this.visual,
    this.moreActions = const [],
    this.moreTitle,
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
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onPill,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                  child: Text(pill!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: accent)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        // « Titre d'abord » (maquette validée 2026-10-30) : le titre prend toute
        // la largeur, UNE ligne de contexte dessous (contexte · sous-ligne), et
        // l'anneau passe en miniature en tête de la ligne de progression, le
        // chiffre à côté. Trois lignes de texte au lieu de cinq.
        Text(title,
            softWrap: true,
            style: TextStyle(fontSize: title.length > 60 ? 18 : 21, fontWeight: FontWeight.w700, height: 1.15, color: pal.text)),
        if (context_ != null || sub.isNotEmpty) ...[
          const SizedBox(height: 5),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (context_ != null) ...[
              Padding(
                padding: EdgeInsets.only(top: contextIcon == null ? 5 : 2),
                child: Icon(contextIcon ?? Icons.circle, size: contextIcon == null ? 8 : 13, color: accent),
              ),
              const SizedBox(width: 6),
            ],
            // Plus d'ellipse (retour user 2026-10) : contexte sur trois lignes
            // au plus, titre en entier.
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  if (context_ != null) TextSpan(text: context_, style: TextStyle(color: pal.text2)),
                  if (context_ != null && sub.isNotEmpty) TextSpan(text: ' · ', style: TextStyle(color: pal.text3)),
                  if (sub.isNotEmpty)
                    TextSpan(
                        text: sub,
                        style: TextStyle(color: subColor ?? pal.text3, fontWeight: subColor == null ? null : FontWeight.w700)),
                ]),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.3, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ]),
        ],
        if (detail != null) ...[const SizedBox(height: 8), detail!],
        if (ring != null || ringBig.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            MomentRing(value: ring, color: ringColor ?? accent, big: '', small: '', size: 30, stroke: 5),
            const SizedBox(width: 10),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: ringBig, style: TextStyle(fontWeight: FontWeight.w800, color: pal.text)),
                if (ringSmall.isNotEmpty) TextSpan(text: ' ${ringSmall.toLowerCase()}', style: TextStyle(color: pal.text3)),
              ]),
              style: TextStyle(fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ]),
        ],
        if (visual != null) ...[const SizedBox(height: 10), visual!],
        const SizedBox(height: 14),
        if (actions != null)
          actions!
        else ...[
          _primary(pal),
          if (onFiche != null || chainLabel != null || moreActions.isNotEmpty) _links(context, pal),
        ],
      ]),
    );
  }

  /// Sous le bouton plein : deux boutons contour (fiche · geste secondaire,
  /// retour user 2026-10 : « plus joli que du texte ») et « ⋯ Autres » en lien.
  Widget _links(BuildContext context, NowPalette pal) {
    Widget btn(String label, VoidCallback? onTap, {IconData? icon, Color? color}) => Expanded(
          child: SizedBox(
            height: 42,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color ?? pal.text2,
                side: BorderSide(color: (color ?? pal.text2).withValues(alpha: color == null ? .25 : .45)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 5)],
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        );
    Widget iconBtn(IconData icon, String label, VoidCallback? onTap) => Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: SizedBox(
              width: 52,
              height: 42,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: pal.text2,
                  side: BorderSide(color: pal.text2.withValues(alpha: .25)),
                  shape: const StadiumBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: Icon(icon, size: 19),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        if (onFiche != null) ficheIcon != null ? iconBtn(ficheIcon!, ficheLabel, onFiche) : btn(ficheLabel, onFiche),
        if (onFiche != null && chainLabel != null) const SizedBox(width: 8),
        if (chainLabel != null) btn(chainLabel!, onChain, icon: chainIcon, color: accent),
        if (moreActions.isNotEmpty) ...[
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => showMomentActions(context, title: moreTitle ?? title, actions: moreActions),
            style: TextButton.styleFrom(
              foregroundColor: pal.text3,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            child: const Text('⋯ Autres'),
          ),
        ],
      ]),
    );
  }

  Widget _primary(NowPalette pal) {
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      if (primaryIcon != null) ...[Icon(primaryIcon, size: 20), const SizedBox(width: 6)],
      Flexible(child: Text(primaryLabel, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
    ]);
    if (primaryOutlined) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: OutlinedButton(
          onPressed: onPrimary,
          style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: .5)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
          child: label,
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: FilledButton(
        onPressed: onPrimary,
        style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: pal.track,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
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
  final double stroke;
  const MomentRing({super.key, required this.value, required this.color, required this.big, required this.small, this.size = 96, this.stroke = 9});

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: RingPainter(progress: (value ?? 0).clamp(0.0, 1.0), color: color, stroke: stroke, trackColor: pal.track, cap: StrokeCap.round),
        ),
        if (big.isNotEmpty || small.isNotEmpty)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(big,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(small, style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: pal.text3)),
          ]),
      ]),
    );
  }
}
