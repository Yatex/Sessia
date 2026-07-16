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
    reasoning_summary: parsed.data.reasoning_summary.trim(),
    evidence_ids: parsed.data.evidence_ids.length > 0 ? parsed.data.evidence_ids : evidenceForDecision(parsed.data, request),
    human_review_required: parsed.data.human_review_required
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
    evidence_ids: [],
    human_review_required: false,
    ...decision
  };
}

function evidenceForDecision(decision: Decision, request: DecideRequest): string[] {
  if (request.architecture_version !== "grounded_v1") return [];

  const ids: string[] = [];
  const latestInbound = [...request.recent_messages].reverse().find((message) => message.direction === "inbound");
  if (latestInbound?.evidence_id) ids.push(latestInbound.evidence_id);

  if (["mark_session_confirmed", "mark_session_maybe", "mark_session_declined"].includes(decision.action)) {
    const confirmationEvidence = request.evidence?.find((item) => item.source_type === "session" && item.field === "confirmation_status");
    if (confirmationEvidence) ids.push(confirmationEvidence.evidence_id);
  }

  if (decision.action === "reschedule_session" && decision.target_start_at) {
    const slot = request.availability_options.find((option) => option.starts_at === decision.target_start_at);
    if (slot?.evidence_id) ids.push(slot.evidence_id);
  }

  if (decision.action === "send_message" && ids.length === 0) {
    const sessionEvidence = request.evidence?.find((item) => item.source_type === "session");
    if (sessionEvidence) ids.push(sessionEvidence.evidence_id);
  }

  return [...new Set(ids)];
}
