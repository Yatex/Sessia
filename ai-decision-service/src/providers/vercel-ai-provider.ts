import { createAnthropic } from "@ai-sdk/anthropic";
import { createOpenAI } from "@ai-sdk/openai";
import type { LanguageModelV1 } from "@ai-sdk/provider";
import { generateObject } from "ai";

import type { AppConfig } from "../config.js";
import { ConfigurationError, ProviderExecutionError } from "../lib/errors.js";
import type { LoggerLike } from "../lib/logger.js";
import { decisionSchema } from "../schemas/decision.js";
import type { DecisionProvider, ProviderDecisionInput, ProviderDecisionResult } from "./base-provider.js";

export class VercelAiDecisionProvider implements DecisionProvider {
  private readonly modelFactory: (modelId: string) => LanguageModelV1;

  constructor(
    private readonly config: Pick<AppConfig, "modelProvider" | "model" | "timeoutMs" | "maxRetries" | "temperature" | "logPrompts" | "aiGatewayApiKey" | "aiGatewayBaseUrl" | "openAiApiKey" | "openAiBaseUrl" | "anthropicApiKey" | "anthropicBaseUrl">,
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
      const result = await generateObject({
        model: this.modelFactory(this.config.model),
        schema: decisionSchema,
        schemaName: "sessia_ai_decision",
        schemaDescription: "Exactly one Sessia AI Assistant decision for a single session/client task.",
        system: input.prompt.system,
        prompt: input.prompt.prompt,
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
          responseId: result.response?.id
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
