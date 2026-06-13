import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/pulse.dart';

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
/// CTA « Engager » (coût en armes globales) → épingle dans « Combats en cours ».
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

class _BacklogCombatPanelState extends State<BacklogCombatPanel> {
  // Persiste entre les rebuilds → « punch » du sprite à chaque sbire éliminé.
  int hitTick = 0;

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
        final engaged = logic.isEngaged(type, itemId);
        // Capacité permanente, pas une tenue à porter : POSSÉDER l'avatar Ninja
        // (boutique → Avatars) débloque l'attaque des cœurs, quel que soit
        // l'avatar actuellement équipé. Source de vérité unique.
        final ninjaEquipped =
            logic.state.cosmeticsOwned.contains('avatar_ninja');
        final sbires = engaged ? logic.sbiresLeft(type, itemId) : 0;
        final minionW = GoldEconomy.minionWeaponForPest(type);
        final minionWEmoji = logic.weaponEmoji(minionW);
        final minionNeedsNinja = GoldEconomy.minionNeedsNinja(type);
        final canKillSbire = logic.weaponsAvailable(minionW) >= 1 &&
            (!minionNeedsNinja || ninjaEquipped);
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

        Future<void> killOneSbire() async {
          // Consommer l'arme manuellement (killSbire ne la consomme pas)
          logic.state.weaponsSpent[minionW] =
              (logic.state.weaponsSpent[minionW] ?? 0) + 1;
          logic.killSbire(type, itemId, sync);
          logic.onChange();
          hitTick++; // déclenche le punch du sprite
          setLocal(() {});
          onChanged?.call();
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

        // ── Arsenal : compteurs réels, arme du combat en surbrillance ────────────
        String earnSource(String w) => w == 'epee'
            ? 'coche une action de projet'
            : (w == 'arc' ? 'logge du temps' : 'fais une routine');
        Widget weaponChip(String w) {
          final n = logic.weaponsAvailable(w);
          final active = w == minionW;
          final empty = n <= 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFD4A017).withOpacity(empty ? .10 : .20)
                  : Colors.white.withOpacity(.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active
                      ? const Color(0xFFD4A017).withOpacity(empty ? .4 : .7)
                      : Colors.white.withOpacity(.08),
                  width: active ? 1.5 : 1),
            ),
            child: Text('${logic.weaponEmoji(w)} $n',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: active
                        ? (empty
                            ? const Color(0xFFC9952F)
                            : const Color(0xFFE8C24A))
                        : Colors.white.withOpacity(.55),
                    decoration: TextDecoration.none)),
          );
        }
        final weaponRow = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  weaponChip('couteau'),
                  const SizedBox(width: 8),
                  weaponChip('arc'),
                  const SizedBox(width: 8),
                  weaponChip('epee'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                logic.weaponsAvailable(minionW) >= 1
                    ? 'Sbires : −1 ${logic.weaponEmoji(minionW)} par sbire'
                    : 'Plus de ${logic.weaponEmoji(minionW)} — ${earnSource(minionW)}, ou ramasses-en sur la carte',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withOpacity(.5),
                    decoration: TextDecoration.none),
              ),
            ],
          ),
        );

        final List<Widget> attacks;
        if (!engaged) {
          // Pas encore engagé : expliquer la mécanique
          attacks = [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                type == 'snake'
                    ? 'Engagez pour faire apparaître les sbires (🔪 couteau + 🥷 ninja requis).'
                    : 'Engagez pour faire apparaître les sbires (🏹 arc requis).',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withOpacity(.5),
                    decoration: TextDecoration.none),
              ),
            ),
          ];
        } else if (sbires > 0) {
          // Phase 1 : tuer les sbires
          attacks = [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Élimine les sbires avant d\'atteindre le cœur',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(.5),
                        decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 10),
                  if (minionNeedsNinja && !ninjaEquipped)
                    Text(
                      '🔒 Avatar Ninja requis pour les sbires du serpent\n(Boutique d\'or → Avatars)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.orange.shade300,
                          decoration: TextDecoration.none),
                    )
                  else
                    atk(
                      Icons.close_rounded,
                      canKillSbire
                          ? 'Éliminer 1 sbire  (−1 $minionWEmoji)'
                          : 'Pas assez d\'armes (${logic.weaponsAvailable(minionW)} $minionWEmoji)',
                      canKillSbire ? killOneSbire : () {},
                    ),
                ],
              ),
            ),
          ];
        } else if (!ninjaEquipped) {
          // Sbires éliminés, mais sans ninja pour toucher le cœur
          attacks = [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '🥷 Avatar Ninja requis pour attaquer le cœur\n(Boutique d\'or → Avatars)',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade300,
                    decoration: TextDecoration.none),
              ),
            ),
          ];
        } else {
          // Phase 2 : attaquer le cœur (ninja équipé)
          if (spiderTimer) {
            attacks =
                timerLadder(linkedId, finishMin: timerMin, finishRoutineId: itemId);
          } else if (type == 'spider') {
            attacks = [atk(Icons.local_fire_department_rounded, 'Faire la routine (+1)', inlineWork)];
          } else if (type == 'scorpion') {
            attacks = timerLadder(itemId);
          } else {
            attacks = [atk(Icons.check_circle_outline_rounded, 'Cocher des actions', fightSnake)];
          }
        }

        // Sbires affichés : restants si engagé, sinon aperçu de ce qui gardera
        // le cœur (même règle que la tuile de carte).
        final sbiresShown =
            engaged ? sbires : logic.enemySbires(type, itemId);

        Widget statusLabel(String t) => Text(t,
            style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: Colors.white.withOpacity(.4),
                decoration: TextDecoration.none));

        // Statut de combat : sbires (gardes) AU-DESSUS, cœur EN DESSOUS —
        // même langage visuel que la carte (❤️ en haut, sbires en bas).
        final statusBlock = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sbiresShown > 0) ...[
              statusLabel(engaged
                  ? 'SBIRES — $sbiresShown restant${sbiresShown > 1 ? 's' : ''}'
                  : 'GARDES DU CŒUR — $sbiresShown'),
              const SizedBox(height: 5),
              Wrap(
                spacing: 3,
                alignment: WrapAlignment.center,
                children: [
                  for (int i = 0; i < sbiresShown; i++)
                    Text(entityEmoji(type),
                        style: TextStyle(
                            fontSize: compact ? 13 : 18,
                            decoration: TextDecoration.none)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            statusLabel(sbiresShown > 0
                ? 'CŒUR — $hp/$maxHp ❤️ (protégé)'
                : '💓 CŒUR EXPOSÉ — $hp/$maxHp ❤️'),
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

        final wEmoji = logic.weaponEmoji(GoldEconomy.minionWeaponForPest(type));
        final cost = logic.engageCost(type);

        const _kRed = Color(0xFFFF2B2B);
        const _kCardBg = Color(0xFF120A0A);

        // Cœur atteignable = phase « achève-le » → tout pulse en rouge.
        final exposed = engaged && sbiresShown <= 0;
        final loot = GoldEconomy.pestLootBase(type, false);

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
                    // En-tête hero — bandeau de phase
                    Text(exposed ? '🎯' : '⚔️',
                        style: const TextStyle(fontSize: 28)),
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
                    // quand le cœur est exposé (« finish him ») ; « punch »
                    // élastique à chaque sbire éliminé (hitTick).
                    TweenAnimationBuilder<double>(
                      key: ValueKey(hitTick),
                      tween: Tween<double>(
                          begin: hitTick == 0 ? 1.0 : 1.4, end: 1.0),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.elasticOut,
                      builder: (_, s, child) =>
                          Transform.scale(scale: s, child: child),
                      child: PulseScale(
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
                    statusBlock,
                    const SizedBox(height: 12),
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
                    weaponRow,
                    ...attacks,
                    // CTA Engager
                    if (!engaged)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(.25)),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: const Icon(Icons.push_pin_outlined, size: 16),
                        label: Text(logic.canEngage(type)
                            ? 'Engager (épingler) · $cost$wEmoji'
                            : 'Engager : $cost$wEmoji requis'),
                        onPressed: logic.canEngage(type)
                            ? () {
                                if (logic.engageEnemy(type, itemId, sync)) {
                                  setLocal(() {});
                                  onChanged?.call();
                                }
                              }
                            : null,
                      )
                    else
                      Text('📌 Engagé — dans « Combats en cours »',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(.5),
                              decoration: TextDecoration.none)),

                    // ── Pouvoirs rapides ────────────────────────────────────────
                    _PowersSection(
                      logic: logic,
                      sync: sync,
                      type: type,
                      itemId: itemId,
                      onChanged: () => setLocal(() {}),
                    ),

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

/// Section « Pouvoirs rapides » sous la carte de combat.
/// - Spider (routine) : gel 1j/2j/3j direct (achat + application en un tap).
/// - Snake (tâche) : bouclier anti-retard.
/// - Tous : boost ×2.
/// Prix dynamique : augmente avec le nombre de pouvoirs actifs.
class _PowersSection extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final String type;
  final String itemId;
  final VoidCallback onChanged;
  const _PowersSection({
    required this.logic,
    required this.sync,
    required this.type,
    required this.itemId,
    required this.onChanged,
  });
  @override
  State<_PowersSection> createState() => _PowersSectionState();
}

class _PowersSectionState extends State<_PowersSection> {
  AppLogic get logic => widget.logic;
  bool _busy = false;

  static const _kGold = Color(0xFFD4A017);

  /// Gèle la routine pour [days] jours à partir d'aujourd'hui (achat + application).
  Future<void> _freezeRoutine(int days) async {
    if (_busy) return;
    final price = logic.gelPriceDynamic() * days;
    if (logic.gold < price) {
      _snack('Solde insuffisant (${logic.gold} / $price or).');
      return;
    }
    final today = DateTime.now();
    final ymds = [
      for (int i = 0; i < days; i++)
        yyyymmdd(today.add(Duration(days: i)))
    ];
    setState(() => _busy = true);
    final ok = await widget.sync
        .buyAndApplyGelDirect(widget.itemId, ymds, price);
    if (ok) {
      logic.state.gold -= price;
      for (final y in ymds) {
        final key = '${widget.itemId}_$y';
        if (!logic.state.goldGelDays.contains(key)) {
          logic.state.goldGelDays.add(key);
        }
      }
      logic.onChange();
      _snack('🧊 Gelée $days j — pas de pénalité ces jours-là.');
    } else {
      _snack('Solde insuffisant.');
    }
    if (mounted) {
      setState(() => _busy = false);
      widget.onChanged();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final gelPrice1 = logic.gelPriceDynamic();
    final frozen = logic.routineFrozenDaysLeft(widget.itemId);
    final activeGel = logic.activeGelCount();
    final boostPrice = logic.boostPriceDynamic();
    final boostActive = logic.state.goldBoostDays.contains(yyyymmdd(DateTime.now()));

    final showGel = widget.type == 'spider';
    final showShield = widget.type == 'snake';

    if (!showGel && !showShield && boostActive) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.white.withOpacity(.12), height: 20),
          Text('POUVOIRS',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(.45))),
          const SizedBox(height: 8),

          // ── Gel de routine ─────────────────────────────────────────────────
          if (showGel) ...[
            if (frozen > 0)
              Row(children: [
                const Icon(Icons.ac_unit_rounded, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 6),
                Text('Gelée $frozen j restants',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7DD3FC))),
              ])
            else if (activeGel >= 3)
              Text('Max 3 gels actifs atteint',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withOpacity(.5)))
            else ...[
              Text('Geler cette routine',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(.7))),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final days in [1, 2, 3]) ...[
                    if (days > 1) const SizedBox(width: 6),
                    Expanded(
                      child: _PowerBtn(
                        icon: Icons.ac_unit_rounded,
                        label: '${days}j',
                        sublabelWidget: _goldSub(gelPrice1 * days),
                        color: const Color(0xFF0EA5E9),
                        enabled: !_busy && logic.gold >= gelPrice1 * days && activeGel + days <= 3,
                        onTap: () => _freezeRoutine(days),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],

          // ── Bouclier tâche ─────────────────────────────────────────────────
          if (showShield) ...[
            Row(children: [
              Expanded(
                child: _PowerBtn(
                  icon: Icons.shield_outlined,
                  label: 'Bouclier ${GoldEconomy.shieldDaysPerUse}j',
                  sublabelWidget: _goldSub(logic.shieldPriceDynamic(), suffix: ' · anti-retard'),
                  color: const Color(0xFF8B5CF6),
                  enabled: !_busy &&
                      logic.gold >= logic.shieldPriceDynamic() &&
                      (logic.state.goldInventory['shield'] ?? 0) > 0,
                  onTap: () {
                    // Renvoie vers la boutique pour choisir la tâche.
                    Navigator.pop(context);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],

          // ── Boost ×2 ───────────────────────────────────────────────────────
          if (!boostActive)
            Row(children: [
              Expanded(
                child: _PowerBtn(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Boost ×2 (${GoldEconomy.boostDaysPerUse}j)',
                  sublabelWidget: _goldSub(boostPrice, suffix: ' · double tes gains'),
                  color: _kGold,
                  enabled: !_busy && logic.gold >= boostPrice &&
                      (logic.state.goldInventory['boost'] ?? 0) > 0,
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            ])
          else
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFFD4A017)),
              const SizedBox(width: 4),
              Text('Boost ×2 actif',
                  style: TextStyle(
                      fontSize: 12,
                      color: _kGold.withOpacity(.8),
                      fontWeight: FontWeight.w700)),
            ]),
        ],
      ),
    );
  }
}

