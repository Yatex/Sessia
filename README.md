# Sessia

Sessia is a Rails/PostgreSQL session management SaaS for independent professionals and small practices.

## Stack

- Ruby on Rails 7.1
- PostgreSQL
- Stripe Checkout, Billing Portal, and subscription webhooks
- Resend transactional email through Action Mailer
- Vercel AI SDK decision service for the AI assistant
- First-party `has_secure_password` authentication

## Local Setup

```bash
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Seeded demo login:

```text
demo@sessia.local
password123
```

## Environment

Copy `.env.example` into your deployment environment or shell and set:

- `APP_HOST`
- `DATABASE_URL`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `STRIPE_SECRET_KEY`
- `STRIPE_PUBLISHABLE_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_ID_STARTER`
- `STRIPE_PRICE_ID_PRO`
- `STRIPE_PRICE_ID_STUDIO`
- `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` for Google sign-in and Calendar sync
- `GOOGLE_AUTH_REDIRECT_URI` if your deployed Google sign-in callback differs from `APP_HOST/auth/google/callback`
- `GOOGLE_CALENDAR_REDIRECT_URI` if your deployed Calendar callback differs from `APP_HOST/google-calendar/callback`
- `SESSIA_AI_SERVICE_URL`
- `SESSIA_AI_PROVIDER`
- `SESSIA_AI_MODEL_PROVIDER`
- `SESSIA_AI_MODEL`
- `AI_GATEWAY_API_KEY` for Vercel AI Gateway
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_WHATSAPP_FROM` for real WhatsApp delivery
- `TWILIO_WEBHOOK_URL` and `TWILIO_VERIFY_WEBHOOK_SIGNATURE` for inbound WhatsApp replies

Stripe webhooks should post to:

```text
POST /stripe/webhook
```

## AI Assistant

Sessia follows the Attendly-style split:

- Rails owns users, clients, sessions, payment state, AI tasks, alerts, and message execution.
- `ai-decision-service` uses the Vercel AI SDK through Vercel AI Gateway to choose one safe action for a task.

For production AI decisions through your Vercel balance, set:

```bash
SESSIA_AI_PROVIDER=vercel
SESSIA_AI_MODEL_PROVIDER=gateway
AI_GATEWAY_API_KEY=...
SESSIA_AI_MODEL=gpt-5-mini
```

`OPENAI_API_KEY` is only needed if you deliberately set `SESSIA_AI_MODEL_PROVIDER=openai` and bypass Vercel AI Gateway.

For local demos:

```bash
cd ai-decision-service
npm install
SESSIA_AI_PROVIDER=mock npm run dev
```

Then run the Rails loop from the UI or with:

```bash
bin/rails sessia:ai:loop
```

Outbound AI messages are queued in Sessia unless Twilio WhatsApp environment variables are configured.

Inbound WhatsApp replies should post to:

```text
POST /webhooks/twilio/whatsapp
```

When `TWILIO_AUTH_TOKEN` is present, Sessia verifies Twilio's `X-Twilio-Signature` header before accepting the webhook. The inbound phone number is matched to a client, the reply is stored, and the AI assistant processes it immediately.

## Verification

```bash
bin/rails test
bin/rails zeitwerk:check
bin/rails db:migrate:status
cd ai-decision-service && npm test && npm run typecheck
```
