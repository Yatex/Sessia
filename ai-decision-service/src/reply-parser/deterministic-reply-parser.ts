export type ReplyClassification = "confirmed" | "maybe" | "declined" | "payment_reported" | "unknown";

const CONFIRMED = [
  "yes", "yep", "sure", "confirmed", "confirm", "i confirm", "i will", "i'll be there",
  "si", "sí", "voy", "confirmo", "dale", "ok", "perfecto", "ahi estare", "ahí estaré"
];
const MAYBE = ["maybe", "not sure", "quizas", "quizás", "capaz", "puede ser", "te aviso"];
const DECLINED = ["no", "can't", "cant", "cannot", "no puedo", "no voy", "cancel", "cancelo", "decline"];
const PAYMENT = ["paid", "i paid", "payment sent", "transfer sent", "ya pague", "ya pagué", "transferi", "transferí", "pago enviado"];

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
  if (!normalized) return "unknown";

  if (matchesAny(normalized, PAYMENT.map(normalizeReplyText))) return "payment_reported";
  if (matchesAny(normalized, CONFIRMED.map(normalizeReplyText))) return "confirmed";
  if (matchesAny(normalized, DECLINED.map(normalizeReplyText))) return "declined";
  if (matchesAny(normalized, MAYBE.map(normalizeReplyText))) return "maybe";

  return "unknown";
}

function matchesAny(value: string, candidates: string[]): boolean {
  return candidates.some((candidate) => value === candidate || value.includes(candidate));
}