Widget _goldSub(int amount, {String? suffix}) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$amount',
            style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withOpacity(.55),
                decoration: TextDecoration.none)),
        const SizedBox(width: 2),
        const GoldIcon(size: 11),
        if (suffix != null)
          Text(suffix,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withOpacity(.45),
                  decoration: TextDecoration.none)),
      ],
    );

class _PowerBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget sublabelWidget;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _PowerBtn({
    required this.icon,
    required this.label,
    required this.sublabelWidget,
    required this.color,
    required this.enabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final labelColor = color;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: labelColor),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: labelColor,
                          decoration: TextDecoration.none)),
                  Text(' · ',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(.3),
                          decoration: TextDecoration.none)),
                  sublabelWidget,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Prévisualisation statique (web design review) ─────────────────────────────

/// Ouvre la carte de combat avec des données fictives — pour valider le design
/// sans AppLogic. À retirer après validation.
Future<void> showCombatCardPreview(BuildContext context) async {
  const _kRed = Color(0xFFFF2B2B);
  const _kCardBg = Color(0xFF120A0A);
  const _kGold = Color(0xFFD4A017);

  Widget _mockAtk(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label),
            onPressed: () {},
          ),
        ),
      );

  Widget _mockPower(IconData icon, String label, Widget sub, Color color) =>
      Expanded(
        child: Opacity(
          opacity: 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: color,
                            decoration: TextDecoration.none)),
                    Text(' · ',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(.3),
                            decoration: TextDecoration.none)),
                    sub,
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Preview',
    barrierColor: Colors.black.withOpacity(.65),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: _kRed.withOpacity(.30),
                    blurRadius: 40,
                    spreadRadius: 2),
                BoxShadow(
                    color: Colors.black.withOpacity(.55),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚔️', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                const Text('ROUTINE À FAIRE',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2.5,
                        fontWeight: FontWeight.w900,
                        color: _kRed,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 16),
                const Text('🕷️', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 6),
                const Text('Sport du matin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  alignment: WrapAlignment.center,
                  children: [
                    for (int i = 0; i < 5; i++)
                      Text(i < 2 ? '✅' : '❤️',
                          style: const TextStyle(
                              fontSize: 18, decoration: TextDecoration.none)),
                  ],
                ),
                const SizedBox(height: 16),
                _mockAtk(Icons.local_fire_department_rounded, 'Faire la routine (+1)'),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(.25)),
                    minimumSize: const Size.fromHeight(42),
                  ),
                  icon: const Icon(Icons.push_pin_outlined, size: 16),
                  label: const Text('Engager (épingler) · 1🩴'),
                  onPressed: () {},
                ),
                // Pouvoirs
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(color: Colors.white.withOpacity(.12), height: 20),
                      Text('POUVOIRS',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withOpacity(.45),
                              decoration: TextDecoration.none)),
                      const SizedBox(height: 8),
                      Text('Geler cette routine',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(.7),
                              decoration: TextDecoration.none)),
                      const SizedBox(height: 6),
                      Row(children: [
                        _mockPower(Icons.ac_unit_rounded, '1j', _goldSub(8),
                            const Color(0xFF0EA5E9)),
                        const SizedBox(width: 6),
                        _mockPower(Icons.ac_unit_rounded, '2j', _goldSub(16),
                            const Color(0xFF0EA5E9)),
                        const SizedBox(width: 6),
                        _mockPower(Icons.ac_unit_rounded, '3j', _goldSub(24),
                            const Color(0xFF0EA5E9)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        _mockPower(Icons.auto_awesome_rounded, 'Boost ×2 (3j)',
                            _goldSub(40, suffix: ' · double tes gains'), _kGold),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    overlayColor: Colors.white12,
                  ),
                  onPressed: () {},
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
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fuir',
                      style: TextStyle(decoration: TextDecoration.none)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
