import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

/// Moteur de RECONQUÊTE (couche jeu, découplée du relevé factuel).
///
/// Lit le registre `state.redemptions` (crédits imputés à des jours passés en
/// dette) SANS jamais toucher aux sessions/hits réels. Ces crédits réduisent les
/// PV des ennemis du jardin (branchements dans `gold_engine` : `enemyHp`, tokens)
/// et n'apparaissent JAMAIS dans le rapport temps / budgets / ORION.
///
/// Clé-jour = `yyyymmdd()` (sans tiret), cohérente avec `_minutesOnDay`,
/// `habitValueOn`, `_activityLoggedMinutes`.
extension RedemptionEngine on AppLogic {
  /// Somme des crédits de reconquête ACTIFS pour [activityId], le jour [dayKey]
  /// (format `yyyymmdd`) et le [type] (`"time"` → minutes · `"habit"` → hits).
  /// Renvoie 0 si aucun crédit (cas par défaut tant que la Phase 2 n'écrit rien).
  int redemptionCreditsOn(String activityId, String dayKey, String type) {
    var sum = 0;
    for (final r in state.redemptions) {
      if (!r.active) continue;
      if (r.activityId != activityId) continue;
      if (r.type != type) continue;
      if (r.targetDate != dayKey) continue;
      sum += r.amount;
    }
    return sum;
  }
}
