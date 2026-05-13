import assert from "node:assert/strict";
import test from "node:test";

import { DecisionService } from "../src/services/decision-service.js";
import { MockDecisionProvider } from "../src/providers/mock-provider.js";
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

test("marks a clear payment reply", async () => {
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

  assert.equal(decision.action, "mark_payment_reported");
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
  assert.match(decision.message_body ?? "", /sessia\.demo/i);
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
