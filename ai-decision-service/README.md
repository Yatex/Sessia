# Sessia AI Decision Service

Small TypeScript decision service for Sessia's AI Assistant. Rails owns account data, task generation, ownership checks, and action execution. This service receives one Sessia AI task context and returns exactly one structured decision.

It follows the Attendly pattern:

- deterministic shortcuts for obvious confirmations, declines, payment reports, reminders, and known session questions
- Vercel AI SDK `generateObject` for ambiguous client replies
- strict Zod schemas for request and decision shape
- mock provider for local development and tests

## Run

```sh
cd ai-decision-service
npm install
npm run dev
```

Rails defaults to `http://127.0.0.1:8788/decide`.
