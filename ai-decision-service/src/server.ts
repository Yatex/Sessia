import Fastify from "fastify";
import { z } from "zod";

import type { AppConfig } from "./config.js";
import type { LoggerLike } from "./lib/logger.js";
import { ProviderExecutionError } from "./lib/errors.js";
import { createDecisionProvider } from "./providers/create-provider.js";
import { decideRequestSchema } from "./schemas/request.js";
import { DecisionService } from "./services/decision-service.js";

export function buildServer(config: AppConfig, logger: LoggerLike = console) {
  const fastify = Fastify({ logger: false });
  const provider = createDecisionProvider(config, logger);
  const decisionService = new DecisionService(provider);

  fastify.get("/health", async () => ({ ok: true, provider: config.provider, modelProvider: config.modelProvider }));

  fastify.post("/decide", async (request, reply) => {
    const parsed = decideRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: {
          code: "invalid_request",
          message: "Invalid Sessia AI decision request.",
          details: parsed.error.flatten()
        }
      });
    }

    const decision = await decisionService.decide(parsed.data);
    return reply.status(200).send(decision);
  });

  fastify.setErrorHandler((error, _request, reply) => {
    if (error instanceof z.ZodError) {
      return reply.status(422).send({
        error: {
          code: "invalid_decision",
          message: "The AI provider returned an invalid decision.",
          details: error.flatten()
        }
      });
    }

    if (error instanceof ProviderExecutionError) {
      return reply.status(error.code === "provider_timeout" ? 504 : 502).send({
        error: {
          code: error.code,
          message: error.message
        }
      });
    }

    logger.error?.({ error }, "Sessia AI decision service request failed.");
    return reply.status(500).send({
      error: {
        code: "internal_error",
        message: "The Sessia AI decision service failed to complete the request."
      }
    });
  });

  return fastify;
}
