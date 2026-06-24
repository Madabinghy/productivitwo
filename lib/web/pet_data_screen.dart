import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/prototypes/pet_prototype.dart';

// Prototype « Compagnon » branché sur TES données (?proto=pet, après auth).
//   • activité aujourd'hui (sessions + routines)  → énergie + humeur
//   • jours consécutifs actifs                     → streak → croissance/niveau
//   • jours depuis la dernière activité            → s'endort/se morfond
class PetDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const PetDataScreen({super.key, required this.sync});

  @override
  State<PetDataScreen> createState() => _PetDataScreenState();
}

class _PetDataScreenState extends State<PetDataScreen> {
  PetData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.sync.pull();
      if (state == null) throw Exception('Aucun état chargé');
      if (mounted) setState(() => _data = _build(state));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Erreur : $_error')),
      );
    }
    final d = _data;
    if (d == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: PetView(data: d, onPet: () {})),
        PetHud(data: d),
      ]),
    );
  }
}

PetData _build(AppState state) {
  final now = DateTime.now();
  final today = yyyymmdd(now);

  // jours avec activité (session OU routine) + dernière activité
  final days = <String>{};
  DateTime? last;
  var doneToday = 0;
  for (final s in state.sessions) {
    days.add(yyyymmdd(s.startAt));
    if (last == null || s.startAt.isAfter(last)) last = s.startAt;
    if (yyyymmdd(s.startAt) == today) doneToday++;
  }
  for (final hh in state.habitHits) {
    days.add(yyyymmdd(hh.ts));
    if (last == null || hh.ts.isAfter(last)) last = hh.ts;
    if (yyyymmdd(hh.ts) == today) doneToday++;
  }

  final daysSince =
      last == null ? 99.0 : (now.difference(last).inMinutes / 1440.0);
  final streak = _streak(days, now);

  // objectif du jour ≈ nombre de routines actives (au moins 1)
  final routines =
      state.activeActivities.where((a) => a.isHabit).length;
  final due = routines > 0 ? routines : 1;
  final energy = (doneToday / due).clamp(0.0, 1.0);

  final PetMood mood;
  if (daysSince >= 3) {
    mood = PetMood.asleep;
  } else if (daysSince >= 1.5) {
    mood = PetMood.sad;
  } else if (energy >= 0.6) {
    mood = PetMood.happy;
  } else {
    mood = PetMood.content;
  }

  final status = switch (mood) {
    PetMood.happy => 'Pousse est ravie ! 🌱',
    PetMood.content => 'Logge encore une routine et elle rayonne',
    PetMood.sad => 'Pousse s\'ennuie… reviens la voir',
    PetMood.asleep => 'Pousse s\'est endormie 😴 réveille-la',
  };

  return PetData(
    streak: streak,
    energy: energy,
    mood: mood,
    doneToday: doneToday,
    dueToday: due,
    statusText: status,
  );
}

int _streak(Set<String> days, DateTime now) {
  if (days.isEmpty) return 0;
  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(yyyymmdd(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(yyyymmdd(cursor))) return 0;
  }
  var n = 0;
  while (days.contains(yyyymmdd(cursor))) {
    n++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return n;
}
