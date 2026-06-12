import type { DecideRequest } from "../../src/schemas/request.js";

export function buildRequest(overrides: Partial<DecideRequest> = {}): DecideRequest {
  const base: DecideRequest = {
    trigger_event: "client_replied",
    professional: {
      id: "user_1",
      name: "Demo Professional",
      locale: "en",
      time_zone: "America/Montevideo",
      payment_instructions: "Bank transfer to Sessia Pro alias sessia.demo",
      instructions: "Keep messages concise."
    },
    instruction: {
      key: "answer_client_reply",
      name: "Answer client reply",
      description: "Interpret replies and answer safe session questions.",
      trigger_event: "client_replied",
      allowed_actions: [
        "send_message",
        "mark_session_confirmed",
        "mark_session_maybe",
        "mark_session_declined",
        "reschedule_session",
        "create_client_note",
        "alert_professional",
        "do_nothing"
      ]
    },
    client: {
      id: "client_1",
      name: "Ana Martinez",
      phone: "+598 99 111 222"
    },
    session: {
      id: "session_1",
      title: "Therapy session",
      starts_at: "2026-05-05T15:00:00-03:00",
      ends_at: "2026-05-05T15:50:00-03:00",
      status: "scheduled",
      confirmation_status: "pending",
      payment_status: "pending",
      payment_link: "https://www.mercadopago.com/test-session",
      price_cents: 8500,
      currency: "USD"
    },
    payment_record: null,
    billing_context: {
      current_balance_cents: 8500,
      credit_balance_cents: 0,
      unpaid_sessions: [],
      overdue_charges: [],
      next_session_payment_status: "pending",
      payment_link_for_next_unpaid_session: "https://www.mercadopago.com/test-session",
      last_payment_status: null
    },
    availability_options: [
      {
        id: "1",
        label: "Tue May 6, 10:00 - 10:50",
        starts_at: "2026-05-06T10:00:00-03:00",
        ends_at: "2026-05-06T10:50:00-03:00"
      },
      {
        id: "2",
        label: "Wed May 7, 15:00 - 15:50",
        starts_at: "2026-05-07T15:00:00-03:00",
        ends_at: "2026-05-07T15:50:00-03:00"
      }
    ],
    task_context: {},
    recent_messages: [
      {
        id: "message_0",
        direction: "outbound",
        author_role: "assistant",
        channel: "whatsapp",
        body: "Hi Ana, can you confirm your Therapy session?",
        occurred_at: "2026-05-05T11:55:00-03:00"
      },
      {
        id: "message_1",
        direction: "inbound",
        author_role: "client",
        channel: "whatsapp",
        body: "yes",
        occurred_at: "2026-05-05T12:00:00-03:00"
      }
    ],
    current_time: "2026-05-05T12:00:00-03:00",
    timezone: "America/Montevideo"
  };

  const client = overrides.client === null
    ? null
    : ({ ...base.client!, ...(overrides.client ?? {}) } as NonNullable<DecideRequest["client"]>);
  const session = overrides.session === null
    ? null
    : ({ ...base.session!, ...(overrides.session ?? {}) } as NonNullable<DecideRequest["session"]>);

  return {
    ...base,
    ...overrides,
    professional: { ...base.professional, ...overrides.professional },
    instruction: { ...base.instruction, ...overrides.instruction },
    client,
    session
  };
}
