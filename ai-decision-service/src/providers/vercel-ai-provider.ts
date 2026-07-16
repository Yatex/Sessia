import { createAnthropic } from "@ai-sdk/anthropic";
import { createOpenAI } from "@ai-sdk/openai";
import type { LanguageModelV1 } from "@ai-sdk/provider";
import { generateObject, generateText, tool } from "ai";
import { z } from "zod";

import type { AppConfig } from "../config.js";
import { ConfigurationError, ProviderExecutionError } from "../lib/errors.js";
import type { LoggerLike } from "../lib/logger.js";
import { PROMPT_VERSION } from "../prompts/system-prompt.js";
import { decisionSchema } from "../schemas/decision.js";
import type { DecisionProvider, ProviderDecisionInput, ProviderDecisionResult } from "./base-provider.js";

export class VercelAiDecisionProvider implements DecisionProvider {
  private readonly modelFactory: (modelId: string) => LanguageModelV1;

  constructor(
    private readonly config: Pick<AppConfig, "modelProvider" | "model" | "timeoutMs" | "maxRetries" | "temperature" | "logPrompts" | "aiGatewayApiKey" | "aiGatewayBaseUrl" | "openAiApiKey" | "openAiBaseUrl" | "anthropicApiKey" | "anthropicBaseUrl" | "toolServiceSecret">,
    private readonly logger: LoggerLike
  ) {
    this.modelFactory = createModelFactory(config);
  }

  async decide(input: ProviderDecisionInput): Promise<ProviderDecisionResult> {
    const abortSignal = AbortSignal.timeout(this.config.timeoutMs);

    this.logger.info?.({
      event: "ai.decision.request",
      provider: "vercel",
      modelProvider: this.config.modelProvider,
      model: this.config.model,
      triggerEvent: input.context.trigger_event,
      instructionKey: input.context.instruction.key
    }, "Sending Sessia decision request to model provider.");

    if (this.config.logPrompts) {
      this.logger.debug?.({ system: input.prompt.system, prompt: input.prompt.prompt }, "Sessia decision prompt content.");
    }

    try {
      const toolTrace = input.context.architecture_version === "grounded_v2" ? await this.runTools(input, abortSignal) : null;
      const groundedPrompt = toolTrace ? `${input.prompt.prompt}\n\nTool results selected by the model:\n${JSON.stringify(toolTrace.toolResults, null, 2)}\n\nCite evidence IDs from these results.` : input.prompt.prompt;
      const result = await generateObject({
        model: this.modelFactory(this.config.model),
        schema: decisionSchema,
        schemaName: "sessia_ai_decision",
        schemaDescription: "Exactly one Sessia AI Assistant decision for a single session/client task.",
        system: input.prompt.system,
        prompt: groundedPrompt,
        temperature: this.config.temperature,
        maxRetries: this.config.maxRetries,
        abortSignal
      });

      return {
        rawDecision: result.object,
        metadata: {
          provider: "vercel",
          modelProvider: this.config.modelProvider,
          model: this.config.model,
          finishReason: result.finishReason,
          usage: result.usage,
          responseId: result.response?.id,
          promptVersion: PROMPT_VERSION,
          schemaVersion: "decision_v2",
          tools_requested: toolTrace?.toolsRequested ?? [],
          tools_completed: toolTrace?.toolsCompleted ?? [],
          tool_errors: toolTrace?.toolErrors ?? [],
          tool_results: toolTrace?.toolResults ?? {},
          evidence: toolTrace?.evidence ?? []
        }
      };
    } catch (error) {
      const timeout = error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError");
      this.logger.error?.({
        event: "ai.decision.error",
        timeout,
        errorName: error instanceof Error ? error.name : "UnknownError",
        errorMessage: error instanceof Error ? error.message : "Unknown provider error"
      }, "Sessia decision provider request failed.");

      if (timeout) {
        throw new ProviderExecutionError("The AI provider timed out before returning a decision.", "provider_timeout", { cause: error });
      }

      throw new ProviderExecutionError("The AI provider failed to return a decision.", "provider_error", { cause: error });
    }
  }

