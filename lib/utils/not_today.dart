import 'package:productivitwo_v1/gamification_flags.dart';

/// Message d'un « Pas aujourd'hui » sur une routine (décision user 2026-11-04) : la journée
/// parfaite reste possible, mais la série s'arrête et la journée ne forgera pas de braise.
String notTodayLine(String name, {int series = 0, bool daily = true}) {
  if (!daily) return 'Pas aujourd\'hui : $name';
  final cut = series >= 1 ? 'la série de $series j s\'arrête' : 'pas de série en jeu';
  return 'Pas aujourd\'hui : $name · ta journée parfaite reste possible${kEmbersEnabled ? ' (sans braise)' : ''}, $cut';
}
