export type ReplyClassification = "confirmed" | "maybe" | "declined" | "payment_reported" | "ambiguous";

interface ReplySignal {
  label: string;
  pattern: RegExp;
}

const CONFIRMED_SIGNALS: ReplySignal[] = [
  { label: "confirmed", pattern: /\bconfirmed\b/ },
  { label: "confirmo", pattern: /\bconfirmo\b/ },
  { label: "i confirm", pattern: /\bi confirm\b/ },
  { label: "voy", pattern: /\bvoy\b/ },
  { label: "estare", pattern: /\bestare\b/ },
  { label: "i will attend", pattern: /\bi will attend\b/ },
  { label: "i'll be there", pattern: /\bi ll be there\b/ }
];

const CONTEXTUAL_CONFIRMATION_SIGNALS: ReplySignal[] = [
  { label: "yes", pattern: /\byes\b/ },
  { label: "si", pattern: /\bsi\b/ },
  { label: "ok", pattern: /\bok\b/ },
  { label: "dale", pattern: /\bdale\b/ },
  { label: "perfecto", pattern: /\bperfecto\b/ },
  { label: "sure", pattern: /\bsure\b/ }
];

const MAYBE_SIGNALS: ReplySignal[] = [
  { label: "maybe", pattern: /\bmaybe\b/ },
  { label: "not sure", pattern: /\bnot sure\b/ },
  { label: "quizas", pattern: /\bquizas\b/ },
  { label: "capaz", pattern: /\bcapaz\b/ },
  { label: "puede ser", pattern: /\bpuede ser\b/ },
  { label: "te aviso", pattern: /\bte aviso\b/ },
  { label: "no se si", pattern: /\bno se si\b/ },
  { label: "no creo", pattern: /\bno creo\b/ }
];

const DECLINED_SIGNALS: ReplySignal[] = [
  { label: "no puedo", pattern: /\bno puedo\b/ },
  { label: "no voy", pattern: /\bno voy\b/ },
  { label: "can't", pattern: /\bcan t\b/ },
  { label: "cant", pattern: /\bcant\b/ },
  { label: "cannot", pattern: /\bcannot\b/ },
  { label: "cancel", pattern: /\bcancel\b/ },
  { label: "cancelo", pattern: /\bcancelo\b/ },
  { label: "decline", pattern: /\bdecline\b/ },
  { label: "not attending", pattern: /\bnot attending\b/ }
];

const PAYMENT_REPORTED_SIGNALS: ReplySignal[] = [
  { label: "paid", pattern: /\bpaid\b/ },
  { label: "i paid", pattern: /\bi paid\b/ },
  { label: "payment sent", pattern: /\bpayment sent\b/ },
  { label: "transfer sent", pattern: /\btransfer sent\b/ },
  { label: "ya pague", pattern: /\bya pague\b/ },
  { label: "te pague", pattern: /\bte pague\b/ },
  { label: "transferi", pattern: /\btransferi\b/ },
  { label: "pago enviado", pattern: /\bpago enviado\b/ }
];

const AMBIGUOUS_SIGNALS: ReplySignal[] = [
  { label: "pero", pattern: /\bpero\b/ },
  { label: "late", pattern: /\blate\b/ },
  { label: "tarde", pattern: /\btarde\b/ },
  { label: "change", pattern: /\bchange\b/ },
  { label: "reschedule", pattern: /\breschedule\b/ },
  { label: "move", pattern: /\bmove\b/ },
  { label: "cambiar", pattern: /\bcambiar\b/ },
  { label: "reagendar", pattern: /\breagendar\b/ },
  { label: "mover", pattern: /\bmover\b/ },
  { label: "no se", pattern: /\bno se\b/ }
];

export function normalizeReplyText(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function parseDeterministicReply(value: string): ReplyClassification {
  const normalized = normalizeReplyText(value);
  if (!normalized) return "ambiguous";

  const matches = {
    confirmed: collectMatches(normalized, CONFIRMED_SIGNALS),
    maybe: collectMatches(normalized, MAYBE_SIGNALS),
    declined: collectMatches(normalized, DECLINED_SIGNALS),
    payment_reported: collectMatches(normalized, PAYMENT_REPORTED_SIGNALS),
    ambiguous: collectMatches(normalized, AMBIGUOUS_SIGNALS)
  };

  if (/[?¿]/.test(value)) {
    matches.ambiguous.push("question");
  }

  if (matches.maybe.length > 0) {
    matches.ambiguous = matches.ambiguous.filter((match) => match !== "no se");
  }

  const categoriesWithMatches = [
    matches.confirmed.length > 0 ? "confirmed" : null,
    matches.maybe.length > 0 ? "maybe" : null,
    matches.declined.length > 0 ? "declined" : null,
    matches.payment_reported.length > 0 ? "payment_reported" : null
  ].filter(Boolean) as ReplyClassification[];

  if (matches.ambiguous.length > 0 || categoriesWithMatches.length !== 1) {
    return "ambiguous";
  }

  return categoriesWithMatches[0] ?? "ambiguous";
}

export function parseContextualConfirmationReply(value: string): Exclude<ReplyClassification, "payment_reported"> {
  const normalized = normalizeReplyText(value);
  if (!normalized) return "ambiguous";

  if (collectMatches(normalized, MAYBE_SIGNALS).length > 0) return "maybe";
  if (collectMatches(normalized, DECLINED_SIGNALS).length > 0 || normalized === "no") return "declined";
  if (collectMatches(normalized, CONFIRMED_SIGNALS).length > 0) return "confirmed";

  const contextualMatches = collectMatches(normalized, CONTEXTUAL_CONFIRMATION_SIGNALS);
  if (contextualMatches.length > 0 && normalized.split(" ").length <= 3) return "confirmed";

  return "ambiguous";
}

function collectMatches(text: string, signals: ReplySignal[]): string[] {
  return signals
    .filter((signal) => signal.pattern.test(text))
    .map((signal) => signal.label);
}
