import assert from "node:assert/strict";
import test from "node:test";

import { DecisionService } from "../src/services/decision-service.js";
import { MockDecisionProvider } from "../src/providers/mock-provider.js";
import type { DecisionProvider, ProviderDecisionInput, ProviderDecisionResult } from "../src/providers/base-provider.js";
import { buildRequest } from "./support/build-request.js";

test("marks a clear confirmation reply without provider ambiguity", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest());

  assert.equal(decision.action, "mark_session_confirmed");
});

test("does not treat bare acknowledgements as confirmations without confirmation context", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    recent_messages: [
      {
        direction: "outbound",
        author_role: "assistant",
        channel: "whatsapp",
        body: "Here are the payment instructions.",
        occurred_at: "2026-05-05T11:55:00-03:00"
      },
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "dale",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "send_message");
});

test("answers a clear payment reply without mutating payment state", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    recent_messages: [
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "ya pague",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "send_message");
  assert.match(decision.message_body ?? "", /no veo|do not see/i);
});

test("answers how to pay from professional payment instructions", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    recent_messages: [
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "Como pago?",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "send_message");
  assert.match(decision.message_body ?? "", /mercadopago|link de pago|payment link/i);
});

test("escalates how to pay when payment instructions are missing", async () => {
  const baseRequest = buildRequest();
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    professional: {
      ...baseRequest.professional,
      payment_instructions: null
    },
    recent_messages: [
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "Por donde pago?",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "alert_professional");
});

test("answers a basic time question from session context", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    recent_messages: [
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "What time is my session?",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "send_message");
  assert.match(decision.message_body ?? "", /Therapy session/);
});

test("offers free slots when a client asks to reschedule", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    recent_messages: [
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "Can we move my session?",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "send_message");
  assert.match(decision.message_body ?? "", /1\./);
});

test("reschedules when the client chooses an option", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    recent_messages: [
      {
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "option 2",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ]
  }));

  assert.equal(decision.action, "reschedule_session");
  assert.equal(decision.target_start_at, "2026-05-07T15:00:00-03:00");
});

test("builds deterministic confirmation messages", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    trigger_event: "before_session",
    instruction: {
      key: "confirm_session",
      name: "Confirm upcoming session",
      description: "Ask the client to confirm.",
      trigger_event: "before_session",
      allowed_actions: ["send_message", "do_nothing"]
    },
    recent_messages: []
  }));

  assert.equal(decision.action, "send_message");
  assert.match(decision.message_body ?? "", /confirm/);
});

test("offers rebooking options for blocked sessions", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    trigger_event: "schedule_blocked",
    instruction: {
      key: "blocked_time_rebooking",
      name: "Rebook blocked session",
      description: "Offer new options.",
      trigger_event: "schedule_blocked",
      allowed_actions: ["send_message", "do_nothing"]
    },
    recent_messages: []
  }));

  assert.equal(decision.action, "send_message");
  assert.match(decision.message_body ?? "", /free|libres/i);
});

test("grounded decisions cite scoped message and session evidence", async () => {
  const decision = await new DecisionService(new MockDecisionProvider()).decide(buildRequest({
    architecture_version: "grounded_v1",
    context_token: "signed-context-token",
    trigger_event: "incoming_message",
    instruction: {
      key: "answer_client_reply",
      name: "Answer client reply",
      description: "Interpret an inbound client reply.",
      trigger_event: "incoming_message",
      allowed_actions: ["mark_session_confirmed", "send_message", "do_nothing"]
    },
    recent_messages: [
      {
        id: "message_0",
        direction: "outbound",
        author_role: "assistant",
        channel: "whatsapp",
        body: "Can you confirm your session?",
        occurred_at: "2026-05-05T11:55:00-03:00",
        evidence_id: "message.40.body"
      },
      {
        id: "message_1",
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "yes",
        occurred_at: "2026-05-05T12:00:00-03:00",
        evidence_id: "message.41.body"
      }
    ],
    evidence: [
      { evidence_id: "message.41.body", source_type: "message", source_id: "41", field: "body", value: "yes" },
      { evidence_id: "session.12.confirmation_status", source_type: "session", source_id: "12", field: "confirmation_status", value: "pending" }
    ],
    required_evidence_citations: true
  }));

  assert.equal(decision.action, "mark_session_confirmed");
  assert.deepEqual(decision.evidence_ids, ["message.41.body", "session.12.confirmation_status"]);
});

test("grounded_v2 sends semantic replies to the provider instead of regex classification", async () => {
  class RecordingProvider implements DecisionProvider {
    calls = 0;
    async decide(_input: ProviderDecisionInput): Promise<ProviderDecisionResult> {
      this.calls += 1;
      return { rawDecision: { action: "send_message", message_body: "Could you clarify?", confidence: 0.75, reasoning_summary: "The short reply is ambiguous." }, metadata: { provider: "test" } };
    }
  }
  const provider = new RecordingProvider();
  const base = buildRequest();
  const input = buildRequest({
    architecture_version: "grounded_v2",
    context_token: "signed-context",
    tool_endpoint: "https://sessia.org/internal/ai/tools/__TOOL__",
    allowed_tools: ["pending_interaction", "conversation_history"],
    recent_messages: [{ direction: "inbound", author_role: "client", body: "dale", occurred_at: base.current_time }]
  });

  const decision = await new DecisionService(provider).decide(input);
  assert.equal(provider.calls, 1);
  assert.equal(decision.action, "send_message");
});

test("grounded_v2 delegates confirmation and rescheduling language to the provider", async () => {
  const replies = [
    "sí",
    "dale",
    "creo que sí",
    "después te confirmo",
    "no puedo",
    "no puedo, ¿puedo ir otro día?",
    "¿a qué hora es mi sesión?"
  ];

  class RecordingProvider implements DecisionProvider {
    bodies: string[] = [];

    async decide(input: ProviderDecisionInput): Promise<ProviderDecisionResult> {
      const latest = input.context.recent_messages.at(-1)?.body ?? "";
      this.bodies.push(latest);
      return {
        rawDecision: {
          action: "send_message",
          message_body: "Respuesta basada en contexto.",
          confidence: 0.8,
          reasoning_summary: "The provider interpreted the reply."
        },
        metadata: { provider: "test" }
      };
    }
  }

  const provider = new RecordingProvider();
  const service = new DecisionService(provider);
  const base = buildRequest();

  for (const body of replies) {
    await service.decide(buildRequest({
      architecture_version: "grounded_v2",
      context_token: "signed-context",
      tool_endpoint: "https://sessia.org/internal/ai/tools/__TOOL__",
      allowed_tools: ["pending_interaction", "conversation_history", "session_context"],
      recent_messages: [{ direction: "inbound", author_role: "client", body, occurred_at: base.current_time }]
    }));
  }

  assert.deepEqual(provider.bodies, replies);
});
