/**
 * Historique des veilles (lot « Pause, record et reprise », 2026-10-30) :
 * `data/meta.restPeriods` = [{domainId, from, to}] (jours inclus). Gèle les séries de routine
 * des domaines en veille, jours passés compris. Jamais rétroactive.
 * Logique alignée avec `lib/utils/rest_periods.dart` (garder alignés).
 */
export interface RestPeriod {
  domainId: string;
  from: string;
  to: string;
}

export const REST_PERIODS_KEPT = 60;
const YMD = /^\d{4}-\d{2}-\d{2}$/;

function shift(ymd: string, days: number): string {
  const d = new Date(`${ymd}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

const covers = (p: RestPeriod, ymd: string) => p.from <= ymd && p.to >= ymd;

export function parseRestPeriods(raw: unknown): RestPeriod[] {
  if (!Array.isArray(raw)) return [];
  const out: RestPeriod[] = [];
  for (const x of raw) {
    if (!x || typeof x !== "object") continue;
    const { domainId, from, to } = x as Record<string, unknown>;
    if (typeof domainId !== "string" || typeof from !== "string" || typeof to !== "string") continue;
    if (!YMD.test(from) || !YMD.test(to) || to < from) continue;
    out.push({ domainId, from, to });
  }
  return out;
}

const capped = (l: RestPeriod[]) => (l.length > REST_PERIODS_KEPT ? l.slice(l.length - REST_PERIODS_KEPT) : l);

/** Met le domaine en veille d'aujourd'hui à `until` : prolonge la période en cours, sinon en ouvre une. */
export function withRestSet(periods: RestPeriod[], domainId: string, todayYmd: string, untilYmd: string): RestPeriod[] {
  if (untilYmd < todayYmd) return periods;
  let found = false;
  const next = periods.map((p) => {
    if (!found && p.domainId === domainId && covers(p, todayYmd)) {
      found = true;
      return { domainId, from: p.from, to: untilYmd };
    }
    return p;
  });
  if (!found) next.push({ domainId, from: todayYmd, to: untilYmd });
  return capped(next);
}

/** Lève la veille aujourd'hui : la période en cours s'arrête hier, ou disparaît si elle commençait aujourd'hui. */
export function withRestLifted(periods: RestPeriod[], domainId: string, todayYmd: string): RestPeriod[] {
  const yesterday = shift(todayYmd, -1);
  const out: RestPeriod[] = [];
  for (const p of periods) {
    if (p.domainId === domainId && covers(p, todayYmd)) {
      if (p.from <= yesterday) out.push({ domainId, from: p.from, to: yesterday });
    } else {
      out.push(p);
    }
  }
  return out;
}
