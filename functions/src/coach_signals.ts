// Signaux de la semaine pour le coach (maquette validée 2026-11-01 « Cockpit
// coach »). Calculés par l'APP (`lib/utils/coach_signals.dart`) et déposés
// dans `data/badges.signals` ; le serveur ne recalcule rien, il FILTRE selon
// le consentement du coaché :
//   - `games` (parole tenue, Montre suisse, Métronome, posé la veille) : opt-in ;
//     une activité d'un domaine non partagé n'apparaît jamais, même nommée ;
//   - `sleep` : opt-in à part (c'est intime).
// Puis il en tire des lignes de rapport et des points « À aborder en séance »,
// par règles fixes (seuils, comparaisons), jamais par IA.

type Json = Record<string, unknown>;

export type CoachSignals = {
  days: string[];
  watch?: { days: (boolean | null)[]; blockers: { name: string; lostDays: number; goalMin: number }[] };
  metronome?: { days: (boolean | null)[] };
  parole?: { days: (boolean | null)[] };
  cap?: { days: ("held" | "posed" | null)[] };
  sleep?: {
    nights: (number | null)[];
    nightsBefore: (number | null)[];
    targetMin: number;
    avgMin: number | null;
    debtMin: number;
    avgBed: number | null;
    spreadMin: number | null;
    plannedBed: number | null;
    impact?: { longLowPct: number; shortLowPct: number; longDays: number; shortDays: number };
  };
};

const boolDays = (v: unknown): (boolean | null)[] =>
  Array.isArray(v) ? v.map((x) => (x === true ? true : x === false ? false : null)) : [];

const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/** Ce que le coach a le droit de voir, d'après le consentement. null = rien. */
export function signalsForCoach(
  raw: unknown,
  sharing: { games?: boolean; sleep?: boolean },
  sharedDomains: Set<string>,
): CoachSignals | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Json;
  const days = Array.isArray(r.days) ? r.days.map(String) : [];
  if (days.length === 0) return null;
  const out: CoachSignals = { days };
  if (sharing.games === true) {
    const w = (r.watch ?? {}) as Json;
    const blockers = Array.isArray(w.blockers) ? (w.blockers as Json[]) : [];
    out.watch = {
      days: boolDays(w.days),
      blockers: blockers
        .filter((b) => typeof b.domainId === "string" && sharedDomains.has(b.domainId as string))
        .map((b) => ({ name: String(b.name ?? ""), lostDays: num(b.lostDays) ?? 0, goalMin: num(b.goalMin) ?? 0 })),
    };
    out.metronome = { days: boolDays(((r.metronome ?? {}) as Json).days) };
    out.parole = { days: boolDays(((r.parole ?? {}) as Json).days) };
    const capDays = ((r.cap ?? {}) as Json).days;
    out.cap = { days: Array.isArray(capDays) ? capDays.map((x) => (x === "held" || x === "posed" ? x : null)) : [] };
  }
  if (sharing.sleep === true && r.sleep && typeof r.sleep === "object") {
    const s = r.sleep as Json;
    const imp = s.impact as Json | undefined;
    out.sleep = {
      nights: Array.isArray(s.nights) ? s.nights.map(num) : [],
      nightsBefore: Array.isArray(s.nightsBefore) ? s.nightsBefore.map(num) : [],
      targetMin: num(s.targetMin) ?? 450,
      avgMin: num(s.avgMin),
      debtMin: num(s.debtMin) ?? 0,
      avgBed: num(s.avgBed),
      spreadMin: num(s.spreadMin),
      plannedBed: num(s.plannedBed),
      ...(imp && num(imp.longLowPct) != null && num(imp.shortLowPct) != null
        ? { impact: { longLowPct: num(imp.longLowPct)!, shortLowPct: num(imp.shortLowPct)!, longDays: num(imp.longDays) ?? 0, shortDays: num(imp.shortDays) ?? 0 } }
        : {}),
    };
  }
  return out.watch || out.sleep ? out : null;
}

