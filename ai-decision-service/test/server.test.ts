import assert from "node:assert/strict";
import test from "node:test";

import { buildServer } from "../src/server.js";
import { loadConfig } from "../src/config.js";
import { buildRequest } from "./support/build-request.js";

test("defaults real model routing to Vercel AI Gateway", () => {
  const config = loadConfig({ SESSIA_AI_PROVIDER: "mock" } as NodeJS.ProcessEnv);

  assert.equal(config.modelProvider, "gateway");
});

test("POST /decide returns a structured decision", async () => {
  const server = buildServer(loadConfig({ SESSIA_AI_PROVIDER: "mock" } as NodeJS.ProcessEnv));
  const response = await server.inject({
    method: "POST",
    url: "/decide",
    payload: buildRequest()
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().action, "mark_session_confirmed");
});
