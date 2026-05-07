demo_user = User.find_or_initialize_by(email: "demo@sessia.local")
demo_user.assign_attributes(
  name: "Demo Professional",
  password: "password123",
  password_confirmation: "password123",
  time_zone: "America/Montevideo",
  locale: "en",
  role: "admin",
  stripe_customer_id: "cus_sessia_demo"
)
demo_user.save!

demo_user.ai_alerts.delete_all
demo_user.messages.delete_all
demo_user.ai_tasks.delete_all
demo_user.payment_records.delete_all
demo_user.sessions.delete_all
demo_user.clients.delete_all
demo_user.subscriptions.delete_all
demo_user.schedule_blocks.delete_all
demo_user.availability_rules.delete_all

demo_user.create_ai_setting! unless demo_user.ai_setting
demo_user.ai_setting.update!(
  confirm_sessions: true,
  send_pre_session_reminders: true,
  follow_up_no_response: true,
  ask_feedback_after_sessions: true,
  answer_basic_questions: true,
  escalate_important_conversations: true,
  payment_reminders: true,
  use_professional_whatsapp: true,
  professional_whatsapp_phone: "+598 99 000 111",
  instructions: "Warm, concise WhatsApp follow-ups. Confirm schedule changes with the professional before committing."
)

Availability::Defaults.ensure_for(demo_user)

client_rows = [
  ["Ana Martinez", "ana@example.com", "+598 99 111 222", "Weekly therapy client. Prefers morning sessions."],
  ["Lucas Pereira", "lucas@example.com", "+598 99 333 444", "Math tutoring client. Parent prefers reminders the day before."],
  ["Maya Costa", "maya@example.com", "+598 99 555 666", "Executive coaching client focused on planning."],
  ["Sofia Ramos", "sofia@example.com", "+598 98 101 202", "Pilates client with recurring Friday sessions."],
  ["Nicolas Alvarez", "nicolas@example.com", "+598 97 303 404", "Consulting client. Usually pays ahead."],
  ["Valentina Silva", "valentina@example.com", "+598 96 505 606", "Language tutoring client."],
  ["Mateo Torres", "mateo@example.com", "+598 95 707 808", "Therapy client with follow-up reminders enabled."],
  ["Camila Duarte", "camila@example.com", "+598 94 909 010", "Training client. Alternates online and in-person."],
  ["Bruno Castro", "bruno@example.com", "+598 93 212 323", "Business consulting client."],
  ["Emma Ferreira", "emma@example.com", "+598 92 434 545", "Coaching client. Likes concise WhatsApp notes."],
  ["Diego Medina", "diego@example.com", "+598 91 656 767", "Exam prep client."],
  ["Julia Ortega", "julia@example.com", "+598 90 878 989", "Monthly strategy client."]
]

clients = client_rows.map.with_index do |(name, email, phone, notes), index|
  demo_user.clients.create!(
    name: name,
    email: email,
    phone: phone,
    preferred_contact_channel: Client::WHATSAPP_CHANNEL,
    notes: notes,
    linked_at: index < 9 ? (index + 1).days.ago : nil
  )
end

demo_user.subscriptions.create!(
  plan_tier: "pro",
  status: "active",
  provider: "stripe",
  provider_subscription_id: "sub_sessia_demo_pro",
  provider_plan_id: ENV["STRIPE_PRICE_ID_PRO"].presence || "price_demo_pro",
  current_period_start: Time.current.beginning_of_month,
  current_period_end: 1.month.from_now.end_of_day,
  quantity: 1
)

def create_demo_session(user, client, title, starts_at, confirmation_status, payment_status, price_cents, notes: "Seeded demo session for Sessia.")
  user.sessions.create!(
    client: client,
    title: title,
    start_time: starts_at,
    end_time: starts_at + 50.minutes,
    price_cents: price_cents,
    currency: "USD",
    status: starts_at < Time.current ? "completed" : "scheduled",
    confirmation_status: confirmation_status,
    payment_status: payment_status,
    notes: notes
  )
end

