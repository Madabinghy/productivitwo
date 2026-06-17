import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/pulse.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

// ── Helpers de la ligne calendrier (semaine glissante) sur la carte de combat ──
const _kWeekLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
List<String> _ctWeekLetters() {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return [
    for (var i = 0; i < 7; i++)
      _kWeekLetters[today.subtract(Duration(days: 6 - i)).weekday - 1]
  ];
}

String _ctTokenEmoji(String t, {required bool scorpion}) => t == 'flame'
    ? '🔥'
    : t == 'spider'
        ? (scorpion ? '🦂' : '🕷️')
        : ''; // 'leaf' (fait) → case vide, plus clean

// Bleu (≥5/7) → jaune (≥3/7) → rouge : santé de la tour.
Color _ctLifeColor(double f) => f >= 5 / 7
    ? const Color(0xFF4FA3FF)
    : (f >= 3 / 7 ? const Color(0xFFF5C518) : const Color(0xFFFF2B2B));

/// Sheet (par-dessus le combat) listant les actions de la tâche-serpent à
/// cocher. Chaque coche = −1 ❤️ (persistée) ; tout coché → ferme le sheet, et la
/// carte de combat déclenche la mise à mort. [onChanged] rafraîchit le combat.
Future<void> _showTaskActionsSheet(
  BuildContext context,
  AppLogic logic,
  FirestoreSync sync,
  String taskId, {
  VoidCallback? onChanged,
}) async {
  Project? project;
  ProjectTask? task;
  for (final p in logic.currentProjects) {
    for (final t in p.tasks) {
      if (t.id == taskId) {
        project = p;
        task = t;
        break;
      }
    }
    if (task != null) break;
  }
  if (project == null || task == null) return;
  final proj = project;
  final tsk = task;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
      final cs = Theme.of(sheetCtx).colorScheme;
      final actions = tsk.actions;
      final done = actions.where((a) => a.done).length;
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text(tsk.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(sheetCtx)),
            ]),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('$done / ${actions.length} actions faites — ❤️ à zéro = serpent vaincu',
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in actions)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: a.done,
                      activeColor: Colors.green,
                      title: Text(a.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: a.done
                                ? cs.onSurface.withOpacity(.4)
                                : cs.onSurface,
                            decoration:
                                a.done ? TextDecoration.lineThrough : null,
                          )),
                      onChanged: (v) async {
                        a.done = v ?? false;
                        a.doneAt = a.done ? DateTime.now() : null;
                        await sync.saveProjectTasks(proj.id, proj.tasks);
                        onChanged?.call();
                        if (actions.isNotEmpty &&
                            actions.every((x) => x.done)) {
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        } else {
                          setSheet(() {});
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }),
  );
}

