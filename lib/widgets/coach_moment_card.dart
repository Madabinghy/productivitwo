import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

/// Carte coach contextuelle en tête de l'onglet « Maintenant ». Rend un
/// [CoachMoment] calculé en local. Apparition / changement en fade + slide léger
/// (200 ms, ease-out). Masquée hors des fenêtres (nuit) ou moment `hidden`.
class CoachMomentCard extends StatelessWidget {
  final CoachMoment moment;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onRenegotiate;
  final VoidCallback? onOpenDayReview;
  // CTA de transition (« Attaquer la journée »…) : avance manuellement au
  // moment suivant sans attendre l'horloge.
  final void Function(CoachMomentType target)? onAdvance;
  // « Planifier · 2 min » (journée non planifiée) → écran de planification.
  final VoidCallback? onPlanDay;
  // « À la volée » → masque la carte pour la matinée.
  final VoidCallback? onDismiss;
  // Carte midi menu (15c) : ✓ Mangé / « Autre chose » (glisse le menu d'un jour).
  final void Function(String artifactId)? onMealEaten;
  final void Function(String artifactId)? onMealShift;
  // « Lire le rapport — 3 min » (16a) → écran du rapport hebdo.
  final VoidCallback? onOpenWeeklyReport;
  // Nudge domaines (Partie D) : nommage in-place / session sur place.
  final VoidCallback? onNameDomains;
  final VoidCallback? onNameTonight;
  final void Function(String domain, {bool short})? onStartSession;
  final VoidCallback? onPoseSessions;
  // « Terminer l'après-midi — mode soirée » (23c) : bascule réversible.
  final VoidCallback? onEndAfternoon;
  // « Je suis dispo » — efface la fenêtre d'indisponibilité déclarée.
  final VoidCallback? onAvailableNow;
  // « Planifions — [routine] » → date/heure de la prochaine exécution.
  final void Function(ScheduleBlock block)? onPlanNext;

  const CoachMomentCard({
    super.key,
    required this.moment,
    this.onLaunch,
    this.onRenegotiate,
    this.onOpenDayReview,
    this.onAdvance,
    this.onPlanDay,
    this.onDismiss,
    this.onMealEaten,
    this.onMealShift,
    this.onOpenWeeklyReport,
    this.onNameDomains,
    this.onNameTonight,
    this.onStartSession,
    this.onPoseSessions,
    this.onEndAfternoon,
    this.onAvailableNow,
    this.onPlanNext,
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
              onOpenDayReview: onOpenDayReview,
              onAdvance: onAdvance,
              onPlanDay: onPlanDay,
              onDismiss: onDismiss,
              onMealEaten: onMealEaten,
              onMealShift: onMealShift,
              onOpenWeeklyReport: onOpenWeeklyReport,
              onNameDomains: onNameDomains,
              onNameTonight: onNameTonight,
              onStartSession: onStartSession,
              onPoseSessions: onPoseSessions,
              onEndAfternoon: onEndAfternoon,
              onAvailableNow: onAvailableNow,
              onPlanNext: onPlanNext,
            ),
    );
  }
}

class _Card extends StatelessWidget {
  final CoachMoment moment;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onRenegotiate;
  final VoidCallback? onOpenDayReview;
  final void Function(CoachMomentType target)? onAdvance;
  final VoidCallback? onPlanDay;
  final VoidCallback? onDismiss;
  final void Function(String artifactId)? onMealEaten;
  final void Function(String artifactId)? onMealShift;
  final VoidCallback? onOpenWeeklyReport;
  final VoidCallback? onNameDomains;
  final VoidCallback? onNameTonight;
  final void Function(String domain, {bool short})? onStartSession;
  final VoidCallback? onPoseSessions;
  final VoidCallback? onEndAfternoon;
  final VoidCallback? onAvailableNow;
  final void Function(ScheduleBlock block)? onPlanNext;

