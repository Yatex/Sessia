import type { AppConfig } from "../config.js";
import type { LoggerLike } from "../lib/logger.js";
import type { DecisionProvider } from "./base-provider.js";
import { MockDecisionProvider } from "./mock-provider.js";
import { VercelAiDecisionProvider } from "./vercel-ai-provider.js";

export function createDecisionProvider(config: AppConfig, logger: LoggerLike): DecisionProvider {
  if (config.provider === "vercel") {
    return new VercelAiDecisionProvider(config, logger);
  }

  return new MockDecisionProvider();
}