/// Carte de COMBAT « vrai item » (PV) — ouvrable depuis la map OU « Mon or ».
/// On FRAPPE en faisant le vrai travail spécifique (cœurs ❤️, ✅ = éliminés).
/// « Ouvrir le feu » = cinématique de tourelle + dégât au cœur (routine) ;
/// échelle minuteur pour les activités-temps, checklist pour les tâches.
/// [onChanged] : rafraîchir l'appelant après une action. [onLaunchedTimer] : le
/// caller ferme son conteneur quand on lance un minuteur (pour voir le décompte).
/// Wrapper modal historique : ouvre la carte de combat en pop-up centré.
/// Conserve l'API d'origine (mobile + autres appels). L'UI vit désormais dans
/// [BacklogCombatPanel], réutilisable en ENCART (ex. colonne droite du Monde).
Future<void> showBacklogCombat(
  BuildContext context,
  AppLogic logic,
  FirestoreSync sync,
  String type,
  String itemId, {
  VoidCallback? onChanged,
  VoidCallback? onLaunchedTimer,
}) async {
  final rootContext = context;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Combat',
    barrierColor: Colors.black.withOpacity(.65),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogCtx, a1, a2) => SafeArea(
      child: Center(
        // Material requis : sans lui, les Text sans ancêtre DefaultTextStyle
        // s'affichent avec le double-souligné JAUNE de debug de Flutter.
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: BacklogCombatPanel(
                logic: logic,
                sync: sync,
                type: type,
                itemId: itemId,
                rootContext: rootContext,
                onChanged: onChanged,
                onLaunchedTimer: onLaunchedTimer,
                onClose: () => Navigator.pop(dialogCtx),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Carte de combat d'un nuisible — extraite de sa modale pour s'afficher soit en
/// pop-up (via [showBacklogCombat]), soit en ENCART (colonne droite du Monde).
/// [onClose] ferme la carte (pop en modale, clear d'état en encart).
class BacklogCombatPanel extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final String type;
  final String itemId;
  final VoidCallback onClose;
  final VoidCallback? onChanged;
  final VoidCallback? onLaunchedTimer;
  final BuildContext? rootContext;
  /// Version condensée (sprite/cœurs/espacements réduits) pour un encart étroit.
  final bool compact;
  const BacklogCombatPanel({
    super.key,
    required this.logic,
    required this.sync,
    required this.type,
    required this.itemId,
    required this.onClose,
    this.onChanged,
    this.onLaunchedTimer,
    this.rootContext,
    this.compact = false,
  });
  @override
  State<BacklogCombatPanel> createState() => _BacklogCombatPanelState();
}

class _BacklogCombatPanelState extends State<BacklogCombatPanel>
    with SingleTickerProviderStateMixin {
  // ── Cinématique de canon : la tourelle du calendrier tire sur le nuisible du
  //    jour (dernière colonne) AVANT d'appliquer le coup. ──
  late final AnimationController _fireCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..addListener(() {
      if (mounted) setState(() {});
    });
  bool _firing = false;

  @override
  void dispose() {
    _fireCtrl.dispose();
    super.dispose();
  }

  // Encart le calendrier (tourelle + 7 jours) dans un Stack et fait voler une
  // boule de feu de la tourelle jusqu'à la case du JOUR pendant le tir.
  Widget _cannonRow(int dayCount, Widget row) {
    const turretColW = 44.0;
    const cellW = 30.0; // 28 + marge all(1)
    const turretCx = 22.0;
    final todayCx = turretColW + (dayCount - 1) * cellW + cellW / 2;
    final t = _fireCtrl.value;
    final fx = turretCx + (todayCx - turretCx) * t;
    final dy = -sin(t * pi) * 14.0;
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          row,
          if (_firing) ...[
            Positioned(
              left: fx - 9,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Opacity(
                    opacity: t < 0.96 ? 1 : 0,
                    child: const Text('🔥',
                        style: TextStyle(
                            fontSize: 16, decoration: TextDecoration.none)),
                  ),
                ),
              ),
            ),
            if (t > 0.82)
              Positioned(
                left: todayCx - 11,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('💥',
                      style: TextStyle(
                          fontSize: 18 + (t - 0.82) * 18,
                          decoration: TextDecoration.none)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logic = widget.logic;
    final sync = widget.sync;
    final type = widget.type;
    final itemId = widget.itemId;
    final onChanged = widget.onChanged;
    final onLaunchedTimer = widget.onLaunchedTimer;
    final rootCtx = widget.rootContext ?? context;
    final compact = widget.compact;
    void setLocal(VoidCallback fn) => setState(fn);

    int timerMin = 0;
    String linkedId = '';
    if (type == 'spider') {
      for (final x in logic.state.activities) {
        if (x.id == itemId) {
          timerMin = x.timerMin ?? 0;
          linkedId = (x.linkedActivityId ?? '').trim();
          break;
        }
      }
    }
    final spiderTimer = type == 'spider' && timerMin > 0 && linkedId.isNotEmpty;
    final role = switch (type) {
      'snake' => 'Tâche à terminer',
      'scorpion' => 'Activité en retard',
      _ => 'Routine à faire',
    };

    final hp = logic.enemyHp(type, itemId);
        final maxHp = logic.enemyMaxHp(type, itemId);
        final itemName = logic.enemyItemName(type, itemId);
        final alreadyScheduled = type == 'snake'
            ? logic.currentProjects
                    .expand((p) => p.tasks)
                    .any((t) => t.id == itemId && t.todayFlag) ||
                logic.todayBlocks.any((b) =>
                    b.taskId == itemId && b.status != 'deleted')
            : logic.state.activeActivities
                    .any((a) => a.id == itemId && a.todayFlag) ||
                logic.todayBlocks.any((b) =>
                    b.activityId == itemId && b.status != 'deleted');

        Future<void> kill() async {
          final loot =
              GoldEconomy.pestLootBase(type, false) + Random().nextInt(5);
          final unlocked = logic.recordKill(type, sync, spendWeapon: false);
          // (La masse de « Bataille de nuisibles » est DÉRIVÉE de habitProgress,
          // plus de mint ici → une routine complétée sur n'importe quel appareil
          // compte. Voir gold_engine.battleMasseEarned.)
          logic.applyGold(sync, loot,
              category: 'gain',
              reasonCode: 'pest_loot',
              label: 'Butin de combat');
          logic.unengageEnemy(type, itemId, sync);
          logic.onChange();
          widget.onClose();
          if (rootCtx.mounted) {
            showConfetti(rootCtx, count: 22);
            ScaffoldMessenger.of(rootCtx).showSnackBar(SnackBar(
                content:
                    Text('⚔️ ${pestName(type)} vaincu ! +$loot or'),
                duration: const Duration(seconds: 2)));
            if (unlocked.isNotEmpty) {
              ScaffoldMessenger.of(rootCtx).showSnackBar(SnackBar(
                  content: Text(
                      '${unlocked.first.emoji} ${unlocked.first.name} débloqué !'),
                  duration: const Duration(seconds: 3)));
            }
          }
          onChanged?.call();
        }

        void launchTimer(int min, String actId, {String? routineId}) {
          if (logic.launchTimerHook == null) return;
          logic.start(actId);
          logic.launchTimerHook!(min, itemName, routineId: routineId);
          widget.onClose();
          onLaunchedTimer?.call();
        }

        void launchChrono(String actId) {
          logic.start(actId);
          logic.onChange();
          widget.onClose();
          onLaunchedTimer?.call();
        }

        // Frappe « routine » (araignée) : +1 sur la routine. Le serpent (tâche)
        // passe par la checklist d'actions (_showTaskActionsSheet).
        Future<void> inlineWork() async {
          logic.incHabit(itemId, 1, DateTime.now());
          logic.onChange();
          if (logic.enemyHp(type, itemId) <= 0) {
            await kill();
          } else {
            setLocal(() {});
            onChanged?.call();
          }
        }

        // Joue la cinématique de canon (tourelle → nuisible du jour) PUIS applique
        // le coup. Réutilisée par « Faire la routine » (web + mobile, même widget).
        Future<void> cannonThen(Future<void> Function() apply) async {
          if (_firing) return;
          setLocal(() => _firing = true);
          await _fireCtrl.forward(from: 0);
          if (!mounted) return;
          setLocal(() => _firing = false);
          await apply();
        }

        // Serpent : ouvre la checklist des actions ; tout coché → mise à mort.
        Future<void> fightSnake() async {
          await _showTaskActionsSheet(rootCtx, logic, sync, itemId,
              onChanged: () {
            setLocal(() {});
            onChanged?.call();
          });
          if (logic.enemyHp(type, itemId) <= 0) {
            await kill();
          } else {
            setLocal(() {});
          }
        }

        Widget atk(IconData icon, String label, VoidCallback onTap) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2B2B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none),
                  ),
                  icon: Icon(icon, size: 18),
                  label: Text(label),
                  onPressed: onTap,
                ),
              ),
            );

        List<Widget> timerLadder(String actId,
            {int? finishMin, String? finishRoutineId}) {
          final out = <Widget>[];
          if (finishMin != null) {
            out.add(atk(Icons.flag_rounded, 'Finir ($finishMin min)',
                () => launchTimer(finishMin, actId, routineId: finishRoutineId)));
          }
          for (final m in [25, 15, 5]) {
            if (m == finishMin) continue;
            if (hp >= m ~/ 5) {
              out.add(atk(Icons.timer_outlined, '$m min (−${m ~/ 5} ❤️)',
                  () => launchTimer(m, actId)));
            }
          }
          out.add(atk(Icons.play_circle_outline, 'Chrono libre', () => launchChrono(actId)));
          return out;
        }

        // Cœur toujours exposé : un seul geste — « Ouvrir le feu » (routine) ;
        // l'échelle de minuteurs reste pour les activités-temps, la checklist
        // pour les tâches.
        final List<Widget> attacks;
        if (spiderTimer) {
          attacks =
              timerLadder(linkedId, finishMin: timerMin, finishRoutineId: itemId);
        } else if (type == 'spider') {
          attacks = [
            atk(Icons.gps_fixed, 'Ouvrir le feu', () => cannonThen(inlineWork))
          ];
        } else if (type == 'scorpion') {
          attacks = timerLadder(itemId);
        } else {
          attacks = [
            atk(Icons.check_circle_outline_rounded, 'Cocher des actions',
                fightSnake)
          ];
        }

        Widget statusLabel(String t) => Text(t,
            style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: Colors.white.withOpacity(.4),
                decoration: TextDecoration.none));

        // Cœur du nuisible — affiché ici pour les types SANS calendrier (tâche)
        // ou en mode compact. Pour routine/activité-temps, les cœurs vivent
        // dans les cases du calendrier, au-dessus des nuisibles visés.
        final statusBlock = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            statusLabel('💓 CŒUR — $hp/$maxHp ❤️'),
            const SizedBox(height: 5),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < maxHp; i++)
                  Text(i < maxHp - hp ? '✅' : '❤️',
                      style: TextStyle(
                          fontSize: compact ? 13 : 18,
                          decoration: TextDecoration.none)),
              ],
            ),
          ],
        );

        const _kRed = Color(0xFFFF2B2B);
        const _kCardBg = Color(0xFF120A0A);

        // Dernier cœur = phase « achève-le » → tout pulse en rouge.
        final exposed = hp <= 1;
        final loot = GoldEconomy.pestLootBase(type, false);

        // ── Ligne CALENDRIER de la semaine glissante (tour + 7 jours) du nuisible
        //    quand c'est une routine (🕷️) ou une activité-temps (🦂). ──
        final weekTokens = type == 'spider'
            ? logic.routineWeekTokens(itemId)
            : (type == 'scorpion'
                ? logic.activityTimeTokens(itemId)
                : const <({String type, int hp})>[]);
        final weekCharger = type == 'spider'
            ? logic.routineDefenseCharger(itemId)
            : weekTokens
                .where((t) => t.type == 'leaf' || t.type == 'flame')
                .length;
        final domColor =
            domainColor(logic.enemyDomainId(type, itemId), logic.state.activeDomains) ??
                const Color(0xFF4FA3FF);
        const _cell = 28.0;
        Widget weekRow() {
          final days = _ctWeekLetters();
          Widget tcell(int d) {
            final tok = weekTokens[d];
            final isSp = tok.type == 'spider';
            final emoji = _ctTokenEmoji(tok.type, scorpion: type == 'scorpion');
            return Container(
              width: _cell,
              height: _cell,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.03),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withOpacity(.06)),
              ),
              child: emoji.isEmpty
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Cœurs du nuisible, juste AU-DESSUS de lui.
                            if (isSp && tok.hp > 0)
                              Text(tok.hp <= 3 ? '❤️' * tok.hp : '❤️${tok.hp}',
                                  style: const TextStyle(
                                      fontSize: 9, height: 1)),
                            Text(emoji, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
            );
          }

          final lifeCol = _ctLifeColor(weekCharger / 7);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const SizedBox(width: 44),
                  for (final l in days)
                    SizedBox(
                      width: _cell + 2,
                      child: Center(
                        child: Text(l,
                            style: TextStyle(
                                color: Colors.white.withOpacity(.4),
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                decoration: TextDecoration.none)),
                      ),
                    ),
                ]),
                const SizedBox(height: 2),
                _cannonRow(
                  weekTokens.length,
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 44,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        // Vie (jaune/bleu/rouge selon la tenue).
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Container(
                            width: 34,
                            height: 4,
                            color: lifeCol.withOpacity(.18),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: (weekCharger / 7).clamp(0.0, 1.0),
                              child: Container(color: lifeCol),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Chargeur (cases vertes = munitions non tirées = jours non faits).
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          for (var i = 0; i < 7; i++)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(right: 1),
                              decoration: BoxDecoration(
                                color: i < (7 - weekCharger)
                                    ? const Color(0xFF4FC26B)
                                    : Colors.white.withOpacity(.12),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        SvgPicture.asset('assets/icons/turret.svg',
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                                _firing
                                    ? const Color(0xFFFFC83D)
                                    : (weekCharger == 0 ? _kRed : domColor),
                                BlendMode.srcIn)),
                      ]),
                    ),
                    for (var d = 0; d < weekTokens.length; d++) tcell(d),
                  ]),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Container(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                decoration: BoxDecoration(
                  color: _kCardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: exposed
                      ? Border.all(color: _kRed.withOpacity(.55), width: 1.5)
                      : null,
                  boxShadow: [
                    BoxShadow(
                        color: _kRed.withOpacity(exposed ? .55 : .30),
                        blurRadius: exposed ? 60 : 40,
                        spreadRadius: exposed ? 4 : 2),
                    BoxShadow(
                        color: Colors.black.withOpacity(.55),
                        blurRadius: 20,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // En-tête hero — ta tourelle fait feu sur le nuisible.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset('assets/icons/turret.svg',
                            width: 30,
                            height: 30,
                            colorFilter: ColorFilter.mode(
                                _kRed.withOpacity(.9), BlendMode.srcIn)),
                        const SizedBox(width: 2),
                        SvgPicture.asset('assets/icons/gunshot.svg',
                            width: 22,
                            height: 22,
                            colorFilter: const ColorFilter.mode(
                                Color(0xFFFFC83D), BlendMode.srcIn)),
                        const SizedBox(width: 8),
                        Text(exposed ? '🎯' : '⚔️',
                            style: const TextStyle(fontSize: 28)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(exposed ? 'ACHÈVE-LE !' : role.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w900,
                            color: exposed ? _kRed : _kRed.withOpacity(.85),
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 16),
                    // Sprite ennemi : pulse en idle, pulse fort + aura rouge
                    // quand le cœur est exposé (dernier ❤️, « finish him »).
                    PulseScale(
                        active: true,
                        maxScale: exposed ? 1.12 : 1.05,
                        period: Duration(milliseconds: exposed ? 650 : 1300),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: exposed
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color: _kRed.withOpacity(.55),
                                        blurRadius: 34,
                                        spreadRadius: 4),
                                  ],
                                )
                              : null,
                          child: Text(entityEmoji(type),
                              style: TextStyle(fontSize: compact ? 44 : 72)),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(itemName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: compact ? 15 : 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            decoration: TextDecoration.none)),
                    SizedBox(height: compact ? 8 : 12),
                    // Cœur global affiché seulement sans calendrier (tâche) ou
                    // en compact — sinon les cœurs sont dans les cases.
                    if (compact || weekTokens.isEmpty) ...[
                      statusBlock,
                      const SizedBox(height: 12),
                    ],
                    // Ligne calendrier de la semaine glissante (routine/activité).
                    if (!compact && weekTokens.isNotEmpty) ...[
                      weekRow(),
                      const SizedBox(height: 8),
                    ],
                    // Récompense de victoire — moteur d'action
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFD4A017).withOpacity(.45)),
                      ),
                      child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '🏆 Victoire : +$loot'),
                            goldIconSpan(size: 13),
                          ]),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE8C24A),
                              decoration: TextDecoration.none)),
                    ),
                    const SizedBox(height: 16),
                    ...attacks,
                    const SizedBox(height: 4),
                    if (logic.programBacklogHook != null && !alreadyScheduled)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          overlayColor: Colors.white12,
                        ),
                        onPressed: () async {
                          widget.onClose();
                          onLaunchedTimer?.call();
                          await logic.programBacklogHook!(type, itemId);
                        },
                        icon: const Icon(Icons.event_available_outlined, size: 16),
                        label: const Text('Programmer pour plus tard',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none)),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                        overlayColor: Colors.white12,
                      ),
                      onPressed: () => widget.onClose(),
                      child: const Text('Fuir',
                          style: TextStyle(decoration: TextDecoration.none)),
                    ),
                  ],
                ),
              ),
        );
  }
}
