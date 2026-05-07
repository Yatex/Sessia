export interface LoggerLike {
  info?(payload: unknown, message?: string): void;
  warn?(payload: unknown, message?: string): void;
  error?(payload: unknown, message?: string): void;
  debug?(payload: unknown, message?: string): void;
}

export const consoleLogger: LoggerLike = {
  info: (payload, message) => console.info(message ?? "info", payload),
  warn: (payload, message) => console.warn(message ?? "warn", payload),
  error: (payload, message) => console.error(message ?? "error", payload),
  debug: (payload, message) => console.debug(message ?? "debug", payload)
};
