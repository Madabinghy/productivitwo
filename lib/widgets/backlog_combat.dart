import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';

/// Complète la 1ʳᵉ action non faite d'une tâche (frappe d'un serpent backlog).
Future<bool> _completeOneTaskAction(
    AppLogic logic, FirestoreSync sync, String taskId) async {
  for (final p in logic.currentProjects) {
    for (final t in p.tasks) {
      if (t.id != taskId) continue;
      final idx = t.actions.indexWhere((a) => !a.done);
      if (idx < 0) return false;
      t.actions[idx].done = true;
      t.actions[idx].doneAt = DateTime.now();
      await sync.saveProjectTasks(p.id, p.tasks);
      return true;
    }
  }
  return false;
}

/// Carte de COMBAT « vrai item » (PV) — ouvrable depuis la map OU « Mon or ».
/// On FRAPPE en faisant le vrai travail spécifique (cœurs ❤️, ✅ = éliminés).
/// CTA « Engager » (coût en armes globales) → épingle dans « Combats en cours ».
/// [onChanged] : rafraîchir l'appelant après une action. [onLaunchedTimer] : le
/// caller ferme son conteneur quand on lance un minuteur (pour voir le décompte).
Future<void> showBacklogCombat(
  BuildContext context,
  AppLogic logic,
  FirestoreSync sync,
  String type,
  String itemId, {
  VoidCallback? onChanged,
  VoidCallback? onLaunchedTimer,
}) async {
  final rootCtx = context;
  const accent = Color(0xFFE24A4A);
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

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Combat',
    barrierColor: Colors.black.withOpacity(.6),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final hp = logic.enemyHp(type, itemId);
        final maxHp = logic.enemyMaxHp(type, itemId);
        final itemName = logic.enemyItemName(type, itemId);
        final engaged = logic.isEngaged(type, itemId);

        Future<void> kill() async {
          final loot =
              GoldEconomy.pestLootBase(type, false) + Random().nextInt(5);
          final unlocked = logic.recordKill(type, sync, spendWeapon: false);
          logic.applyGold(sync, loot,
              category: 'gain',
              reasonCode: 'pest_loot',
              label: 'Butin de combat');
          logic.unengageEnemy(type, itemId, sync);
          logic.onChange();
          Navigator.pop(ctx);
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
          Navigator.pop(ctx);
          onLaunchedTimer?.call();
        }

        void launchChrono(String actId) {
          logic.start(actId);
          logic.onChange();
          Navigator.pop(ctx);
          onLaunchedTimer?.call();
        }

        Future<void> inlineWork() async {
          if (type == 'spider') {
            logic.incHabit(itemId, 1, DateTime.now());
            logic.onChange();
          } else {
            await _completeOneTaskAction(logic, sync, itemId);
          }
          if (logic.enemyHp(type, itemId) <= 0) {
            await kill();
          } else {
            setLocal(() {});
            onChanged?.call();
          }
        }

        Widget atk(String icon, String label, VoidCallback onTap) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: Text(icon, style: const TextStyle(fontSize: 15)),
                  label: Text(label,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                  onPressed: onTap,
                ),
              ),
            );

        List<Widget> timerLadder(String actId,
            {int? finishMin, String? finishRoutineId}) {
          final out = <Widget>[];
          if (finishMin != null) {
            out.add(atk('🏁', 'Finir ($finishMin min)',
                () => launchTimer(finishMin, actId, routineId: finishRoutineId)));
          }
          for (final m in [25, 15, 5]) {
            if (m == finishMin) continue;
            if (hp >= m ~/ 5) {
              out.add(atk('⏱️', '$m min (−${m ~/ 5} ❤️)',
                  () => launchTimer(m, actId)));
            }
          }
          out.add(atk('▶', 'Chrono libre', () => launchChrono(actId)));
          return out;
        }

        final List<Widget> attacks;
        if (spiderTimer) {
          attacks =
              timerLadder(linkedId, finishMin: timerMin, finishRoutineId: itemId);
        } else if (type == 'spider') {
          attacks = [atk('🔥', 'Faire la routine (+1)', inlineWork)];
        } else if (type == 'scorpion') {
          attacks = timerLadder(itemId);
        } else {
          attacks = [atk('✅', 'Cocher une action (−1 ❤️)', inlineWork)];
        }

        final Widget hearts;
        if (maxHp > 12) {
          hearts = Text('❤️ $hp / $maxHp PV',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white));
        } else {
          hearts = Wrap(
            spacing: 2,
            runSpacing: 2,
            alignment: WrapAlignment.center,
            children: [
              for (int i = 0; i < maxHp; i++)
                Text(i < maxHp - hp ? '✅' : '❤️',
                    style: const TextStyle(fontSize: 18)),
            ],
          );
        }

        final wEmoji = logic.weaponEmoji(GoldEconomy.weaponForPest(type));
        final cost = logic.engageCost(type);

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A0E0E), Color(0xFF5A1A1A)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accent, width: 2),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(.4), blurRadius: 26)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(role.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFC9C9))),
                    const SizedBox(height: 12),
                    Container(
                      width: 104,
                      height: 104,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          accent.withOpacity(.30),
                          accent.withOpacity(0),
                        ]),
                      ),
                      child: Text(entityEmoji(type),
                          style: const TextStyle(fontSize: 68)),
                    ),
                    Text(itemName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 10),
                    hearts,
                    const SizedBox(height: 14),
                    ...attacks,
                    // CTA Engager : épingle l'ennemi (coût en armes globales) pour
                    // le retrouver dans « Combats en cours » sans re-fouiller la map.
                    if (!engaged)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(.3)),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: const Text('📌', style: TextStyle(fontSize: 14)),
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
                              color: Colors.white.withOpacity(.6))),
                    if (logic.programBacklogHook != null)
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          onLaunchedTimer?.call();
                          await logic.programBacklogHook!(type, itemId);
                        },
                        icon: const Text('📅', style: TextStyle(fontSize: 14)),
                        label: Text('Programmer pour plus tard',
                            style: TextStyle(
                                color: Colors.white.withOpacity(.9),
                                fontWeight: FontWeight.w700)),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Fuir',
                          style:
                              TextStyle(color: Colors.white.withOpacity(.55))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    },
  );
}
