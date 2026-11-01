import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/run_session_store.dart';
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/run_session.dart';
import 'package:productivitwo_v1/utils/sniper.dart' show kSniperKind;
import 'package:productivitwo_v1/widgets/sniper_screen.dart' show kSniperAccent, showSniperScreen;
import 'package:productivitwo_v1/widgets/guerilla_screen.dart' show kGuerillaAccent, showGuerillaScreen;
import 'package:productivitwo_v1/widgets/offensive_screen.dart' show kOffensiveAccent, showOffensiveScreen;

/// Une Guérilla / Offensive quittée en route (app fermée, écran quitté) :
/// rouverte d'elle-même au premier affichage après un lancement de l'app ;
/// sinon « Reprendre » rouvre l'écran au coup suivant, « Terminer ici » la clôt
/// telle quelle (ses coups comptent). Rien quand aucune n'attend ; une
/// session expirée (autre journée, 45 min sans rien) est close en silence.
class PendingRunCard extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  const PendingRunCard({super.key, required this.logic, this.badges});

  @override
  State<PendingRunCard> createState() => _PendingRunCardState();
}

class _PendingRunCardState extends State<PendingRunCard> {
  /// Une fois par lancement de l'app : la session en attente se rouvre d'elle-même.
  static bool _autoResumed = false;

  @override
  void initState() {
    super.initState();
    RunSessionStore.live(widget.logic).then((p) {
      if (!mounted) return;
      setState(() {});
      if (p != null && !_autoResumed) {
        _autoResumed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resume(p);
        });
      }
    });
  }

  Future<void> _resume(PendingRun p) async {
    if (p.kind == kGuerillaKind) {
      await showGuerillaScreen(context, widget.logic, resume: p);
    } else if (p.kind == kSniperKind) {
      await showSniperScreen(context, widget.logic, badges: widget.badges, resume: p);
    } else {
      await showOffensiveScreen(context, widget.logic, resume: p);
    }
    if (mounted) setState(() {});
  }

  Future<void> _close(PendingRun p) async {
    await RunSessionStore.closeAsIs(widget.logic, p);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = RunSessionStore.current;
    if (p == null || !p.isLive(DateTime.now(), widget.logic.livedTodayYmd)) return const SizedBox.shrink();
    final guerilla = p.kind == kGuerillaKind;
    final sniper = p.kind == kSniperKind;
    final accent = guerilla ? kGuerillaAccent : (sniper ? kSniperAccent : kOffensiveAccent);
    final cs = Theme.of(context).colorScheme;
    final at = '${p.lastActiveAt.hour.toString().padLeft(2, '0')}:${p.lastActiveAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(guerilla ? Icons.bolt : (sniper ? Icons.gps_fixed : Icons.north_east), size: 18, color: cs.brightness == Brightness.dark ? accent : cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text((sniper ? 'Sniper en cours · ${p.done} cible${p.done > 1 ? 's' : ''}' : pendingRunLabel(p, name: guerilla ? 'Guérilla' : 'Offensive')).toUpperCase(),
                style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .7))),
          ),
        ]),
        const SizedBox(height: 4),
        Text(sniper ? 'Quitté à $at. Il reprend au tir suivant.' : 'Quittée à $at. Elle reprend au coup suivant.', style: TextStyle(fontSize: 13.5, color: cs.onSurface.withValues(alpha: .75))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => _resume(p),
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: const Color(0xFF141C0C), minimumSize: const Size.fromHeight(44)),
              child: const Text('Reprendre', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _close(p),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: const Text('Terminer ici'),
            ),
          ),
        ]),
      ]),
    );
  }
}
