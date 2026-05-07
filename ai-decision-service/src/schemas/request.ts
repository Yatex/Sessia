import { z } from "zod";

import { decisionActionSchema } from "./decision.js";

const nonEmptyStringSchema = z.string().trim().min(1);
const isoDatetimeSchema = z.string().datetime({ offset: true });

const professionalSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  name: nonEmptyStringSchema,
  locale: nonEmptyStringSchema.nullable().optional(),
  time_zone: nonEmptyStringSchema.nullable().optional(),
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

const availabilityOptionSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  label: nonEmptyStringSchema,
  starts_at: isoDatetimeSchema,
  ends_at: isoDatetimeSchema
}).passthrough();

export const recentMessageSchema = z.object({
  id: nonEmptyStringSchema.optional(),
  direction: z.enum(["inbound", "outbound", "internal_note"]),
  author_role: z.enum(["client", "assistant", "professional", "system"]).optional(),
  channel: nonEmptyStringSchema.optional(),
  subject: nonEmptyStringSchema.nullable().optional(),
  body: nonEmptyStringSchema.max(4000),
  occurred_at: isoDatetimeSchema
}).passthrough();

export const decideRequestSchema = z.object({
  trigger_event: nonEmptyStringSchema,
  professional: professionalSchema,
  instruction: instructionSchema,
  client: clientSchema.nullable().optional(),
  session: sessionSchema.nullable().optional(),
  payment_record: paymentRecordSchema.nullable().optional(),
  recent_messages: z.array(recentMessageSchema).max(80).default([]),
  availability_options: z.array(availabilityOptionSchema).max(20).default([]),
  task_context: z.record(z.unknown()).default({}),
  current_time: isoDatetimeSchema,
  timezone: nonEmptyStringSchema
}).strict().superRefine((request, ctx) => {
  if (request.instruction.trigger_event !== request.trigger_event) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["instruction", "trigger_event"],
      message: "instruction.trigger_event must match trigger_event."
    });
  }
});

export type DecideRequest = z.infer<typeof decideRequestSchema>;
