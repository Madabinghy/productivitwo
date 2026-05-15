import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

class OnboardingScreen extends StatefulWidget {
  final AppLogic logic;
  final VoidCallback onDone;

  const OnboardingScreen({
    super.key,
    required this.logic,
    required this.onDone,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  // ── Domaines ──────────────────────────────────────────────────────────────
  static const _domainSuggestions = [
    ('Santé', '❤️'),
    ('Sport', '💪'),
    ('Business', '💼'),
    ('Organisation', '📋'),
    ('Finances', '💰'),
    ('Famille', '👨‍👩‍👧'),
    ('Spiritualité', '🙏'),
    ('Créativité', '🎨'),
    ('Apprentissage', '📚'),
    ('Social', '🤝'),
    ('Environnement', '🌿'),
    ('Bien-être', '🧘'),
  ];

  final Set<String> _selectedDomains = {};
  final _customDomainCtrl = TextEditingController();

  // ── Routine ───────────────────────────────────────────────────────────────
  final _routineCtrl = TextEditingController();
  HabitFreq _routineFreq = HabitFreq.daily;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _customDomainCtrl.dispose();
    _routineCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageCtrl.animateToPage(page,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _page = page);
  }

  void _finish() {
    final logic = widget.logic;

    // Créer les domaines sélectionnés
    for (final name in _selectedDomains) {
      logic.createDomain(name);
    }

    // Créer la routine si remplie
    final routineTitle = _routineCtrl.text.trim();
    if (routineTitle.isNotEmpty && logic.state.domains.isNotEmpty) {
      final domainId = logic.state.domains.first.id;
      logic.createHabit(
        domainId: domainId,
        name: routineTitle,
        freq: _routineFreq,
      );
    }

    // Pré-configurer "Boire de l'eau" dans tous les blocs comme exemple concret
    // de routine multi-blocs. L'utilisateur voit directement le concept en action.
    if (logic.state.domains.isNotEmpty && logic.state.blocks.isNotEmpty) {
      final santeId =
          logic.state.domains.firstWhereOrNull((d) => d.name == 'Santé')?.id ??
              logic.state.domains.first.id;

      final hydratation = Activity(
        domainId: santeId,
        name: 'Hydratation',
        type: 'time',
        goalMin: 1,
      );
      logic.state.activities.add(hydratation);

      final eau = Activity(
        domainId: santeId,
        name: "Boire de l'eau",
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: 8,
        manualTarget: true,
        autoTune: false,
        linkedActivityId: hydratation.id,
        iconCode: 0xf0695, // Icons.water_drop_outlined
      );
      logic.state.activities.add(eau);

      for (final b in logic.state.blocks) {
        if (!b.activityIds.contains(eau.id)) b.activityIds.add(eau.id);
      }

      logic.ensureHabitPlannedForDay(yyyymmdd(DateTime.now()), eau.id);
    }

    logic.state.onboardingDone = true;
    logic.onChange();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? cs.primary
                        : cs.onSurface.withOpacity(.2),
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
                  _WelcomePage(cs: cs, onNext: () => _goTo(1)),
                  _DomainsPage(
                    cs: cs,
                    suggestions: _domainSuggestions,
                    selected: _selectedDomains,
                    customCtrl: _customDomainCtrl,
                    onToggle: (name) => setState(() {
                      if (_selectedDomains.contains(name)) {
                        _selectedDomains.remove(name);
                      } else {
                        _selectedDomains.add(name);
                      }
                    }),
                    onAddCustom: () {
                      final v = _customDomainCtrl.text.trim();
                      if (v.isNotEmpty) {
                        setState(() => _selectedDomains.add(v));
                        _customDomainCtrl.clear();
                      }
                    },
                    onNext: () => _goTo(2),
                    canContinue: _selectedDomains.isNotEmpty,
                  ),
                  _RoutinePage(
                    cs: cs,
                    ctrl: _routineCtrl,
                    freq: _routineFreq,
                    onFreqChanged: (f) => setState(() => _routineFreq = f),
                    onFinish: _finish,
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

// ── Page 1 : Bienvenue ────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final ColorScheme cs;
  final VoidCallback onNext;
  const _WelcomePage({required this.cs, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        children: [
          const Spacer(),
          Text('🎯',
              style: const TextStyle(fontSize: 72)),
          const SizedBox(height: 24),
          Text(
            'Productivitwo',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Transforme tes intentions en actions.\nSuis tes routines, avance sur tes objectifs,\ndeviens la version que tu veux être.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
              color: cs.onSurface.withOpacity(.65),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: const Text('Commencer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text(
            'Configuration rapide · 2 minutes',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(.35)),
          ),
        ],
      ),
    );
  }
}

// ── Page 2 : Domaines ─────────────────────────────────────────────────────────

class _DomainsPage extends StatelessWidget {
  final ColorScheme cs;
  final List<(String, String)> suggestions;
  final Set<String> selected;
  final TextEditingController customCtrl;
  final void Function(String) onToggle;
  final VoidCallback onAddCustom;
  final VoidCallback onNext;
  final bool canContinue;

  const _DomainsPage({
    required this.cs,
    required this.suggestions,
    required this.selected,
    required this.customCtrl,
    required this.onToggle,
    required this.onAddCustom,
    required this.onNext,
    required this.canContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tes domaines de vie',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text(
            'Choisis les sphères sur lesquelles tu veux progresser.',
            style: TextStyle(
                fontSize: 14, color: cs.onSurface.withOpacity(.5)),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: suggestions.map((s) {
                      final name = s.$1;
                      final emoji = s.$2;
                      final isSelected = selected.contains(name);
                      return GestureDetector(
                        onTap: () => onToggle(name),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? cs.primary
                                : cs.primary.withOpacity(.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? cs.onPrimary
                                      : cs.primary.withOpacity(.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Domaine custom
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customCtrl,
                          decoration: InputDecoration(
                            hintText: 'Ajouter un domaine…',
                            hintStyle: TextStyle(
                                color: cs.onSurface.withOpacity(.35)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: cs.onSurface.withOpacity(.2)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: cs.onSurface.withOpacity(.15)),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => onAddCustom(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onAddCustom,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            padding: EdgeInsets.zero),
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ),

                  // Domaines custom sélectionnés
                  if (selected.any((s) =>
                      !suggestions.any((sug) => sug.$1 == s))) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: selected
                          .where((s) =>
                              !suggestions.any((sug) => sug.$1 == s))
                          .map((s) => Chip(
                                label: Text(s),
                                onDeleted: () => onToggle(s),
                                backgroundColor:
                                    cs.primary.withOpacity(.1),
                                labelStyle: TextStyle(color: cs.primary),
                                side: BorderSide.none,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canContinue ? onNext : null,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: Text(
              canContinue
                  ? 'Continuer (${selected.length} domaine${selected.length > 1 ? 's' : ''})'
                  : 'Sélectionne au moins un domaine',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 3 : Première routine ──────────────────────────────────────────────────

class _RoutinePage extends StatelessWidget {
  final ColorScheme cs;
  final TextEditingController ctrl;
  final HabitFreq freq;
  final void Function(HabitFreq) onFreqChanged;
  final VoidCallback onFinish;

  const _RoutinePage({
    required this.cs,
    required this.ctrl,
    required this.freq,
    required this.onFreqChanged,
    required this.onFinish,
  });

  static const _suggestions = [
    'Méditer', 'Faire du sport', 'Lire', 'Boire de l\'eau',
    'Journaling', 'Apprendre', 'Gratitude',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ta première routine',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text(
            'Quelle habitude veux-tu ancrer ? Tu pourras en ajouter d\'autres après.',
            style: TextStyle(
                fontSize: 14, color: cs.onSurface.withOpacity(.5)),
          ),
          const SizedBox(height: 20),

          // Suggestions rapides
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((s) => GestureDetector(
              onTap: () => ctrl.text = s,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: cs.onSurface.withOpacity(.15)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(s,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(.7))),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),

          // Nom
          TextField(
            controller: ctrl,
            autofocus: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Nom de la routine…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: cs.onSurface.withOpacity(.2)),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Fréquence
          Text('Fréquence',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(.55))),
          const SizedBox(height: 8),
          Row(
            children: [
              _freqChip(context, 'Quotidienne', HabitFreq.daily),
              const SizedBox(width: 8),
              _freqChip(context, 'Hebdomadaire', HabitFreq.weekly),
              const SizedBox(width: 8),
              _freqChip(context, 'Mensuelle', HabitFreq.monthly),
            ],
          ),

          const Spacer(),
          FilledButton(
            onPressed: onFinish,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: const Text("C'est parti ! 🚀",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onFinish,
              child: Text('Passer cette étape',
                  style: TextStyle(
                      color: cs.onSurface.withOpacity(.35),
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _freqChip(BuildContext context, String label, HabitFreq f) {
    final selected = freq == f;
    return GestureDetector(
      onTap: () => onFreqChanged(f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.primary.withOpacity(.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color:
                selected ? cs.onPrimary : cs.primary.withOpacity(.7),
          ),
        ),
      ),
    );
  }
}
