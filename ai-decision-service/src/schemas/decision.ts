import { z } from "zod";

export const decisionActionValues = [
  "send_message",
  "mark_session_confirmed",
  "mark_session_maybe",
  "mark_session_declined",
  "mark_payment_reported",
  "reschedule_session",
  "create_client_note",
  "alert_professional",
  "schedule_follow_up",
  "do_nothing"
] as const;

export const decisionActionSchema = z.enum(decisionActionValues);
export type DecisionAction = z.infer<typeof decisionActionSchema>;

const nullableTextSchema = z.string().trim().min(1).max(2000).nullable();

export const decisionSchema = z.object({
  action: decisionActionSchema,
  message_body: nullableTextSchema,
  note_body: nullableTextSchema,
  alert_body: nullableTextSchema,
  follow_up_at: z.string().datetime({ offset: true }).nullable(),
  target_start_at: z.string().datetime({ offset: true }).nullable(),
  confidence: z.number().min(0).max(1),
  reasoning_summary: z.string().trim().min(1).max(280)
}).strict().superRefine((decision, ctx) => {
  if (decision.action === "send_message" && !decision.message_body) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["message_body"], message: "message_body is required when action is send_message." });
  }
  if (decision.action === "create_client_note" && !decision.note_body) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["note_body"], message: "note_body is required when action is create_client_note." });
  }
  if (decision.action === "alert_professional" && !decision.alert_body) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["alert_body"], message: "alert_body is required when action is alert_professional." });
  }
  if (decision.action === "schedule_follow_up" && !decision.follow_up_at) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["follow_up_at"], message: "follow_up_at is required when action is schedule_follow_up." });
  }
  if (decision.action === "reschedule_session" && !decision.target_start_at) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["target_start_at"], message: "target_start_at is required when action is reschedule_session." });
  }
});

export type Decision = z.infer<typeof decisionSchema>;
