import { buildDecisionPrompt } from "../prompts/build-prompt.js";
import type { Decision } from "../schemas/decision.js";
import type { DecideRequest } from "../schemas/request.js";
import type { DecisionProvider } from "../providers/base-provider.js";
import { normalizeReplyText, parseDeterministicReply } from "../reply-parser/deterministic-reply-parser.js";
import { validateDecision } from "./validate-decision.js";

export class DecisionService {
  constructor(private readonly provider: DecisionProvider) {}

  async decide(input: DecideRequest): Promise<Decision> {
    const deterministicDecision = maybeResolveDeterministicAutomation(input) ?? maybeResolveDeterministicReply(input);
    if (deterministicDecision) return deterministicDecision;

    const prompt = buildDecisionPrompt(input);
    const result = await this.provider.decide({ prompt, context: input });
    return validateDecision(result.rawDecision, input);
  }
}

function maybeResolveDeterministicAutomation(input: DecideRequest): Decision | null {
  switch (input.instruction.key) {
    case "confirm_session":
      return sendIfAllowed(input, buildConfirmationMessage(input), "Deterministic confirmation request for an upcoming session.");
    case "send_pre_session_reminder":
      if (input.session?.confirmation_status !== "confirmed") return doNothing(input, "Pre-session reminders only apply to confirmed sessions.");
      return sendIfAllowed(input, buildReminderMessage(input), "Deterministic reminder for a confirmed upcoming session.");
    case "follow_up_no_response":
      return sendIfAllowed(input, buildNoResponseFollowUp(input), "Deterministic no-response follow-up for pending confirmation.");
    case "ask_feedback_after_session":
      return sendIfAllowed(input, buildFeedbackMessage(input), "Deterministic feedback request after a session.");
    case "payment_reminder":
      if (!["pending", "overdue"].includes(input.session?.payment_status ?? "")) return doNothing(input, "Payment is not pending or overdue.");
      return sendIfAllowed(input, buildPaymentReminder(input), "Deterministic payment reminder for an unpaid session.");
    case "blocked_time_rebooking":
      return sendIfAllowed(input, buildBlockedTimeRebooking(input), "Deterministic rebooking options for a blocked session.");
    default:
      return null;
  }
}

function maybeResolveDeterministicReply(input: DecideRequest): Decision | null {
  const latestInbound = latestInboundMessage(input);
  if (!latestInbound) return null;

  const body = latestInbound.body;
  const normalized = normalizeReplyText(body);

  const chosenSlot = maybeChosenAvailabilityOption(input, normalized);
  if (chosenSlot) return reschedule(input, chosenSlot.starts_at, "Client selected an available rescheduling option.");

  const rescheduleDecision = maybeHandleRescheduleRequest(input, normalized);
  if (rescheduleDecision) return rescheduleDecision;

  const basicQuestionDecision = maybeAnswerBasicQuestion(input, normalized);
  if (basicQuestionDecision) return basicQuestionDecision;

  switch (parseDeterministicReply(body)) {
    case "confirmed":
      return stateUpdate(input, "mark_session_confirmed", "Client clearly confirmed the session.");
    case "maybe":
      return stateUpdate(input, "mark_session_maybe", "Client gave a maybe response.");
    case "declined":
      return stateUpdate(input, "mark_session_declined", "Client clearly declined the session.");
    case "payment_reported":
      return stateUpdate(input, "mark_payment_reported", "Client clearly reported payment.");
    default:
      return null;
  }
}

function maybeAnswerBasicQuestion(input: DecideRequest, normalizedBody: string): Decision | null {
  if (!input.instruction.allowed_actions.includes("send_message")) return null;

  if (/(what time|when|hour|hora|cuando|cu[aá]ndo)/i.test(normalizedBody) && input.session) {
    return sendIfAllowed(input, localize(input, {
      en: `Your ${input.session.title} is scheduled for ${formatSessionTime(input)}.`,
      es: `Tu ${input.session.title} esta agendada para ${formatSessionTime(input)}.`
    }), "Answered session time from Sessia context.");
  }

  if (/(price|cost|pay|payment|precio|costo|pago|pagar)/i.test(normalizedBody) && input.session) {
    const amount = formatMoney(input.session.price_cents ?? 0, input.session.currency ?? "USD");
    const status = input.session.payment_status ?? "not tracked";
    return sendIfAllowed(input, localize(input, {
      en: `The session price is ${amount}. Payment status: ${status.replaceAll("_", " ")}.`,
      es: `El precio de la sesion es ${amount}. Estado de pago: ${status.replaceAll("_", " ")}.`
    }), "Answered payment question from Sessia context.");
  }

  if (/(am i confirmed|confirmed|confirmado|confirmada|estoy confirmado|estoy confirmada)/i.test(normalizedBody) && input.session) {
    return sendIfAllowed(input, localize(input, {
      en: `Your confirmation status is ${input.session.confirmation_status?.replaceAll("_", " ") ?? "not requested"}.`,
      es: `Tu estado de confirmacion es ${input.session.confirmation_status?.replaceAll("_", " ") ?? "sin solicitar"}.`
    }), "Answered confirmation-status question from Sessia context.");
  }

  return null;
}