Time.use_zone(demo_user.time_zone) do
  week_start = Date.current.beginning_of_week(:monday)

  demo_user.schedule_blocks.create!(
    title: "Lunch break",
    starts_at: Time.zone.parse("#{week_start + 2.days} 12:00"),
    ends_at: Time.zone.parse("#{week_start + 2.days} 13:00"),
    notes: "Demo blocked time. Sessia will not offer this slot."
  )

  sessions = [
    [clients[0], "Therapy session", week_start, "09:00", "confirmed", "paid", 8500],
    [clients[1], "Math tutoring", week_start, "11:00", "pending", "pending", 5500],
    [clients[2], "Coaching check-in", week_start + 1.day, "10:00", "confirmed", "pending", 12000],
    [clients[3], "Pilates assessment", week_start + 1.day, "16:00", "maybe", "paid", 6500],
    [clients[4], "Consulting sprint", week_start + 2.days, "09:00", "confirmed", "paid", 18000],
    [clients[5], "English tutoring", week_start + 2.days, "15:00", "pending", "pending", 6000],
    [clients[6], "Therapy follow-up", week_start + 3.days, "08:00", "declined", "cancelled", 8500],
    [clients[7], "Training session", week_start + 3.days, "13:00", "confirmed", "overdue", 7500],
    [clients[8], "Business consult", week_start + 4.days, "10:00", "confirmed", "paid", 16000],
    [clients[9], "Coaching recap", week_start + 4.days, "14:00", "pending", "pending", 11000],
    [clients[10], "Exam prep", week_start + 5.days, "09:00", "not_requested", "pending", 6500],
    [clients[11], "Strategy session", week_start + 6.days, "17:00", "confirmed", "paid", 20000]
  ].map do |client, title, date, hour, confirmation_status, payment_status, price_cents|
    create_demo_session(demo_user, client, title, Time.zone.parse("#{date} #{hour}"), confirmation_status, payment_status, price_cents)
  end

  recurring_therapy = create_demo_session(
    demo_user,
    clients[0],
    "Therapy recurring block",
    Time.zone.parse("#{week_start + 1.day} 12:00"),
    "confirmed",
    "pending",
    8500,
    notes: "Recurring weekly therapy block generated by seeds."
  )
  recurring_therapy.update!(
    recurring: true,
    recurrence_frequency: "weekly",
    recurrence_days: [2, 4],
    recurrence_ends_on: 2.months.from_now.to_date,
    recurrence_rule: "Weekly on Tuesday and Thursday"
  )
  RecurringSessionGenerator.new(recurring_therapy).generate!

  monthly_strategy = create_demo_session(
    demo_user,
    clients[11],
    "Monthly strategy review",
    Time.zone.parse("#{week_start + 2.days} 18:00"),
    "confirmed",
    "paid",
    20000,
    notes: "Monthly strategy session generated by seeds."
  )
  monthly_strategy.update!(
    recurring: true,
    recurrence_frequency: "monthly",
    recurrence_ends_on: 4.months.from_now.to_date,
    recurrence_rule: "Monthly on the same date"
  )
  RecurringSessionGenerator.new(monthly_strategy).generate!

  sessions.each do |session_record|
    next if session_record.payment_not_tracked?

    demo_user.payment_records.create!(
      client: session_record.client,
      session: session_record,
      amount_cents: session_record.price_cents,
      currency: session_record.currency,
      status: if session_record.payment_overdue?
        "overdue"
      elsif session_record.payment_paid?
        "paid"
      elsif session_record.payment_cancelled?
        "cancelled"
      else
        "pending"
      end,
      due_on: session_record.start_time.to_date,
      paid_at: session_record.payment_paid? ? session_record.start_time - 1.day : nil,
      notes: "Demo payment record for #{session_record.title}."
    )
  end

  demo_user.messages.create!(
    client: clients[1],
    session: sessions[1],
    direction: "outbound",
    channel: Client::WHATSAPP_CHANNEL,
    status: "sent",
    subject: "Session confirmation",
    body: "Hi Lucas, confirming tomorrow's tutoring session.",
    sent_at: 2.hours.ago
  )

  demo_user.messages.create!(
    client: clients[7],
    session: sessions[7],
    direction: "inbound",
    channel: Client::WHATSAPP_CHANNEL,
    status: "sent",
    subject: "Payment question",
    body: "Can I pay this afternoon?",
    sent_at: 45.minutes.ago
  )

  completed_ai_task = demo_user.ai_tasks.create!(
    client: clients[1],
    session: sessions[1],
    trigger_event: "before_session",
    automation_key: "confirm_session",
    status: "completed",
    scheduled_for: 2.hours.ago,
    processed_at: 2.hours.ago,
    context_data: { "purpose" => "initial_confirmation" },
    result_data: {
      "activity_summary" => "Queued confirmation message for Lucas Pereira.",
      "performed_action" => "send_message",
      "reasoning_summary" => "Deterministic confirmation request for an upcoming session."
    }
  )

  demo_user.messages.create!(
    client: clients[1],
    session: sessions[1],
    ai_task: completed_ai_task,
    direction: "outbound",
    channel: Client::WHATSAPP_CHANNEL,
    status: "queued",
    subject: "confirmation_request",
    body: "Hi Lucas, can you confirm your Math tutoring session?",
    metadata: {
      source: "ai",
      automation_key: "confirm_session",
      trigger_event: "before_session"
    }
  )

  alert_task = demo_user.ai_tasks.create!(
    client: clients[7],
    session: sessions[7],
    trigger_event: "client_replied",
    automation_key: "answer_client_reply",
    status: "completed",
    scheduled_for: 40.minutes.ago,
    processed_at: 39.minutes.ago,
    result_data: {
      "activity_summary" => "Created AI alert for payment question.",
      "performed_action" => "alert_professional"
    }
  )

  demo_user.ai_alerts.create!(
    client: clients[7],
    session: sessions[7],
    ai_task: alert_task,
    severity: "medium",
    title: "Client follow-up needed",
    body: "Camila asked whether she can pay this afternoon. The payment is overdue, so Sessia flagged it for review.",
    metadata: {
      source: "seed",
      trigger_event: "client_replied"
    }
  )

  failed_delivery_task = demo_user.ai_tasks.create!(
    client: clients[5],
    session: sessions[5],
    trigger_event: "before_session",
    automation_key: "session_reminder",
    status: "failed",
    scheduled_for: 25.minutes.ago,
    processed_at: 23.minutes.ago,
    result_data: {
      "activity_summary" => "AI tried to send a reminder but WhatsApp delivery failed.",
      "performed_action" => "send_message",
      "reasoning_summary" => "Reminder was due before the English tutoring session."
    },
    error_message: "Twilio WhatsApp delivery failed."
  )

  demo_user.messages.create!(
    client: clients[5],
    session: sessions[5],
    ai_task: failed_delivery_task,
    direction: "outbound",
    channel: Client::WHATSAPP_CHANNEL,
    status: "failed",
    subject: "session_reminder",
    body: "Hi Valentina, this is a reminder for your English tutoring session.",
    external_id: "SM-demo-failed-delivery",
    error_message: "Outside WhatsApp conversation window.",
    metadata: {
      source: "ai",
      provider: {
        name: "twilio_whatsapp",
        status: "failed",
        error_message: "Outside WhatsApp conversation window."
      }
    }
  )

  demo_user.ai_alerts.create!(
    client: clients[5],
    session: sessions[5],
    ai_task: failed_delivery_task,
    severity: "high",
    title: "AI message delivery failed",
    body: "Sessia could not deliver a WhatsApp reminder to Valentina. Review provider configuration or the client conversation window.",
    metadata: {
      source: "seed",
      provider: "twilio_whatsapp"
    }
  )
