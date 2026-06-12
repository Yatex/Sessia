module Ai
  class ActionExecutor
    ACTION_NAMES = %w[
      send_message
      mark_session_confirmed
      mark_session_maybe
      mark_session_declined
      reschedule_session
      create_client_note
      alert_professional
      schedule_follow_up
      do_nothing
    ].freeze

    Result = Struct.new(:status, :activity_summary, :performed_action, :error_message, keyword_init: true) do
      def to_h
        {
          "activity_summary" => activity_summary,
          "performed_action" => performed_action,
          "error_message" => error_message
        }.compact
      end
    end

    def initialize(task:, context:, instruction:, dispatcher: Messaging::Dispatcher.new)
      @task = task
      @context = context
      @instruction = instruction
      @dispatcher = dispatcher
    end

    def call(decision)
      action_name = decision.fetch("action")
      validate_action!(action_name)

      summary = dispatch_action(action_name, decision)
      Result.new(
        status: action_name == "do_nothing" ? "skipped" : "completed",
        activity_summary: summary,
        performed_action: action_name
      )
    rescue StandardError => error
      Result.new(
        status: "failed",
        activity_summary: "Action execution failed.",
        performed_action: decision&.fetch("action", nil),
        error_message: error.message
      )
    end

    private

    attr_reader :task, :context, :instruction, :dispatcher

    def validate_action!(action_name)
      raise ArgumentError, "Unsupported action: #{action_name}" unless ACTION_NAMES.include?(action_name)
      raise ArgumentError, "Action #{action_name} is not allowed for #{instruction.name}." unless instruction.allows_action?(action_name)
    end

    def dispatch_action(action_name, decision)
      case action_name
      when "send_message"
        send_message!(decision.fetch("message_body"))
      when "mark_session_confirmed"
        update_confirmation!("confirmed")
      when "mark_session_maybe"
        update_confirmation!("maybe")
      when "mark_session_declined"
        update_confirmation!("declined")
      when "reschedule_session"
        reschedule_session!(decision.fetch("target_start_at"))
      when "create_client_note"
        create_client_note!(decision.fetch("note_body"))
      when "alert_professional"
        alert_professional!(decision.fetch("alert_body"))
      when "schedule_follow_up"
        schedule_follow_up!(decision.fetch("follow_up_at"))
      when "do_nothing"
        decision["reasoning_summary"].presence || "No action taken."
      end
    end

    def send_message!(body)
      client = context.fetch(:client)
      raise "Cannot send an AI message without a client." if client.blank?

      message = dispatcher.deliver(
        user: task.user,
        client: client,
        session: context[:session],
        body: body,
        ai_task: task,
        metadata: message_metadata
      )

      if task.automation_key == "confirm_session" && context[:session]&.confirmation_not_requested?
        context[:session].update!(confirmation_status: "pending")
      end

      "Queued #{task.automation_key.presence || task.trigger_event} message for #{client.name} (#{message.status})."
    end

    def update_confirmation!(status)
      session = context[:session]
      raise "Cannot update confirmation without a session." if session.blank?

      session.update!(confirmation_status: status)
      acknowledgement = send_acknowledgement(confirmation_acknowledgement(status), event: "confirmation_#{status}")
      "#{session.client.name} marked #{status.humanize.downcase}#{acknowledgement ? ' and acknowledged' : ''}."
    end

    def reschedule_session!(target_start_at)
      session = context[:session]
      raise "Cannot reschedule without a session." if session.blank?

      target_start = parse_time_in_user_zone(target_start_at)
      raise "Target start time is invalid." if target_start.blank?

      duration = session.duration_minutes.positive? ? session.duration_minutes : 50
      calendar = Availability::Calendar.new(task.user)
      unless calendar.available?(target_start, duration_minutes: duration, exclude_session: session)
        raise "Target start time is no longer available."
      end

      session.update!(
        start_time: target_start,
        end_time: target_start + duration.minutes,
        status: "scheduled",
        confirmation_status: "pending"
      )
      GoogleCalendar::SyncSession.new(session).call if session.sync_to_google_calendar?

      acknowledgement = send_acknowledgement(reschedule_acknowledgement(session), event: "session_rescheduled")
      "#{session.client.name} rescheduled #{session.title} to #{session.start_time.in_time_zone(task.user.time_zone).strftime("%b %-d at %H:%M")}#{acknowledgement ? ' and acknowledged' : ''}."
    end

    def create_client_note!(body)
      client = context[:client]
      raise "Cannot create a client note without a client." if client.blank?

      task.user.messages.create!(
        client: client,
        session: context[:session],
        ai_task: task,
        direction: "internal_note",
        channel: Client::WHATSAPP_CHANNEL,
        status: "sent",
        subject: "AI note",
        body: body,
        sent_at: Time.current,
        metadata: message_metadata.merge("event" => "client_note")
      )
      "Created AI note for #{client.name}."
    end

    def alert_professional!(body)
      alert = task.user.ai_alerts.create!(
        client: context[:client],
        session: context[:session],
        ai_task: task,
        severity: "medium",
        title: "Client follow-up needed",
        body: body,
        metadata: {
          "automation_key" => task.automation_key,
          "trigger_event" => task.trigger_event
        }.compact
      )
      send_acknowledgement(owner_review_acknowledgement, event: "professional_alerted") if task.trigger_event == "client_replied"
      "Created AI alert ##{alert.id}."
    end

    def schedule_follow_up!(follow_up_at)
      scheduled_for = Time.zone.parse(follow_up_at.to_s)
      raise "Follow-up time is invalid." if scheduled_for.blank?

      follow_up = task.user.ai_tasks.create!(
        client: context[:client],
        session: context[:session],
        trigger_event: task.trigger_event,
        automation_key: task.automation_key,
        scheduled_for: scheduled_for,
        context_data: task.context_data.merge("source_task_id" => task.id)
      )
      "Scheduled follow-up task ##{follow_up.id}."
    end

    def send_acknowledgement(body, event:)
      return false unless task.trigger_event == "client_replied"
      return false if context[:client].blank?
      return false if body.blank?

      dispatcher.deliver(
        user: task.user,
        client: context[:client],
        session: context[:session],
        body: body,
        ai_task: task,
        metadata: message_metadata.merge("event" => event, "acknowledgement" => true)
      )
      true
    rescue StandardError => error
      Rails.logger.warn("AI acknowledgement skipped for task #{task.id}: #{error.class}: #{error.message}")
      false
    end

    def confirmation_acknowledgement(status)
      if spanish?
        {
          "confirmed" => "Gracias, quedo confirmada tu sesion.",
          "maybe" => "Gracias, lo dejo como pendiente y se lo aviso al profesional.",
          "declined" => "Gracias por avisar. Se lo aviso al profesional."
        }.fetch(status)
      else
        {
          "confirmed" => "Thanks, your session is confirmed.",
          "maybe" => "Thanks, I’ll keep it as tentative and let the professional know.",
          "declined" => "Thanks for letting us know. I’ll notify the professional."
        }.fetch(status)
      end
    end

    def payment_acknowledgement(session)
      if spanish?
        "Gracias, marque como pagada la sesion #{session.title}."
      else
        "Thanks, I marked #{session.title} as paid."
      end
    end

    def owner_review_acknowledgement
      if spanish?
        "Gracias, voy a pasarle esto al profesional para que lo revise."
      else
        "Thanks, I’ll pass this to the professional for review."
      end
    end

    def reschedule_acknowledgement(session)
      formatted_time = session.start_time.in_time_zone(task.user.time_zone).strftime("%A %-d %B, %H:%M")
      if spanish?
        "Listo, movi tu sesion a #{formatted_time}. Queda pendiente de confirmacion final."
      else
        "Done, I moved your session to #{formatted_time}. It is pending final confirmation."
      end
    end

    def parse_time_in_user_zone(value)
      Time.use_zone(task.user.time_zone) { Time.zone.parse(value.to_s) }
    rescue ArgumentError
      nil
    end

    def spanish?
      task.user.locale.to_s.start_with?("es")
    end

    def message_metadata
      {
        "source" => "ai",
        "automation_key" => task.automation_key,
        "trigger_event" => task.trigger_event
      }.compact
    end
  end
end
