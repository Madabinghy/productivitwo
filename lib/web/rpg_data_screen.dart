import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/prototypes/rpg_prototype.dart';

// Prototype « RPG / Stats » branché sur TES données (?proto=rpg, après auth).
// Chaque domaine actif devient un attribut :
//   • minutes totales loggées        → XP de l'attribut
//   • XP cumulé (courbe)             → niveau de l'attribut
//   • niveau / niveau max            → valeur sur le radar (montre l'équilibre)
//   • minutes loggées aujourd'hui    → XP du jour
//   • somme des niveaux              → niveau global du personnage
class RpgDataScreen extends StatefulWidget {
  final FirestoreSync sync;
  const RpgDataScreen({super.key, required this.sync});

  @override
  State<RpgDataScreen> createState() => _RpgDataScreenState();
}

class _RpgDataScreenState extends State<RpgDataScreen> {
  _RpgData? _data;
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
      final d = _build(state);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0813),
        body: Center(
            child: Text('Erreur : $_error',
                style: const TextStyle(color: Colors.white70))),
      );
    }
    final d = _data;
    if (d == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0813),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (d.attrs.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0813),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Aucun domaine actif.\n'
              'Crée des domaines et logue du temps pour faire monter tes attributs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0813),
      body: RpgView(
        attrs: d.attrs,
        globalLevel: d.globalLevel,
        title: d.title,
        globalProgress: d.globalProgress,
        globalXpLabel: d.globalXpLabel,
        onTapAttr: _showInfo,
      ),
    );
  }

  void _showInfo(RpgAttr a) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1C1640),
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${a.name} — Niveau ${a.level}'
            '${a.totalLabel != null ? ' · ${a.totalLabel}' : ''}'
            '${a.todayXp > 0 ? ' · +${a.todayXp} xp aujourd\'hui' : ''}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
  }
}

class _RpgData {
  _RpgData(this.attrs, this.globalLevel, this.title, this.globalProgress,
      this.globalXpLabel);
  final List<RpgAttr> attrs;
  final int globalLevel;
  final String title;
  final double globalProgress;
  final String globalXpLabel;
}

const _fallbackPalette = [
  Color(0xFFFFB347),
  Color(0xFF8A6EF0),
  Color(0xFF4FD17A),
  Color(0xFF36C9C9),
  Color(0xFF5A8FD6),
  Color(0xFFFF5A47),
  Color(0xFFB06DF0),
  Color(0xFFD06DE0),
  Color(0xFFFFD36B),
];

// XP cumulé requis pour atteindre le niveau L (en minutes) : 50·L·(L−1).
int _xpForLevel(int l) => 50 * l * (l - 1);
int _levelForXp(int xp) {
  var l = 1;
  while (_xpForLevel(l + 1) <= xp) {
    l++;
  }
  return l;
}

double _progress(int xp, int level) {
  final cur = _xpForLevel(level);
  final next = _xpForLevel(level + 1);
  if (next <= cur) return 0;
  return ((xp - cur) / (next - cur)).clamp(0.0, 1.0);
}

_RpgData _build(AppState state) {
  final now = DateTime.now();
  final today = yyyymmdd(now);
  final domains = state.activeDomains;
  if (domains.isEmpty) {
    return _RpgData(const [], 1, 'Apprenti', 0, '0 XP cumulé');
  }

  final actToDom = <String, String>{};
  for (final a in state.activeActivities) {
    actToDom[a.id] = a.domainId;
  }

  final totalMinByDom = <String, int>{};
  final todayMinByDom = <String, int>{};
  for (final s in state.sessions) {
    final dom = actToDom[s.activityId];
    if (dom == null) continue;
    final mins = s.duration.inMinutes.clamp(0, 24 * 60);
    totalMinByDom[dom] = (totalMinByDom[dom] ?? 0) + mins;
    if (yyyymmdd(s.startAt) == today) {
      todayMinByDom[dom] = (todayMinByDom[dom] ?? 0) + mins;
    }
  }

  // niveaux
  final levelByDom = <String, int>{};
  for (final d in domains) {
    levelByDom[d.id] = _levelForXp(totalMinByDom[d.id] ?? 0);
  }
  final maxLevel =
      levelByDom.values.fold<int>(1, (m, l) => l > m ? l : m).clamp(1, 9999);

  final attrs = <RpgAttr>[];
  for (var i = 0; i < domains.length; i++) {
    final d = domains[i];
    final xp = totalMinByDom[d.id] ?? 0;
    final level = levelByDom[d.id]!;
    final color = d.colorValue != null
        ? Color(d.colorValue!)
        : _fallbackPalette[i % _fallbackPalette.length];
    attrs.add(RpgAttr(
      name: d.name,
      color: color,
      level: level,
      progress: _progress(xp, level),
      radar: (level / maxLevel).clamp(0.08, 1.0),
      todayXp: todayMinByDom[d.id] ?? 0,
      totalLabel: _fmtTotal(xp),
    ));
  }

  final globalLevel = levelByDom.values.fold<int>(0, (a, b) => a + b);
  final totalMin = totalMinByDom.values.fold<int>(0, (a, b) => a + b);
  final avgProgress = attrs.isEmpty
      ? 0.0
      : attrs.map((a) => a.progress).reduce((a, b) => a + b) / attrs.length;

  return _RpgData(
    attrs,
    globalLevel,
    _title(globalLevel),
    avgProgress,
    '${_fmtHours(totalMin)} de jeu · $globalLevel niveaux cumulés',
  );
}

String _title(int lvl) {
  if (lvl < 8) return 'Apprenti';
  if (lvl < 20) return 'Aventurier';
  if (lvl < 40) return 'Architecte de vie';
  if (lvl < 70) return 'Maître de vie';
  return 'Légende';
}

String? _fmtTotal(int min) {
  if (min <= 0) return null;
  return '${_fmtHours(min)} cumulées';
}

String _fmtHours(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  if (h <= 0) return '${m}min';
  return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
}
