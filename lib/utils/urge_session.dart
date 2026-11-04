import 'package:productivitwo_v1/utils/freedom.dart' show kUrgeWaveSec;

/// Une envie en cours (Liberté, 2026-11-04, retour user) : on peut quitter
/// l'écran pour faire autre chose, le minuteur continue ; au bout, il sonne et
/// l'écran se rouvre pour demander comment ça s'est passé. Une seule à la fois,
/// gardée sur l'appareil.
class PendingUrge {
  final String freedomId;
  final int startMs;
  final int intensity;
  final String? trigger;
  final String? parade;

  const PendingUrge({required this.freedomId, required this.startMs, this.intensity = 3, this.trigger, this.parade});

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs);
  DateTime get endsAt => start.add(const Duration(seconds: kUrgeWaveSec));
  bool isOver(DateTime now) => !now.isBefore(endsAt);
  int secondsLeft(DateTime now) {
    final s = endsAt.difference(now).inSeconds;
    return s < 0 ? 0 : s;
  }

  /// Oubliée au-delà de 12 h : on ne redemande pas une envie de la veille.
  bool isStale(DateTime now) => now.difference(start) > kUrgeStale;

  PendingUrge copyWith({int? intensity, String? trigger, bool clearTrigger = false, String? parade, bool clearParade = false}) => PendingUrge(
        freedomId: freedomId,
        startMs: startMs,
        intensity: intensity ?? this.intensity,
        trigger: clearTrigger ? null : (trigger ?? this.trigger),
        parade: clearParade ? null : (parade ?? this.parade),
      );

  Map<String, dynamic> toJson() => {
        'freedomId': freedomId,
        'startMs': startMs,
        'intensity': intensity,
        if (trigger != null) 'trigger': trigger,
        if (parade != null) 'parade': parade,
      };

  static PendingUrge? from(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['freedomId'];
    final start = raw['startMs'];
    if (id is! String || start is! num) return null;
    return PendingUrge(
      freedomId: id,
      startMs: start.toInt(),
      intensity: (raw['intensity'] as num?)?.toInt() ?? 3,
      trigger: raw['trigger'] as String?,
      parade: raw['parade'] as String?,
    );
  }
}

const kUrgeStale = Duration(hours: 12);