  private async runTools(input: ProviderDecisionInput, abortSignal: AbortSignal) {
    if (!this.config.toolServiceSecret) throw new ConfigurationError("SESSIA_AI_TOOL_SECRET is required for grounded_v2 tools.");
    const allowed = input.context.allowed_tools ?? [];
    const endpoint = input.context.tool_endpoint!;
    const contextToken = input.context.context_token!;
    const toolResults: Record<string, unknown> = {};
    const evidence: unknown[] = [];
    const toolsRequested: string[] = [];
    const toolsCompleted: string[] = [];
    const toolErrors: Array<{ tool: string; error: string }> = [];

    const tools = Object.fromEntries(allowed.map((name) => [name, tool({
      description: toolDescription(name),
      parameters: z.object({}),
      execute: async () => {
        toolsRequested.push(name);
        try {
          const response = await fetch(endpoint.replace("__TOOL__", name), {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-Sessia-AI-Tool-Secret": this.config.toolServiceSecret! },
            body: JSON.stringify({ context_token: contextToken }),
            signal: abortSignal
          });
          if (!response.ok) throw new Error(`Tool endpoint returned HTTP ${response.status}.`);
          const payload = await response.json() as { result: unknown; evidence?: unknown[] };
          toolResults[name] = payload.result;
          evidence.push(...(payload.evidence ?? []));
          toolsCompleted.push(name);
          return payload;
        } catch (error) {
          const message = error instanceof Error ? error.message : "Unknown tool error";
          toolErrors.push({ tool: name, error: message });
          return { error: { code: "tool_failed", message } };
        }
      }
    })]));

    await generateText({
      model: this.modelFactory(this.config.model),
      system: `${input.prompt.system}\nUse the available read-only tools before deciding. Do not guess facts.`,
      prompt: input.prompt.prompt,
      tools,
      maxSteps: 5,
      temperature: this.config.temperature,
      maxRetries: this.config.maxRetries,
      abortSignal
    });
    return { toolsRequested: [...new Set(toolsRequested)], toolsCompleted: [...new Set(toolsCompleted)], toolErrors, toolResults, evidence };
  }
}

function toolDescription(name: string): string {
  return ({
    client_context: "Read the authorized client's basic context.",
    session_context: "Read the authorized session date, time, status and confirmation state. Required for date or time answers.",
    conversation_history: "Read recent authorized conversation messages. Required to interpret short replies.",
    pending_interaction: "Read whether the current reply answers a pending session confirmation. Required for short confirmations.",
    professional_settings: "Read the professional's assistant settings, locale and instructions."
  } as Record<string, string>)[name] ?? "Read authorized Sessia context.";
}

function createModelFactory(config: Pick<AppConfig, "modelProvider" | "aiGatewayApiKey" | "aiGatewayBaseUrl" | "openAiApiKey" | "openAiBaseUrl" | "anthropicApiKey" | "anthropicBaseUrl">): (modelId: string) => LanguageModelV1 {
  if (config.modelProvider === "gateway") {
    if (!config.aiGatewayApiKey) throw new ConfigurationError("AI_GATEWAY_API_KEY is required when SESSIA_AI_MODEL_PROVIDER=gateway.");
    const gateway = createOpenAI({ apiKey: config.aiGatewayApiKey, baseURL: config.aiGatewayBaseUrl ?? "https://ai-gateway.vercel.sh/v1" });
    return (modelId: string) => gateway(modelId);
  }

  if (config.modelProvider === "openai") {
    if (!config.openAiApiKey) throw new ConfigurationError("OPENAI_API_KEY is required when SESSIA_AI_MODEL_PROVIDER=openai.");
    const openai = createOpenAI({ apiKey: config.openAiApiKey, ...(config.openAiBaseUrl ? { baseURL: config.openAiBaseUrl } : {}) });
    return (modelId: string) => openai(modelId);
  }

  if (!config.anthropicApiKey) throw new ConfigurationError("ANTHROPIC_API_KEY is required when SESSIA_AI_MODEL_PROVIDER=anthropic.");
  const anthropic = createAnthropic({ apiKey: config.anthropicApiKey, ...(config.anthropicBaseUrl ? { baseURL: config.anthropicBaseUrl } : {}) });
  return (modelId: string) => anthropic(modelId);
}
