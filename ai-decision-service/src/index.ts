import { loadConfig } from "./config.js";
import { consoleLogger } from "./lib/logger.js";
import { buildServer } from "./server.js";

const config = loadConfig();
const server = buildServer(config, consoleLogger);

await server.listen({ host: config.host, port: config.port });
server.log.info(`Sessia AI decision service listening on http://${config.host}:${config.port}`);
