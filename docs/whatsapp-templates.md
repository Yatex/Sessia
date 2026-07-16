# Sessia WhatsApp templates

`Messaging::WhatsappTemplateCatalog` is the only source of truth for proactive WhatsApp templates. It defines the workflow, locale, friendly name, category, body, semantic variables, numeric placeholders, and ContentSid environment variable. It never stores a ContentSid.

Twilio's official Content API supports creating, fetching, listing, updating unsubmitted templates, submitting templates for WhatsApp approval, and fetching approval status. Sessia uses the API directly because this project does not install the `twilio-ruby` SDK. See the [Content API quickstart](https://www.twilio.com/docs/content/create-and-send-your-first-content-api-template) and [Content API resources](https://www.twilio.com/docs/content/content-api-resources).

## Active catalog

| Key | Locale | Workflow | Variables | Placeholders | ENV |
| --- | --- | --- | --- | --- | --- |
| session_confirmation | es | confirm_session | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_CONFIRMATION_ES |
| session_confirmation | en | confirm_session | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_CONFIRMATION_EN |
| session_follow_up | es | follow_up_no_response | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_FOLLOW_UP_ES |
| session_follow_up | en | follow_up_no_response | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_FOLLOW_UP_EN |
| session_reminder | es | send_pre_session_reminder | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_REMINDER_ES |
| session_reminder | en | send_pre_session_reminder | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_REMINDER_EN |
| session_feedback | es | ask_feedback_after_session | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_FEEDBACK_ES |
| session_feedback | en | ask_feedback_after_session | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_FEEDBACK_EN |
| payment_reminder | es | payment_reminder | client_name, payment_amount, session_name | {{1}}, {{2}}, {{3}} | TWILIO_TEMPLATE_PAYMENT_REMINDER_ES |
| payment_reminder | en | payment_reminder | client_name, payment_amount, session_name | {{1}}, {{2}}, {{3}} | TWILIO_TEMPLATE_PAYMENT_REMINDER_EN |
| session_change | es | blocked_time_rebooking | client_name, session_name, schedule_change_detail | {{1}}, {{2}}, {{3}} | TWILIO_TEMPLATE_SESSION_CHANGE_ES |
| session_change | en | blocked_time_rebooking | client_name, session_name, schedule_change_detail | {{1}}, {{2}}, {{3}} | TWILIO_TEMPLATE_SESSION_CHANGE_EN |
| session_canceled | es | blocked_time_rebooking (cancelled session) | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_CANCELED_ES |
| session_canceled | en | blocked_time_rebooking (cancelled session) | client_name, session_name, session_date, session_time | {{1}}, {{2}}, {{3}}, {{4}} | TWILIO_TEMPLATE_SESSION_CANCELED_EN |

## Production commands

All commands are explicit and safe to run from a Render Shell. None run during boot, deploy, migrations, cron, or message processing.

```bash
bundle exec rails sessia:twilio:templates:dry_run
bundle exec rails sessia:twilio:templates:create
bundle exec rails sessia:twilio:templates:status
bundle exec rails sessia:twilio:templates:audit
bundle exec rails sessia:twilio:templates:env
```

`dry_run` makes no API calls. `create` lists remote templates and creates only missing `friendly_name + language` pairs. It does not delete templates, submit approval, or modify ENV. `status` fetches Content and WhatsApp approval information for configured SIDs. `audit` compares the catalog with ENV and remote body, locale, friendly name, and variable numbering. `env` prints the current block only.

## Approval and rollout

After `create`, review each new SID in **Twilio Console > Messaging > Content Template Builder**, submit it for WhatsApp approval, and wait for `approved`. Approval submission is intentionally manual in this version even though Twilio exposes an API endpoint for it; creating a Content resource must not silently start an external review.

Copy only approved SIDs into the matching Render environment variables. Never paste Auth Tokens or SIDs into source code. Restart the web and cron services after changing Render ENV, then run `status` and `audit`.

To generate a new revision without deleting the old approved template, update the body/contract in the catalog, increment the suffix in `friendly_name` from `_v1` to `_v2`, deploy, run `dry_run`, and then run `create`. This preserves old templates and creates a separately auditable revision.