end

sample_accounts = [
  {
    name: "Starter Practice",
    email: "starter@sessia.local",
    role: "member",
    plan_tier: "starter",
    status: "active",
    provider: "stripe",
    clients: 7
  },
  {
    name: "Studio Practice",
    email: "studio@sessia.local",
    role: "member",
    plan_tier: "studio",
    status: "active",
    provider: "stripe",
    clients: 44
  },
  {
    name: "Admin Granted Practice",
    email: "grant@sessia.local",
    role: "member",
    plan_tier: "pro",
    status: "active",
    provider: "admin",
    clients: 18
  },
  {
    name: "Past Due Practice",
    email: "pastdue@sessia.local",
    role: "member",
    plan_tier: "pro",
    status: "past_due",
    provider: "stripe",
    clients: 23
  }
]

sample_accounts.each do |account|
  user = User.find_or_initialize_by(email: account[:email])
  user.assign_attributes(
    name: account[:name],
    password: "password123",
    password_confirmation: "password123",
    time_zone: "America/Montevideo",
    locale: "en",
    role: account[:role],
    stripe_customer_id: account[:provider] == "stripe" ? "cus_sessia_#{account[:plan_tier]}_#{account[:status]}" : nil
  )
  user.save!
  Availability::Defaults.ensure_for(user)

  user.subscriptions.delete_all
  user.subscriptions.create!(
    plan_tier: account[:plan_tier],
    status: account[:status],
    provider: account[:provider],
    provider_subscription_id: account[:provider] == "stripe" ? "sub_sessia_#{account[:email].parameterize}" : nil,
    provider_plan_id: account[:provider] == "stripe" ? "price_demo_#{account[:plan_tier]}" : "admin_#{account[:plan_tier]}",
    current_period_start: 2.weeks.ago,
    current_period_end: 1.month.from_now.end_of_day,
    quantity: 1
  )

  next if user.clients.exists?

  account[:clients].times do |index|
    user.clients.create!(
      name: "#{account[:name]} Client #{index + 1}",
      email: "client#{index + 1}-#{account[:email]}",
      phone: "+598 98 #{format('%03d', index + 1)} #{format('%03d', index + 20)}",
      preferred_contact_channel: Client::WHATSAPP_CHANNEL,
      linked_at: index.even? ? index.days.ago : nil
    )
  end
end

puts "Seeded demo account: demo@sessia.local / password123"
