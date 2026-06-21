# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_06_12_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ai_alerts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "client_id"
    t.bigint "session_id"
    t.bigint "ai_task_id"
    t.string "status", default: "open", null: false
    t.string "severity", default: "medium", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_task_id"], name: "index_ai_alerts_on_ai_task_id"
    t.index ["client_id"], name: "index_ai_alerts_on_client_id"
    t.index ["session_id"], name: "index_ai_alerts_on_session_id"
    t.index ["user_id", "status", "created_at"], name: "index_ai_alerts_on_user_id_and_status_and_created_at"
    t.index ["user_id"], name: "index_ai_alerts_on_user_id"
  end

  create_table "ai_settings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.boolean "confirm_sessions", default: true, null: false
    t.boolean "send_pre_session_reminders", default: true, null: false
    t.boolean "follow_up_no_response", default: true, null: false
    t.boolean "ask_feedback_after_sessions", default: true, null: false
    t.boolean "answer_basic_questions", default: true, null: false
    t.boolean "escalate_important_conversations", default: true, null: false
    t.boolean "payment_reminders", default: false, null: false
    t.text "instructions"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "use_professional_whatsapp", default: false, null: false
    t.string "professional_whatsapp_phone"
    t.index ["user_id"], name: "index_ai_settings_on_user_id", unique: true
  end

  create_table "ai_tasks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "client_id"
    t.bigint "session_id"
    t.string "trigger_event", null: false
    t.string "automation_key"
    t.string "status", default: "pending", null: false
    t.datetime "scheduled_for", null: false
    t.datetime "processed_at"
    t.jsonb "context_data", default: {}, null: false
    t.jsonb "result_data", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_ai_tasks_on_client_id"
    t.index ["session_id", "automation_key"], name: "index_ai_tasks_on_session_id_and_automation_key"
    t.index ["session_id"], name: "index_ai_tasks_on_session_id"
    t.index ["user_id", "status", "scheduled_for"], name: "index_ai_tasks_on_user_id_and_status_and_scheduled_for"
    t.index ["user_id", "trigger_event"], name: "index_ai_tasks_on_user_id_and_trigger_event"
    t.index ["user_id"], name: "index_ai_tasks_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "actor_id"
    t.string "event", null: false
    t.string "auditable_type"
    t.bigint "auditable_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["user_id", "event", "created_at"], name: "index_audit_logs_on_user_id_and_event_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "availability_rules", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "weekday", null: false
    t.integer "start_minute", null: false
    t.integer "end_minute", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "weekday", "start_minute"], name: "idx_on_user_id_weekday_start_minute_c3ae5ae7e9"
    t.index ["user_id", "weekday"], name: "index_availability_rules_on_user_id_and_weekday"
    t.index ["user_id"], name: "index_availability_rules_on_user_id"
  end

  create_table "calendar_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", default: "google", null: false
    t.string "provider_account_email"
    t.string "calendar_id", default: "primary", null: false
    t.text "access_token_ciphertext"
    t.text "refresh_token_ciphertext"
    t.datetime "access_token_expires_at"
    t.boolean "sync_sessions", default: true, null: false
    t.integer "status", default: 0, null: false
    t.datetime "last_synced_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_calendar_connections_on_status"
    t.index ["user_id", "provider"], name: "index_calendar_connections_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_calendar_connections_on_user_id"
  end

  create_table "charges", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "user_id", null: false
    t.bigint "session_id"
    t.integer "amount_cents", null: false
    t.string "currency", default: "ARS", null: false
    t.string "concept", null: false
    t.text "description"
    t.date "due_date"
    t.integer "status", default: 0, null: false
    t.integer "generated_by", default: 0, null: false
    t.string "external_reference", null: false
    t.string "mercado_pago_preference_id"
    t.text "mercado_pago_init_point"
    t.text "mercado_pago_sandbox_init_point"
    t.text "payment_url"
    t.datetime "paid_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_charges_on_client_id"
    t.index ["external_reference"], name: "index_charges_on_external_reference", unique: true
    t.index ["mercado_pago_preference_id"], name: "index_charges_on_mercado_pago_preference_id"
    t.index ["session_id"], name: "index_charges_on_session_id", unique: true, where: "(session_id IS NOT NULL)"
    t.index ["user_id", "due_date"], name: "index_charges_on_user_id_and_due_date"
    t.index ["user_id", "status"], name: "index_charges_on_user_id_and_status"
    t.index ["user_id"], name: "index_charges_on_user_id"
  end

  create_table "client_billing_profiles", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "user_id", null: false
    t.integer "default_session_price_cents", default: 0, null: false
    t.string "currency", default: "ARS", null: false
    t.boolean "payment_required_before_session", default: false, null: false
    t.integer "default_due_timing", default: 0, null: false
    t.integer "custom_due_days_before"
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_client_billing_profiles_on_client_id", unique: true
    t.index ["user_id", "active"], name: "index_client_billing_profiles_on_user_id_and_active"
    t.index ["user_id"], name: "index_client_billing_profiles_on_user_id"
  end

  create_table "clients", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "phone", null: false
    t.integer "status", default: 0, null: false
    t.string "preferred_contact_channel", default: "whatsapp", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "portal_token", null: false
    t.datetime "linked_at"
    t.string "phone_normalized"
    t.index ["linked_at"], name: "index_clients_on_linked_at"
    t.index ["phone_normalized", "user_id"], name: "index_clients_on_phone_normalized_and_user_id"
    t.index ["portal_token"], name: "index_clients_on_portal_token", unique: true
    t.index ["user_id", "email"], name: "index_clients_on_user_id_and_email"
    t.index ["user_id", "status"], name: "index_clients_on_user_id_and_status"
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "credit_ledger_entries", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "user_id", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "ARS", null: false
    t.integer "entry_type", null: false
    t.string "reason"
    t.bigint "related_payment_id"
    t.bigint "related_charge_id"
    t.bigint "related_session_id"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "created_at"], name: "index_credit_ledger_entries_on_client_id_and_created_at"
    t.index ["client_id"], name: "index_credit_ledger_entries_on_client_id"
    t.index ["created_by_id"], name: "index_credit_ledger_entries_on_created_by_id"
    t.index ["related_charge_id"], name: "index_credit_ledger_entries_on_related_charge_id"
    t.index ["related_payment_id"], name: "index_credit_ledger_entries_on_related_payment_id"
    t.index ["related_session_id"], name: "index_credit_ledger_entries_on_related_session_id"
    t.index ["user_id", "created_at"], name: "index_credit_ledger_entries_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_credit_ledger_entries_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "client_id"
    t.bigint "session_id"
    t.integer "direction", default: 0, null: false
    t.string "channel", default: "email", null: false
    t.integer "status", default: 0, null: false
    t.string "subject"
    t.text "body"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ai_task_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "external_id"
    t.text "error_message"
    t.index ["ai_task_id"], name: "index_messages_on_ai_task_id"
    t.index ["client_id", "created_at"], name: "index_messages_on_client_id_and_created_at"
    t.index ["client_id"], name: "index_messages_on_client_id"
    t.index ["external_id"], name: "index_messages_on_external_id"
    t.index ["external_id"], name: "index_messages_on_external_id_unique", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["session_id"], name: "index_messages_on_session_id"
    t.index ["user_id", "direction", "created_at"], name: "index_messages_on_user_id_and_direction_and_created_at"
    t.index ["user_id", "status"], name: "index_messages_on_user_id_and_status"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "payment_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", default: "mercado_pago", null: false
    t.string "provider_user_id"
    t.text "access_token_ciphertext"
    t.text "refresh_token_ciphertext"
    t.datetime "token_expires_at"
    t.integer "status", default: 0, null: false
    t.datetime "connected_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_user_id"], name: "index_payment_accounts_on_provider_and_provider_user_id"
    t.index ["status"], name: "index_payment_accounts_on_status"
    t.index ["user_id", "provider"], name: "index_payment_accounts_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_payment_accounts_on_user_id"
  end

  create_table "payment_records", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "client_id"
    t.bigint "session_id"
    t.integer "amount_cents", default: 0, null: false
    t.string "currency", default: "USD", null: false
    t.integer "status", default: 0, null: false
    t.date "due_on"
    t.datetime "paid_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_payment_records_on_client_id"
    t.index ["session_id"], name: "index_payment_records_on_session_id"
    t.index ["user_id", "due_on"], name: "index_payment_records_on_user_id_and_due_on"
    t.index ["user_id", "status"], name: "index_payment_records_on_user_id_and_status"
    t.index ["user_id"], name: "index_payment_records_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "charge_id", null: false
    t.bigint "client_id", null: false
    t.bigint "user_id", null: false
    t.string "provider", default: "mercado_pago", null: false
    t.string "provider_payment_id"
    t.integer "amount_cents", default: 0, null: false
    t.string "currency", default: "ARS", null: false
    t.integer "status", default: 0, null: false
    t.string "status_detail"
    t.datetime "paid_at"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["charge_id", "status"], name: "index_payments_on_charge_id_and_status"
    t.index ["charge_id"], name: "index_payments_on_charge_id"
    t.index ["client_id"], name: "index_payments_on_client_id"
    t.index ["provider", "provider_payment_id"], name: "index_payments_on_provider_and_provider_payment_id", unique: true, where: "(provider_payment_id IS NOT NULL)"
    t.index ["user_id", "status"], name: "index_payments_on_user_id_and_status"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "schedule_blocks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", default: "Blocked time", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.text "notes"
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "starts_at"], name: "index_schedule_blocks_on_user_id_and_starts_at"
    t.index ["user_id", "status"], name: "index_schedule_blocks_on_user_id_and_status"
    t.index ["user_id"], name: "index_schedule_blocks_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "client_id", null: false
    t.string "title", null: false
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.integer "status", default: 0, null: false
    t.integer "confirmation_status", default: 0, null: false
    t.integer "payment_status", default: 1, null: false
    t.boolean "recurring", default: false, null: false
    t.string "recurrence_rule"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "currency", default: "ARS", null: false
    t.bigint "parent_session_id"
    t.string "recurrence_frequency", default: "none", null: false
    t.integer "recurrence_days", default: [], null: false, array: true
    t.date "recurrence_ends_on"
    t.date "recurrence_generated_until"
    t.boolean "sync_to_google_calendar", default: false, null: false
    t.string "google_calendar_event_id"
    t.datetime "google_calendar_synced_at"
    t.text "google_calendar_sync_error"
    t.bigint "charge_id"
    t.boolean "payment_required_before_session", default: false, null: false
    t.index ["charge_id"], name: "index_sessions_on_charge_id"
    t.index ["client_id", "start_time"], name: "index_sessions_on_client_id_and_start_time"
    t.index ["client_id"], name: "index_sessions_on_client_id"
    t.index ["parent_session_id"], name: "index_sessions_on_parent_session_id"
    t.index ["user_id", "confirmation_status"], name: "index_sessions_on_user_id_and_confirmation_status"
    t.index ["user_id", "google_calendar_event_id"], name: "index_sessions_on_user_id_and_google_calendar_event_id"
    t.index ["user_id", "parent_session_id"], name: "index_sessions_on_user_id_and_parent_session_id"
    t.index ["user_id", "payment_status"], name: "index_sessions_on_user_id_and_payment_status"
    t.index ["user_id", "recurrence_frequency"], name: "index_sessions_on_user_id_and_recurrence_frequency"
    t.index ["user_id", "start_time"], name: "index_sessions_on_user_id_and_start_time"
    t.index ["user_id", "sync_to_google_calendar"], name: "index_sessions_on_user_id_and_sync_to_google_calendar"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "plan_tier", default: "starter", null: false
    t.integer "status", default: 0, null: false
    t.string "provider", default: "stripe", null: false
    t.string "provider_subscription_id"
    t.string "provider_plan_id"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "trial_ends_at"
    t.boolean "cancel_at_period_end", default: false, null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_subscription_id"], name: "index_subscriptions_on_provider_and_provider_subscription_id", unique: true
    t.index ["provider_plan_id"], name: "index_subscriptions_on_provider_plan_id"
    t.index ["user_id", "status"], name: "index_subscriptions_on_user_id_and_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "password_reset_token_digest"
    t.datetime "password_reset_sent_at"
    t.string "time_zone", default: "UTC", null: false
    t.string "stripe_customer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "en", null: false
    t.integer "role", default: 0, null: false
    t.string "google_uid"
    t.string "google_avatar_url"
    t.text "payment_instructions"
    t.integer "account_type", default: 0, null: false
    t.bigint "studio_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true, where: "(google_uid IS NOT NULL)"
    t.index ["locale"], name: "index_users_on_locale"
    t.index ["password_reset_token_digest"], name: "index_users_on_password_reset_token_digest", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id"
    t.index ["studio_id", "account_type"], name: "index_users_on_studio_id_and_account_type"
    t.index ["studio_id"], name: "index_users_on_studio_id"
  end

  add_foreign_key "ai_alerts", "ai_tasks"
  add_foreign_key "ai_alerts", "clients"
  add_foreign_key "ai_alerts", "sessions"
  add_foreign_key "ai_alerts", "users"
  add_foreign_key "ai_settings", "users"
  add_foreign_key "ai_tasks", "clients"
  add_foreign_key "ai_tasks", "sessions"
  add_foreign_key "ai_tasks", "users"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "availability_rules", "users"
  add_foreign_key "calendar_connections", "users"
  add_foreign_key "charges", "clients"
  add_foreign_key "charges", "sessions"
  add_foreign_key "charges", "users"
  add_foreign_key "client_billing_profiles", "clients"
  add_foreign_key "client_billing_profiles", "users"
  add_foreign_key "clients", "users"
  add_foreign_key "credit_ledger_entries", "charges", column: "related_charge_id"
  add_foreign_key "credit_ledger_entries", "clients"
  add_foreign_key "credit_ledger_entries", "payments", column: "related_payment_id"
  add_foreign_key "credit_ledger_entries", "sessions", column: "related_session_id"
  add_foreign_key "credit_ledger_entries", "users"
  add_foreign_key "credit_ledger_entries", "users", column: "created_by_id"
  add_foreign_key "messages", "ai_tasks"
  add_foreign_key "messages", "clients"
  add_foreign_key "messages", "sessions"
  add_foreign_key "messages", "users"
  add_foreign_key "payment_accounts", "users"
  add_foreign_key "payment_records", "clients"
  add_foreign_key "payment_records", "sessions"
  add_foreign_key "payment_records", "users"
  add_foreign_key "payments", "charges"
  add_foreign_key "payments", "clients"
  add_foreign_key "payments", "users"
  add_foreign_key "schedule_blocks", "users"
  add_foreign_key "sessions", "charges"
  add_foreign_key "sessions", "clients"
  add_foreign_key "sessions", "sessions", column: "parent_session_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "users", "users", column: "studio_id"
end
