import type { DecisionProvider, ProviderDecisionInput, ProviderDecisionResult } from "./base-provider.js";

export class MockDecisionProvider implements DecisionProvider {
  async decide(input: ProviderDecisionInput): Promise<ProviderDecisionResult> {
    const latestInbound = [...input.context.recent_messages].reverse().find((message) => message.direction === "inbound");
    const body = latestInbound?.body ?? "your message";

    if (/urgent|complaint|angry|frustrated|emergency|queja|urgente|enoj/i.test(body)) {
      return {
        rawDecision: {
          action: "alert_professional",
          message_body: null,
          note_body: null,
          alert_body: `Client message needs review: ${body}`,
          follow_up_at: null,
          confidence: 0.8,
          reasoning_summary: "Mock provider escalated a sensitive or urgent message."
        },
        metadata: { provider: "mock" }
      };
    }

    return {
      rawDecision: {
        action: "send_message",
        message_body: locale(input) === "es" ? "Gracias por tu mensaje. Lo reviso con la información de tu sesión y te respondo por acá." : "Thanks for your message. I will check it against your session details and reply here.",
        note_body: null,
        alert_body: null,
        follow_up_at: null,
        confidence: 0.6,
        reasoning_summary: "Mock provider returned a generic safe reply."
      },
      metadata: { provider: "mock" }
    };
  }
}

function locale(input: ProviderDecisionInput): string {
  return input.context.professional.locale?.startsWith("es") ? "es" : "en";
}