/** « 6 h 10 » / « 45 min ». */
export function fmtMin(m: number): string {
  if (m <= 0) return "0 min";
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}`;
}

/** Horloge autour de minuit (−20 = 23:40) → « 23:40 ». */
export function clockOf(m: number): string {
  const v = ((m % 1440) + 1440) % 1440;
  return `${String(Math.floor(v / 60)).padStart(2, "0")}:${String(v % 60).padStart(2, "0")}`;
}

const count = (xs: unknown[], v: unknown) => xs.filter((x) => x === v).length;
const measured = (xs: unknown[]) => xs.filter((x) => x !== null && x !== undefined).length;

export type SignalTiles = {
  sleep?: { avgMin: number | null; debtMin: number; shortNights: number; nights: number };
  parole?: { held: number; given: number };
  watch?: { won: number; measured: number; blocker: string | null };
  metronome?: { won: number; measured: number };
  cap?: { posed: number; held: number };
};

export function signalTiles(s: CoachSignals): SignalTiles {
  const t: SignalTiles = {};
  if (s.sleep) {
    const ns = s.sleep.nights.filter((n): n is number => n != null);
    t.sleep = { avgMin: s.sleep.avgMin, debtMin: s.sleep.debtMin, shortNights: ns.filter((n) => n < s.sleep!.targetMin - 30).length, nights: ns.length };
  }
  if (s.parole) t.parole = { held: count(s.parole.days, true), given: measured(s.parole.days) };
  if (s.watch) t.watch = { won: count(s.watch.days, true), measured: measured(s.watch.days), blocker: s.watch.blockers[0]?.name ?? null };
  if (s.metronome) t.metronome = { won: count(s.metronome.days, true), measured: measured(s.metronome.days) };
  if (s.cap) t.cap = { posed: measured(s.cap.days), held: count(s.cap.days, "held") };
  return t;
}

/** Lignes ajoutées au rapport de pré-séance. */
export function signalReportLines(s: CoachSignals): string[] {
  const t = signalTiles(s);
  const lines: string[] = [];
  if (s.sleep && t.sleep && t.sleep.nights > 0) {
    lines.push(`Sommeil : ${fmtMin(t.sleep.avgMin ?? 0)} en moyenne · dette ${fmtMin(t.sleep.debtMin)} sur 7 nuits · ${t.sleep.shortNights} nuit${t.sleep.shortNights > 1 ? "s" : ""} courte${t.sleep.shortNights > 1 ? "s" : ""}`);
    if (s.sleep.avgBed != null) {
      lines.push(`  coucher ${clockOf(s.sleep.avgBed)}${s.sleep.plannedBed != null ? ` (bloc ${clockOf(s.sleep.plannedBed)})` : ""}${s.sleep.spreadMin != null ? ` · ± ${s.sleep.spreadMin} min` : ""}`);
    }
    if (s.sleep.impact) lines.push(`  après une nuit courte : ${s.sleep.impact.shortLowPct} % du temps en Flemme (contre ${s.sleep.impact.longLowPct} %)`);
  }
  if (t.parole && t.parole.given > 0) lines.push(`Parole tenue : ${t.parole.held} jour${t.parole.held > 1 ? "s" : ""} sur ${t.parole.given} donné${t.parole.given > 1 ? "s" : ""}`);
  if (t.watch && t.watch.measured > 0) lines.push(`Montre suisse : ${t.watch.won} / ${t.watch.measured}${t.watch.blocker ? ` · bloque : ${t.watch.blocker}` : ""}`);
  if (t.metronome && t.metronome.measured > 0) lines.push(`Métronome : ${t.metronome.won} / ${t.metronome.measured}`);
  if (t.cap) lines.push(`Posé la veille : ${t.cap.posed} / 7${t.cap.posed > 0 ? ` · tenus ${t.cap.held}` : ""}`);
  return lines;
}

/** « À aborder en séance » : 4 phrases au plus, les signaux qui bougent. */
export function talkingPoints(s: CoachSignals): string[] {
  const t = signalTiles(s);
  const out: string[] = [];
  if (s.sleep && t.sleep && t.sleep.nights >= 3 && t.sleep.shortNights >= 3) {
    let p = `Nuits courtes ${t.sleep.shortNights} sur ${t.sleep.nights}`;
    if (s.sleep.avgBed != null && s.sleep.plannedBed != null && s.sleep.avgBed - s.sleep.plannedBed >= 20) {
      p += `, couché·e en moyenne à ${clockOf(s.sleep.avgBed)}, ${fmtMin(s.sleep.avgBed - s.sleep.plannedBed)} après son bloc Sommeil`;
    }
    if (s.sleep.impact && s.sleep.impact.shortLowPct > s.sleep.impact.longLowPct) {
      p += `. Après une nuit courte, son temps en Flemme passe de ${s.sleep.impact.longLowPct} % à ${s.sleep.impact.shortLowPct} %`;
    }
    out.push(p + ".");
  }
  if (t.parole && t.parole.given >= 2 && t.parole.held < t.parole.given) {
    let p = `Parole donnée ${t.parole.given} jours, tenue ${t.parole.held}.`;
    if (s.sleep && s.parole) {
      // Jours manqués qui suivent une nuit courte (`nightsBefore` aligné sur `days`).
      const before = s.sleep.nightsBefore;
      const missed = s.parole.days.map((d, i) => (d === false ? before[i] : undefined)).filter((n) => n !== undefined);
      const afterShort = missed.filter((n) => n != null && n < s.sleep!.targetMin - 30).length;
      if (missed.length > 0 && afterShort === missed.length) p += missed.length > 1 ? " Les jours manqués suivent une nuit courte." : " Le jour manqué suit une nuit courte.";
    }
    out.push(p);
  }
  if (t.watch && t.watch.measured > 0 && t.watch.measured - t.watch.won >= 2) {
    const b = s.watch!.blockers[0];
    out.push(`Montre suisse perdue ${t.watch.measured - t.watch.won} soirs${b ? `, surtout à cause de « ${b.name} » (minimum ${fmtMin(b.goalMin)}, en retard ${b.lostDays} soir${b.lostDays > 1 ? "s" : ""})` : ""}.`);
  }
  const good: string[] = [];
  if (t.metronome && t.metronome.measured >= 5 && t.metronome.won >= t.metronome.measured - 1) good.push(`routines tenues ${t.metronome.won} jours sur ${t.metronome.measured}`);
  if (t.cap && t.cap.held >= 3) good.push(`journée posée la veille et tenue ${t.cap.held} fois`);
  if (t.parole && t.parole.given >= 3 && t.parole.held === t.parole.given) good.push(`parole tenue tous les jours où elle a été donnée`);
  if (good.length) out.push(`Bon point : ${good.join(", ")}.`);
  return out.slice(0, 4);
}

/** Pastille « À SURVEILLER » (lot 3) : un signal de fond se dégrade. */
export function watchFlag(s: CoachSignals | null): string | null {
  if (!s) return null;
  const t = signalTiles(s);
  if (t.sleep && t.sleep.nights >= 5 && t.sleep.shortNights >= 5) return "nuits courtes";
  if (t.parole && t.parole.given >= 4 && t.parole.held * 2 < t.parole.given) return "parole fragile";
  return null;
}