function maybeHandleRescheduleRequest(input: DecideRequest, normalizedBody: string): Decision | null {
  if (!/(change|reschedule|move|another time|other time|cancel|cambiar|reagendar|mover|otro horario|otra hora|cancelar)/i.test(normalizedBody)) return null;
  if (input.availability_options.length > 0) {
    return sendIfAllowed(input, buildAvailabilityOptionsMessage(input), "Offered available slots for a rescheduling request.");
  }

  return alert(input, `Client may need a schedule change: ${latestInboundMessage(input)?.body}`, "Schedule-change request needs professional review because no availability options were present.");
}

function maybeChosenAvailabilityOption(input: DecideRequest, normalizedBody: string): DecideRequest["availability_options"][number] | null {
  if (!input.instruction.allowed_actions.includes("reschedule_session")) return null;
  if (input.availability_options.length === 0) return null;

  const optionIndex = parseOptionIndex(normalizedBody);
  if (optionIndex === null) return null;

  return input.availability_options[optionIndex] ?? null;
}

function parseOptionIndex(value: string): number | null {
  const directNumber = value.match(/(?:opcion|option)?\s*(\d+)/i)?.[1];
  if (directNumber) {
    const index = Number(directNumber) - 1;
    return Number.isInteger(index) && index >= 0 ? index : null;
  }

  const wordMap: Record<string, number> = {
    first: 0,
    primera: 0,
    primero: 0,
    second: 1,
    segunda: 1,
    segundo: 1,
    third: 2,
    tercera: 2,
    tercero: 2,
    fourth: 3,
    cuarta: 3,
    cuarto: 3,
    fifth: 4,
    quinta: 4,
    quinto: 4
  };

  return wordMap[value] ?? null;
}

function sendIfAllowed(input: DecideRequest, messageBody: string | null, reasoningSummary: string): Decision | null {
  if (!messageBody || !input.instruction.allowed_actions.includes("send_message")) return null;

  return validateDecision({
    action: "send_message",
    message_body: messageBody,
    note_body: null,
    alert_body: null,
    follow_up_at: null,
    target_start_at: null,
    confidence: 0.98,
    reasoning_summary: reasoningSummary
  }, input);
}

function stateUpdate(input: DecideRequest, action: Decision["action"], reasoningSummary: string): Decision | null {
  if (!input.instruction.allowed_actions.includes(action)) return null;

  return validateDecision({
    action,
    message_body: null,
    note_body: null,
    alert_body: null,
    follow_up_at: null,
    target_start_at: null,
    confidence: 0.99,
    reasoning_summary: reasoningSummary
  }, input);
}

function reschedule(input: DecideRequest, targetStartAt: string, reasoningSummary: string): Decision | null {
  if (!input.instruction.allowed_actions.includes("reschedule_session")) return null;

  return validateDecision({
    action: "reschedule_session",
    message_body: null,
    note_body: null,
    alert_body: null,
    follow_up_at: null,
    target_start_at: targetStartAt,
    confidence: 0.96,
    reasoning_summary: reasoningSummary
  }, input);
}

function alert(input: DecideRequest, body: string, reasoningSummary: string): Decision | null {
  if (!input.instruction.allowed_actions.includes("alert_professional")) return null;

  return validateDecision({
    action: "alert_professional",
    message_body: null,
    note_body: null,
    alert_body: body,
    follow_up_at: null,
    target_start_at: null,
    confidence: 0.96,
    reasoning_summary: reasoningSummary
  }, input);
}

