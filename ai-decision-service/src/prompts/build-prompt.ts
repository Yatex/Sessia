import type { DecideRequest } from "../schemas/request.js";
import { SYSTEM_PROMPT } from "./system-prompt.js";

export interface DecisionPrompt {
  system: string;
  prompt: string;
}

export function buildDecisionPrompt(request: DecideRequest): DecisionPrompt {
  return {
    system: SYSTEM_PROMPT,
    prompt: [
      "Evaluate the active Sessia instruction and return one decision.",
      "",
      "Instruction:",
      JSON.stringify(request.instruction, null, 2),
      "",
      "Sessia context:",
      JSON.stringify({
        trigger_event: request.trigger_event,
        professional: request.professional,
        client: request.client,
        session: request.session,
        payment_record: request.payment_record,
        billing_context: request.billing_context,
        availability_options: request.availability_options,
        task_context: request.task_context,
        recent_messages: request.recent_messages,
        current_time: request.current_time,
        timezone: request.timezone
      }, null, 2),
      "",
      "Decision guidance:",
      "- For clear confirmations, declines, or maybe replies, choose the matching confirmation action when allowed.",
      "- Never mark payments paid, forgiven, discounted, or manually recorded. Payments are read-only for AI; answer from billing_context or alert the professional.",
      "- For simple questions about session time, price, confirmation, or payment, answer only from context.",
      "- For rescheduling requests, offer availability_options first; when the client clearly chooses one, choose reschedule_session with that target_start_at when allowed.",
      "- For clinical/personal/sensitive matters, complaints, or missing facts, alert the professional.",
      "- If nothing useful or safe should happen, choose do_nothing."
    ].join("\n")
  };
}
