// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/onboarding_catalog.dart';

// ── Catalogue & packs : source partagée (lib/onboarding_catalog.dart) ─────────
// Les définitions sont centralisées pour être réutilisées par l'onboarding
// refondu Soft Pop. Ici on alias les noms publics vers les anciens noms privés
// pour ne rien changer au reste de ce fichier.
typedef _ActivitySug = ActivitySug;
typedef _RoutineSug = RoutineSug;
typedef _PackDef = PackDef;
final _catalogue = kOnboardingCatalogue;
const _packs = kOnboardingPacks;
String _freqLabel(HabitFreq f) => onboardingFreqLabel(f);

// ═══════════════════════════════════════════════════════════════════════════════
// OnboardingScreen
// ═══════════════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final VoidCallback onDone;

  const OnboardingScreen({
    super.key,
    required this.logic,
    required this.sync,
    required this.onDone,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _totalPages = 6;

  final _pageCtrl = PageController();
  int _page = 0;

  // Sélections
  final Set<String> _selectedDomains = {};
  // activityName → (suggestion, domainName)
  final Map<String, ({_ActivitySug sug, String domain})> _selectedActivities = {};
  // routineName → (suggestion, domainName, freq)
  final Map<String, ({_RoutineSug sug, String domain, HabitFreq freq})> _selectedRoutines = {};

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageCtrl.animateToPage(page,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    setState(() => _page = page);
  }

  void _applyPack(_PackDef pack) {
    setState(() {
      for (final domainName in pack.domains) {
        _selectedDomains.add(domainName);
      }
      for (final entry in _catalogue.entries) {
        for (final sug in entry.value.activities) {
          if (pack.activities.contains(sug.name)) {
            _selectedActivities[sug.name] = (sug: sug, domain: entry.key);
          }
        }
        for (final sug in entry.value.routines) {
          if (pack.routines.contains(sug.name)) {
            _selectedRoutines[sug.name] = (sug: sug, domain: entry.key, freq: sug.defaultFreq);
          }
        }
      }
    });
    _goTo(4); // directement au résumé
  }

  void _toggleActivity(String domain, _ActivitySug sug) {
    setState(() {
      if (_selectedActivities.containsKey(sug.name)) {
        _selectedActivities.remove(sug.name);
        // Délie les routines qui pointent vers cette activité
        for (final key in _selectedRoutines.keys.toList()) {
          if (_selectedRoutines[key]!.sug.linkedActivity == sug.name) {
            final r = _selectedRoutines.remove(key)!;
            _selectedRoutines[key] = (sug: r.sug, domain: r.domain, freq: r.freq);
          }
        }
      } else {
        _selectedActivities[sug.name] = (sug: sug, domain: domain);
      }
    });
  }

  void _toggleRoutine(String domain, _RoutineSug sug) {
    setState(() {
      if (_selectedRoutines.containsKey(sug.name)) {
        _selectedRoutines.remove(sug.name);
      } else {
        _selectedRoutines[sug.name] = (sug: sug, domain: domain, freq: sug.defaultFreq);
      }
    });
  }

  void _setRoutineFreq(String name, HabitFreq freq) {
    final r = _selectedRoutines[name];
    if (r == null) return;
    setState(() => _selectedRoutines[name] = (sug: r.sug, domain: r.domain, freq: freq));
  }

  void _finish() {
    final logic = widget.logic;

    // 1. Domaines
    for (final name in _selectedDomains) {
      logic.state.domains.add(Domain(name: name));
    }
    final domainIds = {for (final d in logic.state.domains) d.name: d.id};

    // 2. Activités (time trackers)
    final createdActivities = <String, Activity>{};
    for (final entry in _selectedActivities.entries) {
      final sug = entry.value.sug;
      final domainId = domainIds[entry.value.domain] ?? logic.state.domains.firstOrNull?.id ?? '';
      final act = Activity(
        domainId: domainId,
        name: sug.name,
        type: 'time',
        goalMin: 30,
        targetSource: 'default',
        iconCode: sug.icon.codePoint,
      );
      logic.state.activities.add(act);
      createdActivities[sug.name] = act;
    }

    // 3. Routines (habits)
    for (final entry in _selectedRoutines.entries) {
      final sug = entry.value.sug;
      final freq = entry.value.freq;
      final domainId = domainIds[entry.value.domain] ?? logic.state.domains.firstOrNull?.id ?? '';
      final linkedAct = sug.linkedActivity != null ? createdActivities[sug.linkedActivity] : null;
      final habit = Activity(
        domainId: domainId,
        name: sug.name,
        type: 'habit',
        habitFreq: freq,
        habitTarget: sug.habitTarget,
        manualTarget: true,
        autoTune: false,
        iconCode: sug.icon.codePoint,
        linkedActivityId: linkedAct?.id,
      );
      logic.state.activities.add(habit);
      
    }

    // 4. Blocs par défaut si absents
    if (logic.state.blocks.isEmpty) {
      const names = ['Miracle Morning', 'Matinée', 'Midi', 'Après-midi', 'Soir', 'Routine Soir'];
      for (var i = 0; i < names.length; i++) {
        logic.state.blocks.add(DayBlock(name: names[i], order: i));
      }
    }

    logic.state.onboardingDone = true;
    logic.onChange();
    // → page ORION (page 5, index 5)
    _goTo(5);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Indicateur de progression ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == i ? cs.primary : cs.onSurface.withOpacity(.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ),

            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Page 1 — Bienvenue
                  _WelcomePage(
                    cs: cs,
                    onNext: () => _goTo(1),
                    onSelectPack: _applyPack,
                  ),

                  // Page 2 — Domaines
                  _DomainsPage(
                    cs: cs,
                    selected: _selectedDomains,
                    onToggle: (name) => setState(() {
                      if (_selectedDomains.contains(name)) {
                        _selectedDomains.remove(name);
                      } else {
                        _selectedDomains.add(name);
                      }
                    }),
                    onNext: () => _goTo(2),
                  ),

                  // Page 3 — Activités
                  _ActivitiesPage(
                    cs: cs,
                    selectedDomains: _selectedDomains,
                    selectedActivities: _selectedActivities,
                    onToggle: _toggleActivity,
                    onNext: () => _goTo(3),
                  ),

                  // Page 4 — Routines
                  _RoutinesPage(
                    cs: cs,
                    selectedDomains: _selectedDomains,
                    selectedActivities: _selectedActivities,
                    selectedRoutines: _selectedRoutines,
                    onToggle: _toggleRoutine,
                    onFreqChange: _setRoutineFreq,
                    onNext: () => _goTo(4),
                  ),

                  // Page 5 — Récap
                  _SummaryPage(
                    cs: cs,
                    selectedDomains: _selectedDomains,
                    selectedActivities: _selectedActivities,
                    selectedRoutines: _selectedRoutines,
                    onFinish: _finish,
                  ),

                  // Page 6 — Premier projet avec ORION
                  _OrionProjectPage(
                    cs: cs,
                    sync: widget.sync,
                    onDone: widget.onDone,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page 1 — Bienvenue
// ═══════════════════════════════════════════════════════════════════════════════

class _WelcomePage extends StatelessWidget {
  final ColorScheme cs;
  final VoidCallback onNext;
  final void Function(_PackDef) onSelectPack;
  const _WelcomePage({
    required this.cs,
    required this.onNext,
    required this.onSelectPack,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.rocket_launch_outlined, size: 40, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Productivitwo',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: cs.primary),
          ),
          const SizedBox(height: 8),
          Text(
            'Transforme tes intentions en actions.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: cs.onSurface.withOpacity(.55)),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'DÉMARRAGE RAPIDE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: cs.onSurface.withOpacity(.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final pack in _packs) ...[
            _PackCard(cs: cs, pack: pack, onTap: () => onSelectPack(pack)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: cs.onSurface.withOpacity(.12))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('ou', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.35))),
              ),
              Expanded(child: Divider(color: cs.onSurface.withOpacity(.12))),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onNext,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Configurer moi-même', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  final ColorScheme cs;
  final _PackDef pack;
  final VoidCallback onTap;
  const _PackCard({required this.cs, required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withOpacity(.15)),
        ),
        child: Row(
          children: [
            Text(pack.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(pack.description,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: cs.onSurface.withOpacity(.3)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page 2 — Domaines
// ═══════════════════════════════════════════════════════════════════════════════

const _domainList = [
  ('Santé', Icons.favorite_outline),
  ('Sport', Icons.fitness_center_outlined),
  ('Business', Icons.business_center_outlined),
  ('Organisation', Icons.calendar_today_outlined),
  ('Finances', Icons.calculate_outlined),
  ('Famille', Icons.people_outline),
  ('Spiritualité', Icons.church_outlined),
  ('Créativité', Icons.brush_outlined),
  ('Apprentissage', Icons.school_outlined),
  ('Social', Icons.handshake_outlined),
  ('Environnement', Icons.home_outlined),
  ('Bien-être', Icons.spa_outlined),
];

class _DomainsPage extends StatelessWidget {
  final ColorScheme cs;
  final Set<String> selected;
  final void Function(String) onToggle;
  final VoidCallback onNext;

  const _DomainsPage({
    required this.cs,
    required this.selected,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            cs: cs,
            title: 'Tes domaines de vie',
            subtitle: 'Sélectionne les sphères sur lesquelles tu veux progresser.',
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _domainList.map((item) {
                  final name = item.$1;
                  final icon = item.$2;
                  final isSelected = selected.contains(name);
                  return _SelectableChip(
                    cs: cs,
                    label: name,
                    icon: icon,
                    selected: isSelected,
                    onTap: () => onToggle(name),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: selected.isNotEmpty ? onNext : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              selected.isNotEmpty
                  ? 'Continuer (${selected.length} domaine${selected.length > 1 ? 's' : ''})'
                  : 'Sélectionne au moins un domaine',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page 3 — Activités
// ═══════════════════════════════════════════════════════════════════════════════

class _ActivitiesPage extends StatelessWidget {
  final ColorScheme cs;
  final Set<String> selectedDomains;
  final Map<String, ({_ActivitySug sug, String domain})> selectedActivities;
  final void Function(String domain, _ActivitySug sug) onToggle;
  final VoidCallback onNext;

  const _ActivitiesPage({
    required this.cs,
    required this.selectedDomains,
    required this.selectedActivities,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final domains = _domainList.where((d) =>
        selectedDomains.contains(d.$1) && _catalogue.containsKey(d.$1)).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            cs: cs,
            title: 'Tes activités',
            subtitle: 'Ce que tu veux tracker avec un chronomètre.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final domain in domains) ...[
                  _SectionHeader(cs: cs, icon: domain.$2, label: domain.$1),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _catalogue[domain.$1]!.activities.map((sug) {
                      final isSelected = selectedActivities.containsKey(sug.name);
                      return _SelectableChip(
                        cs: cs,
                        label: sug.name,
                        icon: sug.icon,
                        selected: isSelected,
                        onTap: () => onToggle(domain.$1, sug),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
          _BottomNav(
            cs: cs,
            primaryLabel: selectedActivities.isNotEmpty
                ? 'Continuer (${selectedActivities.length} activité${selectedActivities.length > 1 ? 's' : ''})'
                : 'Continuer',
            onPrimary: onNext,
            skipLabel: 'Passer cette étape',
            onSkip: onNext,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page 4 — Routines
// ═══════════════════════════════════════════════════════════════════════════════

class _RoutinesPage extends StatelessWidget {
  final ColorScheme cs;
  final Set<String> selectedDomains;
  final Map<String, ({_ActivitySug sug, String domain})> selectedActivities;
  final Map<String, ({_RoutineSug sug, String domain, HabitFreq freq})> selectedRoutines;
  final void Function(String domain, _RoutineSug sug) onToggle;
  final void Function(String name, HabitFreq freq) onFreqChange;
  final VoidCallback onNext;

  const _RoutinesPage({
    required this.cs,
    required this.selectedDomains,
    required this.selectedActivities,
    required this.selectedRoutines,
    required this.onToggle,
    required this.onFreqChange,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final domains = _domainList.where((d) =>
        selectedDomains.contains(d.$1) && _catalogue.containsKey(d.$1)).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            cs: cs,
            title: 'Tes routines',
            subtitle: 'Des habitudes à cocher au quotidien.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final domain in domains) ...[
                  _SectionHeader(cs: cs, icon: domain.$2, label: domain.$1),
                  const SizedBox(height: 8),
                  for (final sug in _catalogue[domain.$1]!.routines) ...[
                    _RoutineTile(
                      cs: cs,
                      sug: sug,
                      selected: selectedRoutines.containsKey(sug.name),
                      currentFreq: selectedRoutines[sug.name]?.freq ?? sug.defaultFreq,
                      activityLinked: sug.linkedActivity != null &&
                          selectedActivities.containsKey(sug.linkedActivity),
                      onTap: () => onToggle(domain.$1, sug),
                      onFreqChange: (f) => onFreqChange(sug.name, f),
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          _BottomNav(
            cs: cs,
            primaryLabel: selectedRoutines.isNotEmpty
                ? 'Continuer (${selectedRoutines.length} routine${selectedRoutines.length > 1 ? 's' : ''})'
                : 'Continuer',
            onPrimary: onNext,
            skipLabel: 'Passer cette étape',
            onSkip: onNext,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page 5 — Récapitulatif
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryPage extends StatelessWidget {
  final ColorScheme cs;
  final Set<String> selectedDomains;
  final Map<String, ({_ActivitySug sug, String domain})> selectedActivities;
  final Map<String, ({_RoutineSug sug, String domain, HabitFreq freq})> selectedRoutines;
  final VoidCallback onFinish;

  const _SummaryPage({
    required this.cs,
    required this.selectedDomains,
    required this.selectedActivities,
    required this.selectedRoutines,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = selectedActivities.isNotEmpty || selectedRoutines.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            cs: cs,
            title: 'Tout est prêt !',
            subtitle: hasContent
                ? 'Voici ce qui sera créé dans ton espace.'
                : 'Tu peux tout configurer depuis l\'app.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // Domaines
                _SummarySection(
                  cs: cs,
                  title: 'Domaines',
                  items: _domainList
                      .where((d) => selectedDomains.contains(d.$1))
                      .map((d) => (icon: d.$2, label: d.$1, sub: null))
                      .toList(),
                ),

                // Activités
                if (selectedActivities.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SummarySection(
                    cs: cs,
                    title: 'Activités (timer)',
                    items: selectedActivities.values
                        .map((e) => (icon: e.sug.icon, label: e.sug.name, sub: e.domain))
                        .toList(),
                  ),
                ],

                // Routines
                if (selectedRoutines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SummarySection(
                    cs: cs,
                    title: 'Routines',
                    items: selectedRoutines.values.map((e) {
                      final linked = e.sug.linkedActivity != null &&
                          selectedActivities.containsKey(e.sug.linkedActivity);
                      final sub = [
                        _freqLabel(e.freq),
                        if (linked) '⏱ ${e.sug.linkedActivity}',
                      ].join(' · ');
                      return (icon: e.sug.icon, label: e.sug.name, sub: sub);
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
          FilledButton(
            onPressed: onFinish,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text("C'est parti ! 🚀",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets helpers
// ═══════════════════════════════════════════════════════════════════════════════

class _PageHeader extends StatelessWidget {
  final ColorScheme cs;
  final String title;
  final String subtitle;
  const _PageHeader({required this.cs, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.5))),
        ],
      );
}

class _SectionHeader extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label;
  const _SectionHeader({required this.cs, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: cs.primary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
        ],
      );
}

class _SelectableChip extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableChip({
    required this.cs,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.primary.withOpacity(.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16,
                  color: selected ? cs.onPrimary : cs.primary.withOpacity(.8)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? cs.onPrimary : cs.primary.withOpacity(.8),
                  )),
            ],
          ),
        ),
      );
}

class _RoutineTile extends StatelessWidget {
  final ColorScheme cs;
  final _RoutineSug sug;
  final bool selected;
  final HabitFreq currentFreq;
  final bool activityLinked;
  final VoidCallback onTap;
  final void Function(HabitFreq) onFreqChange;

  const _RoutineTile({
    required this.cs,
    required this.sug,
    required this.selected,
    required this.currentFreq,
    required this.activityLinked,
    required this.onTap,
    required this.onFreqChange,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withOpacity(.5) : cs.surfaceContainerHighest.withOpacity(.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary.withOpacity(.35) : cs.onSurface.withOpacity(.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(sug.icon, size: 20,
                      color: selected ? cs.primary : cs.onSurface.withOpacity(.45)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(sug.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: selected ? cs.onSurface : cs.onSurface.withOpacity(.7),
                        )),
                  ),
                  if (activityLinked)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 10, color: cs.secondary),
                          const SizedBox(width: 3),
                          Text(sug.linkedActivity!,
                              style: TextStyle(fontSize: 10, color: cs.secondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? cs.primary : cs.onSurface.withOpacity(.25),
                  ),
                ],
              ),
            ),

            // Sélecteur de fréquence (animé)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Row(
                        children: [
                          for (final f in HabitFreq.values) ...[
                            if (f != HabitFreq.values.first) const SizedBox(width: 6),
                            _FreqChip(
                              cs: cs,
                              label: _freqLabel(f),
                              selected: currentFreq == f,
                              onTap: () => onFreqChange(f),
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreqChip extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FreqChip({
    required this.cs,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.onSurface.withOpacity(.07),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurface.withOpacity(.55),
              )),
        ),
      );
}

class _BottomNav extends StatelessWidget {
  final ColorScheme cs;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String skipLabel;
  final VoidCallback onSkip;

  const _BottomNav({
    required this.cs,
    required this.primaryLabel,
    required this.onPrimary,
    required this.skipLabel,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(primaryLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onSkip,
            child: Text(skipLabel,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.35))),
          ),
        ],
      );
}

class _SummarySection extends StatelessWidget {
  final ColorScheme cs;
  final String title;
  final List<({IconData icon, String label, String? sub})> items;

  const _SummarySection({
    required this.cs,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: cs.onSurface.withOpacity(.4))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 18, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.label,
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                              if (item.sub != null)
                                Text(item.sub!,
                                    style: TextStyle(
                                        fontSize: 12, color: cs.onSurface.withOpacity(.45))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < items.length - 1)
                    Divider(height: 1, indent: 42, color: cs.onSurface.withOpacity(.07)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogueSheet — Ajouter des éléments du catalogue post-onboarding
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogueSheet extends StatefulWidget {
  final AppLogic logic;
  final VoidCallback onChanged;
  const CatalogueSheet({super.key, required this.logic, required this.onChanged});

  @override
  State<CatalogueSheet> createState() => _CatalogueSheetState();
}

class _CatalogueSheetState extends State<CatalogueSheet> {
  final _pageCtrl = PageController();
  int _page = 0;

  final Set<String> _newDomains = {};
  final Map<String, ({_ActivitySug sug, String domain})> _newActivities = {};
  final Map<String, ({_RoutineSug sug, String domain, HabitFreq freq})> _newRoutines = {};

  Set<String> get _existingDomainNames =>
      widget.logic.state.domains.map((d) => d.name).toSet();

  Set<String> get _activeDomains => _existingDomainNames.union(_newDomains);

  bool _activityExists(String name) =>
      widget.logic.state.activities.any((a) => a.name == name && a.type == 'time');

  bool _routineExists(String name) =>
      widget.logic.state.activities.any((a) => a.name == name && a.type == 'habit');

  void _goTo(int p) {
    _pageCtrl.animateToPage(p, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _page = p);
  }

  void _finish() {
    final logic = widget.logic;
    final state = logic.state;
    final hasNew = _newDomains.isNotEmpty || _newActivities.isNotEmpty || _newRoutines.isNotEmpty;

    for (final name in _newDomains) state.domains.add(Domain(name: name));
    final domainIds = {for (final d in state.domains) d.name: d.id};

    final allTimeActivities = <String, Activity>{
      for (final a in state.activities.where((a) => a.type == 'time')) a.name: a,
    };

    for (final entry in _newActivities.entries) {
      final sug = entry.value.sug;
      final act = Activity(
        domainId: domainIds[entry.value.domain] ?? state.domains.firstOrNull?.id ?? '',
        name: sug.name, type: 'time', goalMin: 30, targetSource: 'default',
        iconCode: sug.icon.codePoint,
      );
      state.activities.add(act);
      allTimeActivities[sug.name] = act;
    }

    for (final entry in _newRoutines.entries) {
      final sug = entry.value.sug;
      final linkedAct = sug.linkedActivity != null ? allTimeActivities[sug.linkedActivity] : null;
      final habit = Activity(
        domainId: domainIds[entry.value.domain] ?? state.domains.firstOrNull?.id ?? '',
        name: sug.name, type: 'habit',
        habitFreq: entry.value.freq, habitTarget: sug.habitTarget,
        manualTarget: true, autoTune: false, iconCode: sug.icon.codePoint,
        linkedActivityId: linkedAct?.id,
      );
      state.activities.add(habit);
      
    }

    if (hasNew) {
      logic.onChange();
      widget.onChanged();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titles = ['Domaines', 'Activités', 'Routines'];
    final totalNew = _newDomains.length + _newActivities.length + _newRoutines.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(children: [
            Expanded(
              child: Text(titles[_page],
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
            ),
            Row(children: List.generate(3, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _page == i ? 18 : 6, height: 6,
              decoration: BoxDecoration(
                color: _page == i ? cs.primary : cs.onSurface.withOpacity(.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ))),
          ]),
        ),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildDomainsPage(cs),
              _buildActivitiesPage(cs),
              _buildRoutinesPage(cs, totalNew),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDomainsPage(ColorScheme cs) {
    final existing = _existingDomainNames;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grisés = déjà actifs', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.45))),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10, runSpacing: 10,
                children: _domainList.map((item) {
                  final name = item.$1;
                  final isExisting = existing.contains(name);
                  final isNewSel = _newDomains.contains(name);
                  return _CatalogChip(
                    cs: cs, label: name, icon: item.$2,
                    selected: isExisting || isNewSel,
                    disabled: isExisting,
                    onTap: isExisting ? null : () => setState(() {
                      if (_newDomains.contains(name)) {
                        _newDomains.remove(name);
                        _newActivities.removeWhere((_, v) => v.domain == name);
                        _newRoutines.removeWhere((_, v) => v.domain == name);
                      } else {
                        _newDomains.add(name);
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _goTo(1),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Continuer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesPage(ColorScheme cs) {
    final domains = _domainList
        .where((d) => _activeDomains.contains(d.$1) && _catalogue.containsKey(d.$1))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grisées = déjà ajoutées', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.45))),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final domain in domains) ...[
                  _SectionHeader(cs: cs, icon: domain.$2, label: domain.$1),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _catalogue[domain.$1]!.activities.map((sug) {
                      final exists = _activityExists(sug.name);
                      final newSel = _newActivities.containsKey(sug.name);
                      return _CatalogChip(
                        cs: cs, label: sug.name, icon: sug.icon,
                        selected: exists || newSel, disabled: exists,
                        onTap: exists ? null : () => setState(() {
                          if (newSel) _newActivities.remove(sug.name);
                          else _newActivities[sug.name] = (sug: sug, domain: domain.$1);
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
          _BottomNav(
            cs: cs,
            primaryLabel: _newActivities.isNotEmpty
                ? 'Continuer (${_newActivities.length} nouvelle${_newActivities.length > 1 ? 's' : ''})'
                : 'Continuer',
            onPrimary: () => _goTo(2),
            skipLabel: 'Passer',
            onSkip: () => _goTo(2),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutinesPage(ColorScheme cs, int totalNew) {
    final domains = _domainList
        .where((d) => _activeDomains.contains(d.$1) && _catalogue.containsKey(d.$1))
        .toList();
    final allTimeActivities = {
      for (final a in widget.logic.state.activities.where((a) => a.type == 'time')) a.name: true,
      for (final e in _newActivities.entries) e.key: true,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grisées = déjà ajoutées', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.45))),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final domain in domains) ...[
                  _SectionHeader(cs: cs, icon: domain.$2, label: domain.$1),
                  const SizedBox(height: 8),
                  for (final sug in _catalogue[domain.$1]!.routines) ...[
                    _buildRoutineTile(cs, sug, domain.$1, allTimeActivities),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _finish,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              totalNew > 0
                  ? 'Ajouter ($totalNew élément${totalNew > 1 ? 's' : ''})'
                  : 'Fermer',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineTile(
    ColorScheme cs, _RoutineSug sug, String domain, Map<String, bool> allActivities,
  ) {
    final exists = _routineExists(sug.name);
    final newSel = _newRoutines.containsKey(sug.name);
    final currentFreq = _newRoutines[sug.name]?.freq ?? sug.defaultFreq;
    final activityLinked = sug.linkedActivity != null && allActivities.containsKey(sug.linkedActivity);

    if (exists) {
      return Opacity(
        opacity: 0.45,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.4),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(sug.icon, size: 20, color: cs.onSurface.withOpacity(.45)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(sug.name,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              Icon(Icons.check_circle_rounded, size: 20, color: cs.primary),
            ],
          ),
        ),
      );
    }

    return _RoutineTile(
      cs: cs, sug: sug, selected: newSel,
      currentFreq: currentFreq, activityLinked: activityLinked,
      onTap: () => setState(() {
        if (newSel) _newRoutines.remove(sug.name);
        else _newRoutines[sug.name] = (sug: sug, domain: domain, freq: sug.defaultFreq);
      }),
      onFreqChange: (f) {
        final r = _newRoutines[sug.name];
        if (r != null) setState(() => _newRoutines[sug.name] = (sug: r.sug, domain: r.domain, freq: f));
      },
    );
  }
}

class _CatalogChip extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final IconData icon;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _CatalogChip({
    required this.cs, required this.label, required this.icon,
    required this.selected, required this.disabled, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.primary.withOpacity(.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16,
                  color: selected ? cs.onPrimary : cs.primary.withOpacity(.8)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: selected ? cs.onPrimary : cs.primary.withOpacity(.8),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Page 6 — Premier projet avec ORION
// ═══════════════════════════════════════════════════════════════════════════════

class _OrionProjectPage extends StatefulWidget {
  final ColorScheme cs;
  final FirestoreSync sync;
  final VoidCallback onDone;

  const _OrionProjectPage({
    required this.cs,
    required this.sync,
    required this.onDone,
  });

  @override
  State<_OrionProjectPage> createState() => _OrionProjectPageState();
}

class _OrionProjectPageState extends State<_OrionProjectPage> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;

  static const _orionUrl = 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    setState(() => _loading = true);
    try {
      final uid = widget.sync.uid;
      if (uid != null) {
        // Domaine Test — pour s'entraîner à créer activités/routines et le supprimer
        await widget.sync.saveDomain(Domain(name: 'Domaine Test'));
        await widget.sync.saveProject(buildDiscoveryProject(uid));
      }
    } catch (_) {
      // Le projet de découverte est optionnel — on continue même en cas d'erreur
    }
    widget.onDone();
  }

  Future<void> _createProject() async {
    final desc = _ctrl.text.trim();
    if (desc.isEmpty) return;

    setState(() { _loading = true; _error = null; });

    try {
      final uid = widget.sync.uid;
      if (uid == null) throw Exception('Non connecté');

      // Token auto-créé si absent — transparent pour l'utilisateur
      final apiToken = await widget.sync.ensureOnboardingToken();

      final resp = await http.post(
        Uri.parse(_orionUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'uid': uid,
          'token': apiToken.rawToken,
          'userNeeds': 'ONBOARDING — Crée un projet Gantt pour ce besoin : $desc',
          'isOnboarding': true,
        }),
      );

      if (resp.statusCode == 200) {
        setState(() { _done = true; _loading = false; });
      } else {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        setState(() {
          _error = body['error']?.toString() ?? 'Erreur ${resp.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Text('✦', style: TextStyle(fontSize: 28, color: cs.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Votre premier projet',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ORION va créer un projet Gantt structuré en quelques secondes. Décrivez simplement ce que vous voulez accomplir.',
            style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.6), height: 1.5),
          ),
          const SizedBox(height: 28),

          if (!_done) ...[
            TextField(
              controller: _ctrl,
              enabled: !_loading,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ex : lancer une boutique en ligne de vêtements durables d\'ici septembre',
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(.35), fontSize: 14),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _createProject,
                icon: _loading
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_loading ? 'ORION travaille…' : 'Créer mon projet'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: _loading ? null : () => _finishOnboarding(),
                child: Text('Passer cette étape', style: TextStyle(color: cs.onSurface.withOpacity(.45))),
              ),
            ),
          ] else ...[
            // Succès
            const Spacer(),
            Center(
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Projet créé !',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Retrouvez-le dans l\'onglet Projets.',
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.55)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : () => _finishOnboarding(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Commencer →'),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Projet de prise en main — créé automatiquement en fin d'onboarding
// ═══════════════════════════════════════════════════════════════════════════════

Project buildDiscoveryProject(String createdBy) {
  final today = DateTime.now();
  final t = DateTime(today.year, today.month, today.day);

  // ── Phase unique ─────────────────────────────────────────────────────────────
  final pDecouverte = ProjectPhase(
    label: 'Découverte',
    startDate: t,
    endDate: t.add(const Duration(days: 7)),
  );

  // ── 5 tâches essentielles ────────────────────────────────────────────────────
  final tasks = [
    ProjectTask(
      title: 'Ajouter et cocher une sous-action',
      phaseId: pDecouverte.id,
      startDate: t,
      todayFlag: true,
      actions: [
        TaskAction(title: 'Appuie sur ⊕ sous cette tâche'),
        TaskAction(title: 'Écris une sous-action et valide'),
        TaskAction(title: 'Coche-la ✓'),
      ],
    ),
    ProjectTask(
      title: 'Lancer un timer sur une activité',
      phaseId: pDecouverte.id,
      startDate: t,
      actions: [
        TaskAction(title: 'Sur l\'écran principal, appuie sur « Activités » du domaine Test'),
        TaskAction(title: 'Appuie sur « Nouvelle activité » et nomme-la'),
        TaskAction(title: 'Appuie sur ▶ pour démarrer le timer'),
        TaskAction(title: 'Appuie sur ⏹ pour arrêter'),
      ],
    ),
    ProjectTask(
      title: 'Cocher une routine du jour',
      phaseId: pDecouverte.id,
      startDate: t,
      actions: [
        TaskAction(title: 'Sur l\'écran principal, repère tes routines du jour'),
        TaskAction(title: 'Appuie sur une routine pour la cocher ✓'),
      ],
    ),
    ProjectTask(
      title: 'Explorer ORION',
      phaseId: pDecouverte.id,
      startDate: t,
      actions: [
        TaskAction(title: 'Appuie sur l\'onglet ✦ ORION'),
        TaskAction(title: 'Lis le rapport hebdomadaire'),
        TaskAction(title: 'Capture une idée via 💡 en haut à droite'),
      ],
    ),
    ProjectTask(
      title: 'Créer ton premier vrai projet',
      phaseId: pDecouverte.id,
      startDate: t,
      actions: [
        TaskAction(title: 'Aller sur l\'onglet Projets'),
        TaskAction(title: 'Appuyer sur + Nouveau projet'),
        TaskAction(title: 'Décrire ton objectif en langage naturel — ORION s\'occupe du reste'),
      ],
    ),
  ];

  return Project(
    title: 'Prise en main de Productivitwo',
    description: 'Découvre l\'essentiel en 5 étapes — coche les sous-actions au fur et à mesure !',
    startDate: t,
    endDate: t.add(const Duration(days: 7)),
    status: 'active',
    phases: [pDecouverte],
    tasks: tasks,
    createdBy: createdBy,
    sourceType: 'onboarding',
  );
}
