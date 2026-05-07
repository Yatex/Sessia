import type { DecisionPrompt } from "../prompts/build-prompt.js";
import type { DecideRequest } from "../schemas/request.js";

export interface ProviderDecisionInput {
  prompt: DecisionPrompt;
  context: DecideRequest;
}

export interface ProviderDecisionResult {
  rawDecision: unknown;
  metadata?: Record<string, unknown>;
}

export interface DecisionProvider {
  decide(input: ProviderDecisionInput): Promise<ProviderDecisionResult>;
}
