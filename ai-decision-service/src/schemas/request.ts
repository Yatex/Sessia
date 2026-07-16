import { z } from "zod";

import { decisionActionSchema } from "./decision.js";

const nonEmptyStringSchema = z.string().trim().min(1);
const isoDatetimeSchema = z.string().datetime({ offset: true });

const professionalSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  name: nonEmptyStringSchema,
  locale: nonEmptyStringSchema.nullable().optional(),
  time_zone: nonEmptyStringSchema.nullable().optional(),
  payment_instructions: nonEmptyStringSchema.nullable().optional(),
  instructions: nonEmptyStringSchema.nullable().optional()
}).passthrough();

const instructionSchema = z.object({
  key: nonEmptyStringSchema,
  name: nonEmptyStringSchema,
  description: nonEmptyStringSchema,
  trigger_event: nonEmptyStringSchema,
  allowed_actions: z.array(decisionActionSchema).min(1)
}).passthrough();

const clientSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  name: nonEmptyStringSchema,
  email: nonEmptyStringSchema.nullable().optional(),
  phone: nonEmptyStringSchema.nullable().optional(),
  notes: nonEmptyStringSchema.nullable().optional()
}).passthrough();

const sessionSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  title: nonEmptyStringSchema,
  starts_at: isoDatetimeSchema,
  ends_at: isoDatetimeSchema,
  status: nonEmptyStringSchema.nullable().optional(),
  confirmation_status: nonEmptyStringSchema.nullable().optional(),
  payment_status: nonEmptyStringSchema.nullable().optional(),
  payment_link: nonEmptyStringSchema.nullable().optional(),
  due_date: z.string().date().nullable().optional(),
  price_cents: z.number().int().nonnegative().optional(),
  currency: nonEmptyStringSchema.nullable().optional(),
  notes: nonEmptyStringSchema.nullable().optional()
}).passthrough();

const paymentRecordSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  status: nonEmptyStringSchema.nullable().optional(),
  amount_cents: z.number().int().nonnegative().optional(),
  currency: nonEmptyStringSchema.nullable().optional(),
  due_on: z.string().date().nullable().optional(),
  paid_at: isoDatetimeSchema.nullable().optional()
}).passthrough();

const billingContextSchema = z.object({
  current_balance_cents: z.number().int().optional(),
  credit_balance_cents: z.number().int().optional(),
  unpaid_sessions: z.array(z.record(z.unknown())).optional(),
  overdue_charges: z.array(z.record(z.unknown())).optional(),
  next_session_payment_status: nonEmptyStringSchema.nullable().optional(),
  payment_link_for_next_unpaid_session: nonEmptyStringSchema.nullable().optional(),
  last_payment_status: nonEmptyStringSchema.nullable().optional()
}).passthrough();

const availabilityOptionSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  label: nonEmptyStringSchema,
  starts_at: isoDatetimeSchema,
  ends_at: isoDatetimeSchema,
  evidence_id: nonEmptyStringSchema.optional()
}).passthrough();

export const recentMessageSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  direction: z.enum(["inbound", "outbound", "internal_note"]),
  author_role: z.enum(["client", "assistant", "professional", "system"]).optional(),
  channel: nonEmptyStringSchema.optional(),
  subject: nonEmptyStringSchema.nullable().optional(),
  body: nonEmptyStringSchema.max(4000),
  occurred_at: isoDatetimeSchema,
  evidence_id: nonEmptyStringSchema.optional()
}).passthrough();

const evidenceSchema = z.object({
  evidence_id: nonEmptyStringSchema,
  source_type: nonEmptyStringSchema,
  source_id: nonEmptyStringSchema.optional(),
  field: nonEmptyStringSchema,
  value: z.unknown(),
  metadata: z.record(z.unknown()).optional()
}).passthrough();

export const decideRequestSchema = z.object({
  architecture_version: z.enum(["grounded_v1", "grounded_v2"]).optional(),
  context_token: nonEmptyStringSchema.optional(),
  trigger_event: nonEmptyStringSchema,
  professional: professionalSchema,
  instruction: instructionSchema,
  client: clientSchema.nullable().optional(),
  session: sessionSchema.nullable().optional(),
  payment_record: paymentRecordSchema.nullable().optional(),
  billing_context: billingContextSchema.nullable().optional(),
  recent_messages: z.array(recentMessageSchema).max(80).default([]),
  availability_options: z.array(availabilityOptionSchema).max(20).default([]),
  task_context: z.record(z.unknown()).default({}),
  current_time: isoDatetimeSchema,
  timezone: nonEmptyStringSchema,
  tool_results: z.record(z.unknown()).optional(),
  evidence: z.array(evidenceSchema).max(200).optional(),
  required_evidence_citations: z.boolean().optional(),
  safety_rules: z.array(nonEmptyStringSchema).max(20).optional()
  ,allowed_tools: z.array(z.enum(["client_context", "session_context", "conversation_history", "pending_interaction", "professional_settings"])).max(5).optional()
  ,tool_endpoint: z.string().url().optional()
}).strict().superRefine((request, ctx) => {
  if (request.instruction.trigger_event !== request.trigger_event) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["instruction", "trigger_event"],
      message: "instruction.trigger_event must match trigger_event."
    });
  }
  if (request.architecture_version?.startsWith("grounded_") && !request.context_token) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["context_token"], message: "context_token is required for grounded decisions." });
  }
  if (request.architecture_version === "grounded_v2" && (!request.tool_endpoint || !request.allowed_tools?.length)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["tool_endpoint"], message: "tool_endpoint and allowed_tools are required for grounded_v2." });
  }
});

export type DecideRequest = z.infer<typeof decideRequestSchema>;
