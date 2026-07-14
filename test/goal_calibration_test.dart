import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

// ─── Calibration « plug and play » des cibles de temps ───────────────────────
//
// Une activité créée à 1 min/j (défaut) qui vit à 40 min/j doit voir sa cible
// suivre le réel — sauf épinglage manuel (targetSource == 'user'), qui est la
// vérité utilisateur et ne bouge JAMAIS.

AppLogic _logic(List<Activity> acts, List<Session> sessions) {
  final st = AppState(
    domains: [Domain(name: 'Spiritualité')],
    activities: acts,
    sessions: sessions,
    habitProgress: [],
  );
  return AppLogic(st, () {});
}

Activity _time(String id, String name,
        {int goalMin = 1, String targetSource = 'default'}) =>
    Activity(
        id: id,
        name: name,
        domainId: 'd1',
        type: 'time',
        goalMin: goalMin,
        targetSource: targetSource);

/// [perDayMin] minutes logguées chaque jour sur [days] jours avant [now].
List<Session> _daily(String id, DateTime now, int perDayMin, {int days = 30}) =>
    [
      for (var i = 0; i < days; i++)
        Session(
            activityId: id,
            startAt: DateTime(now.year, now.month, now.day - i, 12, 0),
            endAt: DateTime(now.year, now.month, now.day - i, 12, perDayMin)),
    ];

void main() {
  final now = DateTime(2026, 7, 14, 20, 0);

  test('cible 1 min vécue à 40 min/j → montée par paliers, provenance orion',
      () async {
    final a = _time('a1', 'Louanges');
    final l = _logic([a], _daily('a1', now, 40));
    final notes = await l.autoAdjustStandardsRealtime(now: now);
    expect(a.goalMin, 6); // +max(5, 20 %) par passage — sortie du défaut 1 min
    expect(a.targetSource, 'orion');
    expect(notes.single, contains('Louanges : cible 1 → 6 min/j'));
    expect(notes.single, contains('mesuré ~40 min/j sur 30 j'));

    // Cooldown 48 h : re-passage immédiat = aucun mouvement.
    expect(await l.autoAdjustStandardsRealtime(now: now), isEmpty);

    // 49 h plus tard : la montée continue (6 → 11).
    final later = now.add(const Duration(hours: 49));
    l.state.sessions.addAll(_daily('a1', later, 40, days: 2));
    await l.autoAdjustStandardsRealtime(now: later);
    expect(a.goalMin, 11);
  });

  test('épinglée à la main (targetSource user) → jamais touchée', () async {
    final a = _time('a1', 'Louanges', targetSource: 'user');
    final l = _logic([a], _daily('a1', now, 40));
    final notes = await l.autoAdjustStandardsRealtime(now: now);
    expect(notes, isEmpty);
    expect(a.goalMin, 1);
    expect(a.targetSource, 'user');
  });

  test('écart immatériel (< 5 min/j mesurées) → aucun mouvement, pas d\'oscillation',
      () async {
    // 44 min en TOUT sur 30 j (≈ 1,5 min/j) pour une cible à 1 : rien à faire.
    final a = _time('a1', 'Louanges');
    final l = _logic([a], [
      Session(
          activityId: 'a1',
          startAt: DateTime(2026, 7, 13, 12, 0),
          endAt: DateTime(2026, 7, 13, 12, 44)),
    ]);
    expect(await l.autoAdjustStandardsRealtime(now: now), isEmpty);
    expect(a.goalMin, 1);
    expect(a.targetSource, 'default');
  });

  test('zone morte (0,80-1,10) : une cible tenue ne bouge pas', () async {
    final a = _time('a1', 'Deep Work', goalMin: 30);
    final l = _logic([a], _daily('a1', now, 27));
    expect(await l.autoAdjustStandardsRealtime(now: now), isEmpty);
    expect(a.goalMin, 30);
  });

  test('cible trop haute pour le réel (≤ 50 %) → redescend, bornée à -20 %',
      () async {
    final a = _time('a1', 'Running', goalMin: 60);
    final l = _logic([a], _daily('a1', now, 10));
    final notes = await l.autoAdjustStandardsRealtime(now: now);
    expect(a.goalMin, 48); // 60 - 20 %
    expect(notes.single, contains('Running : cible 60 → 48 min/j'));
  });

  test('défi : jamais sur une cible < 10 min (défaut pas encore calibré)', () {
    final tiny = _time('a1', 'Louanges'); // cible 1
    final real = _time('a2', 'Deep Work', goalMin: 30);
    final l = _logic([tiny, real], []);
    expect(l.challengeActivity()?.id, 'a2');
    final l2 = _logic([tiny], []);
    expect(l2.challengeActivity(), isNull);
  });
}
