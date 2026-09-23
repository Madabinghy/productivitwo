import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

/// Carte coach ÉVÉNEMENTIELLE en tête de l'onglet « Maintenant ». Rend un
/// [CoachMoment] calculé en local — uniquement « Et ensuite ? » (fin de
/// chrono) et « Dérive détectée » ; l'état normal est l'absence de carte.
/// Apparition / changement en fade + slide léger (200 ms, ease-out).
class CoachMomentCard extends StatelessWidget {
  final CoachMoment moment;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onRenegotiate;
  // « Ignorer » (dérive) : silence jusqu'à demain.
  final VoidCallback? onDismiss;
  // Défi ORION : « Je relève 🔥 » (chrono + alarme + streak).
  final void Function(ScheduleBlock block)? onChallengeAccept;
  // ✓ — coche directe d'une routine sans minuteur (pas de chrono).
  final void Function(ScheduleBlock block)? onCheckRoutine;

  const CoachMomentCard({
    super.key,
    required this.moment,
    this.onLaunch,
    this.onRenegotiate,
    this.onDismiss,
    this.onChallengeAccept,
    this.onCheckRoutine,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(0, .04), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: moment.hidden
          ? const SizedBox.shrink(key: ValueKey('coach-hidden'))
          : _Card(
              key: ValueKey('coach-${moment.type}-${moment.message.hashCode}'),
              moment: moment,
              onLaunch: onLaunch,
              onRenegotiate: onRenegotiate,
              onDismiss: onDismiss,
              onChallengeAccept: onChallengeAccept,
              onCheckRoutine: onCheckRoutine,
            ),
    );
  }
}

class _Card extends StatelessWidget {
  final CoachMoment moment;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onRenegotiate;
  final VoidCallback? onDismiss;
  final void Function(ScheduleBlock block)? onChallengeAccept;
  final void Function(ScheduleBlock block)? onCheckRoutine;

  const _Card({
    super.key,
    required this.moment,
    this.onLaunch,
    this.onRenegotiate,
    this.onDismiss,
    this.onChallengeAccept,
    this.onCheckRoutine,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alert = moment.tone == CoachTone.alert;
    // Sur mobile : mapper vers colorScheme (jamais les hex des maquettes web).
    final accent = alert ? _amber(cs) : cs.primary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: accent.withOpacity(.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: accent.withOpacity(alert ? .45 : .30), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Micro-label (tag)
          Row(
            children: [
              if (alert)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber_rounded,
                      size: 14, color: accent),
                ),
              Flexible(
                child: Text(
                  moment.tagLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (moment.title != null) ...[
            const SizedBox(height: 8),
            Text(moment.title!,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 8),
          Text(
            moment.message,
            style: TextStyle(
                fontSize: 14, height: 1.4, color: cs.onSurface.withOpacity(.9)),
          ),
          if (moment.actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Actions(
              actions: moment.actions,
              accent: accent,
              onLaunch: onLaunch,
              onRenegotiate: onRenegotiate,
              onDismiss: onDismiss,
              onChallengeAccept: onChallengeAccept,
              onCheckRoutine: onCheckRoutine,
            ),
          ],
        ],
      ),
    );
  }

  // Ambre d'alerte dérivé du thème (tertiary si chaud, sinon fallback ambre).
  Color _amber(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? const Color(0xFFFFB74D) : const Color(0xFFEF8B1F);
}

class _Actions extends StatelessWidget {
  final List<CoachAction> actions;
  final Color accent;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onRenegotiate;
  final VoidCallback? onDismiss;
  final void Function(ScheduleBlock block)? onChallengeAccept;
  final void Function(ScheduleBlock block)? onCheckRoutine;

  const _Actions({
    required this.actions,
    required this.accent,
    this.onLaunch,
    this.onRenegotiate,
    this.onDismiss,
    this.onChallengeAccept,
    this.onCheckRoutine,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [for (final a in actions) _button(context, a)],
    );
  }

  Widget _button(BuildContext context, CoachAction a) {
    final cs = Theme.of(context).colorScheme;
    final isPrimary = a.kind == CoachActionKind.launchBlock ||
        a.kind == CoachActionKind.challengeAccept;
    final onTap = _handlerFor(a);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    final icon = switch (a.kind) {
      CoachActionKind.launchBlock => Icons.play_arrow_rounded,
      CoachActionKind.renegotiate => Icons.tune_rounded,
      CoachActionKind.dismiss => Icons.skip_next_outlined,
      CoachActionKind.challengeAccept => Icons.local_fire_department_rounded,
      CoachActionKind.checkRoutine => Icons.check_rounded,
    };
    // « Ignorer » : lien discret sous les vrais CTA.
    if (a.kind == CoachActionKind.dismiss) {
      return TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(a.label),
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface.withOpacity(.6),
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: shape,
        ),
      );
    }
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(a.label),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: cs.surface,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: shape,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(a.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withOpacity(.5)),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: shape,
      ),
    );
  }

  VoidCallback? _handlerFor(CoachAction a) {
    switch (a.kind) {
      case CoachActionKind.launchBlock:
        return a.block != null && onLaunch != null
            ? () => onLaunch!(a.block!)
            : null;
      case CoachActionKind.renegotiate:
        return a.block != null && onRenegotiate != null
            ? () => onRenegotiate!(a.block!)
            : null;
      case CoachActionKind.dismiss:
        return onDismiss;
      case CoachActionKind.challengeAccept:
        return a.block != null && onChallengeAccept != null
            ? () => onChallengeAccept!(a.block!)
            : null;
      case CoachActionKind.checkRoutine:
        return a.block != null && onCheckRoutine != null
            ? () => onCheckRoutine!(a.block!)
            : null;
    }
  }
}
