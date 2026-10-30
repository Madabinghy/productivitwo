/**
 * Règles des notifications push ORION / coach (2026-10-30). Pures.
 */

/** Titre selon l'expéditeur : un coach signe de son nom, ORION reste ORION. */
export function pushTitleFor(sender: "coach" | "orion" | undefined, characterName?: string): string {
  const name = (characterName ?? "").trim();
  if (sender === "coach") return `🎓 ${name || "Ton coach"}`;
  return `◉ ${name || "ORION"}`;
}

/** Un message daté d'un jour à venir ne part pas tout de suite (il s'affiche le jour venu dans l'app). */
export function shouldPushNow(targetDate: string, todayYmd: string): boolean {
  return targetDate <= todayYmd;
}

/** Interrupteur « Messages ORION / coach » : absent = activé. */
export function pushAllowed(config: Record<string, unknown> | undefined): boolean {
  return config?.pushEnabled !== false;
}

export function todayParis(d: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}
