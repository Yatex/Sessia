import { z } from "zod";

import { decisionSchema, type Decision } from "../schemas/decision.js";
import type { DecideRequest } from "../schemas/request.js";

const STATE_UPDATE_ACTIONS = [
  "mark_session_confirmed",
  "mark_session_maybe",
  "mark_session_declined"
];

export function validateDecision(decision: unknown, request: DecideRequest): Decision {
  const parsed = decisionSchema.safeParse(normalizeDecision(decision));
  if (!parsed.success) {
    throw new z.ZodError(parsed.error.issues);
  }

  if (!request.instruction.allowed_actions.includes(parsed.data.action)) {
    throw new Error(`Action ${parsed.data.action} is not allowed for instruction ${request.instruction.key}.`);
  }

  if (STATE_UPDATE_ACTIONS.includes(parsed.data.action)) {
    parsed.data.message_body = null;
    parsed.data.note_body = null;
    parsed.data.alert_body = null;
    parsed.data.follow_up_at = null;
    parsed.data.target_start_at = null;
  }

  return {
    action: parsed.data.action,
    message_body: parsed.data.message_body ?? null,
    note_body: parsed.data.note_body ?? null,
    alert_body: parsed.data.alert_body ?? null,
    follow_up_at: parsed.data.follow_up_at ?? null,
    target_start_at: parsed.data.target_start_at ?? null,
    confidence: Number(parsed.data.confidence.toFixed(3)),
    reasoning_summary: parsed.data.reasoning_summary.trim()
  };
}

function normalizeDecision(decision: unknown): unknown {
  if (!decision || typeof decision !== "object" || Array.isArray(decision)) return decision;

  return {
    message_body: null,
    note_body: null,
    alert_body: null,
    follow_up_at: null,
    target_start_at: null,
    confidence: 0.5,
    reasoning_summary: "No reasoning summary supplied.",
    ...decision
  };
}