function doNothing(input: DecideRequest, reasoningSummary: string): Decision | null {
  if (!input.instruction.allowed_actions.includes("do_nothing")) return null;

  return validateDecision({
    action: "do_nothing",
    message_body: null,
    note_body: null,
    alert_body: null,
    follow_up_at: null,
    target_start_at: null,
    confidence: 0.9,
    reasoning_summary: reasoningSummary
  }, input);
}

function buildConfirmationMessage(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  return localize(input, {
    en: `Hi ${preferredClientName(input)}, can you confirm your ${input.session.title} on ${formatSessionTime(input)}?`,
    es: `Hola ${preferredClientName(input)}, me confirmas tu ${input.session.title} el ${formatSessionTime(input)}?`
  });
}

function buildReminderMessage(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  return localize(input, {
    en: `Hi ${preferredClientName(input)}, quick reminder for your ${input.session.title} at ${formatSessionTime(input)}.`,
    es: `Hola ${preferredClientName(input)}, te recuerdo tu ${input.session.title} a las ${formatSessionTime(input)}.`
  });
}

function buildNoResponseFollowUp(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  return localize(input, {
    en: `Quick follow-up, ${preferredClientName(input)}: should we keep your ${input.session.title} on ${formatSessionTime(input)}?`,
    es: `Te escribo rapido, ${preferredClientName(input)}: mantenemos tu ${input.session.title} el ${formatSessionTime(input)}?`
  });
}

function buildFeedbackMessage(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  return localize(input, {
    en: `Thanks for today's ${input.session.title}. How did the session feel for you?`,
    es: `Gracias por la sesion de hoy. Como te sentiste con ${input.session.title}?`
  });
}

function buildPaymentReminder(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  const amount = formatMoney(input.session.price_cents ?? 0, input.session.currency ?? "USD");
  return localize(input, {
    en: `Hi ${preferredClientName(input)}, friendly reminder that ${input.session.title} has a pending payment of ${amount}.`,
    es: `Hola ${preferredClientName(input)}, te recuerdo que ${input.session.title} tiene pendiente el pago de ${amount}.`
  });
}

function buildBlockedTimeRebooking(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  if (input.availability_options.length === 0) {
    return localize(input, {
      en: `Hi ${preferredClientName(input)}, ${input.session.title} needs to be moved because the professional is unavailable at the original time. I will ask them to send options soon.`,
      es: `Hola ${preferredClientName(input)}, tenemos que mover ${input.session.title} porque el profesional no esta disponible en el horario original. Le voy a pedir que te envie opciones pronto.`
    });
  }

  return buildAvailabilityOptionsMessage(input);
}

function buildAvailabilityOptionsMessage(input: DecideRequest): string | null {
  if (!input.client || !input.session) return null;

  const options = formatSlotOptions(input);
  return localize(input, {
    en: `Hi ${preferredClientName(input)}, we can move your ${input.session.title}. These slots are free:\n${options}\nReply with the option number you prefer.`,
    es: `Hola ${preferredClientName(input)}, podemos mover tu ${input.session.title}. Estos horarios estan libres:\n${options}\nRespondeme con el numero de la opcion que prefieras.`
  });
}

function formatSlotOptions(input: DecideRequest): string {
  return input.availability_options.slice(0, 5).map((slot, index) => {
    const starts = new Date(slot.starts_at);
    const formatted = new Intl.DateTimeFormat(input.professional.locale?.startsWith("es") ? "es-UY" : "en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: input.timezone
    }).format(starts);
    return `${index + 1}. ${formatted}`;
  }).join("\n");
}

function latestInboundMessage(input: DecideRequest): DecideRequest["recent_messages"][number] | undefined {
  return [...input.recent_messages].reverse().find((message) => message.direction === "inbound");
}

function preferredClientName(input: DecideRequest): string {
  return input.client?.name?.split(" ")[0] ?? "there";
}

function localize(input: DecideRequest, options: { en: string; es: string }): string {
  return input.professional.locale?.startsWith("es") ? options.es : options.en;
}

function formatSessionTime(input: DecideRequest): string {
  if (!input.session) return "";
  const starts = new Date(input.session.starts_at);
  return new Intl.DateTimeFormat(input.professional.locale?.startsWith("es") ? "es-UY" : "en-US", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: input.timezone
  }).format(starts);
}

function formatMoney(cents: number, currency: string): string {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}
