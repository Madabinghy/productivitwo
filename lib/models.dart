import 'dart:convert';
import 'package:uuid/uuid.dart';

part 'models/core.dart';
part 'models/activity.dart';
part 'models/filters_badges.dart';
part 'models/app_state.dart';
part 'models/projects.dart';
part 'models/integrations.dart';
part 'models/schedule.dart';
part 'models/artifact.dart';
part 'models/weekly_report.dart';
part 'models/world.dart';
part 'models/redemption.dart';

const _uuid = Uuid();
const int kMinDailyGoalMin = 1;

enum HabitFreq { daily, weekly, monthly }

/// Utilitaires de date
String yyyymmdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// Parse une date qui peut être une String ISO ou un Firestore Timestamp.
DateTime _parseDate(dynamic v, [DateTime? fallback]) {
  if (v == null) return fallback ?? DateTime.now();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v) ?? (fallback ?? DateTime.now());
  try { return (v as dynamic).toDate() as DateTime; } catch (_) {}
  return fallback ?? DateTime.now();
}

DateTime? _parseDateOrNull(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  try { return (v as dynamic).toDate() as DateTime; } catch (_) {}
  return null;
}