  const _Card({
    super.key,
    required this.moment,
    this.onLaunch,
    this.onRenegotiate,
    this.onOpenDayReview,
    this.onAdvance,
    this.onPlanDay,
    this.onDismiss,
    this.onMealEaten,
    this.onMealShift,
    this.onOpenWeeklyReport,
    this.onNameDomains,
    this.onNameTonight,
    this.onStartSession,
    this.onPoseSessions,
    this.onEndAfternoon,
    this.onAvailableNow,
    this.onPlanNext,
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
          // Chips domaines du nudge (21b) : « Santé ✓ · Business · Perso ».
          if (moment.chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in moment.chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: c.done
                              ? cs.primary.withOpacity(.5)
                              : cs.onSurface.withOpacity(.25)),
                      color: c.done
                          ? cs.primary.withOpacity(.08)
                          : Colors.transparent,
                    ),
                    child: Text(
                      c.done ? '${c.label} ✓' : c.label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: c.done
                              ? cs.primary
                              : cs.onSurface.withOpacity(.6)),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            moment.message,
            style: TextStyle(
                fontSize: 14, height: 1.4, color: cs.onSurface.withOpacity(.9)),
          ),
          if (moment.stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            _StatsRow(stats: moment.stats, accent: accent),
          ],
          if (moment.actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Actions(
              actions: moment.actions,
              accent: accent,
              onLaunch: onLaunch,
              onRenegotiate: onRenegotiate,
              onOpenDayReview: onOpenDayReview,
              onAdvance: onAdvance,
              onPlanDay: onPlanDay,
              onDismiss: onDismiss,
              onMealEaten: onMealEaten,
              onMealShift: onMealShift,
              onOpenWeeklyReport: onOpenWeeklyReport,
              onNameDomains: onNameDomains,
              onNameTonight: onNameTonight,
              onStartSession: onStartSession,
              onPoseSessions: onPoseSessions,
              onEndAfternoon: onEndAfternoon,
              onAvailableNow: onAvailableNow,
              onPlanNext: onPlanNext,
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

class _StatsRow extends StatelessWidget {
  final List<StatItem> stats;
  final Color accent;
  const _StatsRow({required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 22,
      runSpacing: 10,
      children: [
        for (final s in stats)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                s.label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .4,
                    color: cs.onSurface.withOpacity(.5)),
              ),
              if (s.sub != null)
                SizedBox(
                  width: 120,
                  child: Text(
                    s.sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface.withOpacity(.65)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final List<CoachAction> actions;
  final Color accent;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onRenegotiate;
  final VoidCallback? onOpenDayReview;
  final void Function(CoachMomentType target)? onAdvance;
  final VoidCallback? onPlanDay;
  final VoidCallback? onDismiss;
  final void Function(String artifactId)? onMealEaten;
  final void Function(String artifactId)? onMealShift;
  final VoidCallback? onOpenWeeklyReport;
  final VoidCallback? onNameDomains;
  final VoidCallback? onNameTonight;
  final void Function(String domain, {bool short})? onStartSession;
  final VoidCallback? onPoseSessions;
  final VoidCallback? onEndAfternoon;
  final VoidCallback? onAvailableNow;
  final void Function(ScheduleBlock block)? onPlanNext;

  const _Actions({
    required this.actions,
    required this.accent,
    this.onLaunch,
    this.onRenegotiate,
    this.onOpenDayReview,
    this.onAdvance,
    this.onPlanDay,
    this.onDismiss,
    this.onMealEaten,
    this.onMealShift,
    this.onOpenWeeklyReport,
    this.onNameDomains,
    this.onNameTonight,
    this.onStartSession,
    this.onPoseSessions,
    this.onEndAfternoon,
    this.onAvailableNow,
    this.onPlanNext,
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
        a.kind == CoachActionKind.planDay ||
        a.kind == CoachActionKind.openWeeklyReport ||
        a.kind == CoachActionKind.nameDomains ||
        a.kind == CoachActionKind.startSession ||
        a.kind == CoachActionKind.startSessionShort ||
        a.kind == CoachActionKind.planNext;
    // Secondaires du nudge / bascule système : liens discrets sous le CTA.
    final isQuiet = a.kind == CoachActionKind.nameTonight ||
        a.kind == CoachActionKind.poseSessions ||
        a.kind == CoachActionKind.endAfternoon ||
        (a.kind == CoachActionKind.dismiss &&
            a.label.startsWith('Garder'));
    final onTap = _handlerFor(a);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    final icon = switch (a.kind) {
      CoachActionKind.launchBlock => Icons.play_arrow_rounded,
      CoachActionKind.openDayReview => Icons.nightlight_round,
      CoachActionKind.renegotiate => Icons.tune_rounded,
      CoachActionKind.advanceMoment => Icons.arrow_forward_rounded,
      CoachActionKind.planDay => Icons.edit_calendar_outlined,
      CoachActionKind.dismiss => Icons.skip_next_outlined,
      CoachActionKind.mealEaten => Icons.check_rounded,
      CoachActionKind.mealShift => Icons.swap_horiz_rounded,
      CoachActionKind.openWeeklyReport => Icons.insights_rounded,
      CoachActionKind.nameDomains => Icons.flag_rounded,
      CoachActionKind.nameTonight => Icons.nightlight_outlined,
      CoachActionKind.startSession => Icons.auto_awesome,
      CoachActionKind.startSessionShort => Icons.bolt_rounded,
      CoachActionKind.poseSessions => Icons.event_available_outlined,
      CoachActionKind.endAfternoon => Icons.nights_stay_outlined,
      CoachActionKind.availableNow => Icons.notifications_active_outlined,
      CoachActionKind.planNext => Icons.event_available_outlined,
    };
    // Transition de moment / secondaires du nudge : bouton discret (texte).
    if (a.kind == CoachActionKind.advanceMoment || isQuiet) {
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
      case CoachActionKind.openDayReview:
        return onOpenDayReview;
      case CoachActionKind.advanceMoment:
        return a.target != null && onAdvance != null
            ? () => onAdvance!(a.target!)
            : null;
      case CoachActionKind.planDay:
        return onPlanDay;
      case CoachActionKind.dismiss:
        return onDismiss;
      case CoachActionKind.mealEaten:
        return a.artifactId != null && onMealEaten != null
            ? () => onMealEaten!(a.artifactId!)
            : null;
      case CoachActionKind.mealShift:
        return a.artifactId != null && onMealShift != null
            ? () => onMealShift!(a.artifactId!)
            : null;
      case CoachActionKind.openWeeklyReport:
        return onOpenWeeklyReport;
      case CoachActionKind.nameDomains:
        return onNameDomains;
      case CoachActionKind.nameTonight:
        return onNameTonight;
      case CoachActionKind.startSession:
        return a.domain != null && onStartSession != null
            ? () => onStartSession!(a.domain!)
            : null;
      case CoachActionKind.startSessionShort:
        return a.domain != null && onStartSession != null
            ? () => onStartSession!(a.domain!, short: true)
            : null;
      case CoachActionKind.poseSessions:
        return onPoseSessions;
      case CoachActionKind.endAfternoon:
        return onEndAfternoon;
      case CoachActionKind.availableNow:
        return onAvailableNow;
      case CoachActionKind.planNext:
        return a.block != null && onPlanNext != null
            ? () => onPlanNext!(a.block!)
            : null;
    }
  }
}
