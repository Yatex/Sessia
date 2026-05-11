import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import dotenv from "dotenv";
import { z } from "zod";

import { ConfigurationError } from "./lib/errors.js";

const serviceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const rootDir = path.resolve(serviceDir, "..");

for (const envPath of [path.join(rootDir, ".env"), path.join(serviceDir, ".env")]) {
  if (fs.existsSync(envPath)) dotenv.config({ path: envPath, override: false });
}

const providerSchema = z.enum(["mock", "vercel"]);
const modelProviderSchema = z.enum(["gateway", "openai", "anthropic"]);

const appConfigSchema = z.object({
  host: z.string().trim().min(1).default("127.0.0.1"),
  port: z.coerce.number().int().positive().default(8788),
  provider: providerSchema.default("mock"),
  modelProvider: modelProviderSchema.default("gateway"),
  model: z.string().trim().min(1).default("gpt-5-mini"),
  timeoutMs: z.coerce.number().int().positive().default(30_000),
  maxRetries: z.coerce.number().int().min(0).max(5).default(1),
  temperature: z.coerce.number().min(0).max(2).default(0.2),
  logPrompts: z.coerce.boolean().default(false),
  openAiApiKey: z.string().trim().optional(),
  openAiBaseUrl: z.string().trim().optional(),
  aiGatewayApiKey: z.string().trim().optional(),
  aiGatewayBaseUrl: z.string().trim().optional(),
  anthropicApiKey: z.string().trim().optional(),
  anthropicBaseUrl: z.string().trim().optional()
}).superRefine((value, ctx) => {
  if (value.provider !== "vercel") return;

  if (value.modelProvider === "openai" && !value.openAiApiKey) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "OPENAI_API_KEY is required for OpenAI model provider." });
  }
  if (value.modelProvider === "gateway" && !value.aiGatewayApiKey) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "AI_GATEWAY_API_KEY is required for AI Gateway model provider." });
  }
  if (value.modelProvider === "anthropic" && !value.anthropicApiKey) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "ANTHROPIC_API_KEY is required for Anthropic model provider." });
  }
});

export type AppConfig = z.infer<typeof appConfigSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = appConfigSchema.safeParse({
    host: env.SESSIA_AI_HOST,
    port: env.SESSIA_AI_PORT,
    provider: env.SESSIA_AI_PROVIDER,
    modelProvider: env.SESSIA_AI_MODEL_PROVIDER,
    model: env.SESSIA_AI_MODEL,
    timeoutMs: env.SESSIA_AI_TIMEOUT_MS,
    maxRetries: env.SESSIA_AI_MAX_RETRIES,
    temperature: env.SESSIA_AI_TEMPERATURE,
    logPrompts: env.SESSIA_AI_LOG_PROMPTS,
    openAiApiKey: env.OPENAI_API_KEY,
    openAiBaseUrl: env.OPENAI_BASE_URL,
    aiGatewayApiKey: env.AI_GATEWAY_API_KEY,
    aiGatewayBaseUrl: env.AI_GATEWAY_BASE_URL,
    anthropicApiKey: env.ANTHROPIC_API_KEY,
    anthropicBaseUrl: env.ANTHROPIC_BASE_URL
  });

  if (!parsed.success) {
    const message = parsed.error.issues.map((issue) => issue.message).join(", ");
    throw new ConfigurationError(message || "Invalid Sessia AI configuration.");
  }

  return parsed.data;
}
