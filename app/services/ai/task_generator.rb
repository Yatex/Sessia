module Ai
  class TaskGenerator
    DUPLICATE_WINDOW = 36.hours

    def initialize(users: User.all, now: Time.current)
      @users = users
      @now = now
    end

    def call
      generated = []
      user_scope.find_each do |user|
        setting = user.ai_setting || user.create_ai_setting!
        generated.concat(generate_for_user(user, setting))
      end
      generated
    end

    private

    attr_reader :users, :now

    def user_scope
      users.respond_to?(:find_each) ? users : User.where(id: Array(users).map(&:id))
    end

    def generate_for_user(user, setting)
      tasks = []
      tasks.concat(confirm_session_tasks(user)) if setting.confirm_sessions?
      tasks.concat(reminder_tasks(user)) if setting.send_pre_session_reminders?
      tasks.concat(no_response_tasks(user)) if setting.follow_up_no_response?
      tasks.concat(feedback_tasks(user)) if setting.ask_feedback_after_sessions?
      tasks.concat(payment_tasks(user)) if setting.payment_reminders?
      tasks
    end

    def confirm_session_tasks(user)
      user.sessions.includes(:client)
        .where(status: :scheduled)
        .where(confirmation_status: %i[not_requested pending maybe])
        .where(start_time: now..48.hours.from_now(now))
        .filter_map do |session_record|
          create_task_once(
            user: user,
            session: session_record,
            trigger_event: "before_session",
            automation_key: "confirm_session",
            scheduled_for: now,
            context_data: { "purpose" => "initial_confirmation" }
          )
        end
    end

    def reminder_tasks(user)
      user.sessions.includes(:client)
        .where(status: :scheduled, confirmation_status: :confirmed)
        .where(start_time: 15.minutes.from_now(now)..3.hours.from_now(now))
        .filter_map do |session_record|
          create_task_once(
            user: user,
            session: session_record,
            trigger_event: "before_session",
            automation_key: "send_pre_session_reminder",
            scheduled_for: now,
            context_data: { "purpose" => "pre_session_reminder" }
          )
        end
    end

    def no_response_tasks(user)
      user.sessions.includes(:client)
        .where(status: :scheduled, confirmation_status: %i[pending maybe])
        .where(start_time: now..7.days.from_now(now))
        .filter_map do |session_record|
          next unless stale_confirmation_request?(session_record)

          create_task_once(
            user: user,
            session: session_record,
            trigger_event: "no_response_window_reached",
            automation_key: "follow_up_no_response",
            scheduled_for: now,
            context_data: { "purpose" => "confirmation_no_response" }
          )
        end
    end

    def feedback_tasks(user)
      user.sessions.includes(:client)
        .where(status: :completed)
        .where(end_time: 24.hours.ago(now)..30.minutes.ago(now))
        .filter_map do |session_record|
          create_task_once(
            user: user,
            session: session_record,
            trigger_event: "after_session",
            automation_key: "ask_feedback_after_session",
            scheduled_for: now,
            context_data: { "purpose" => "post_session_feedback" }
          )
        end
    end

    def payment_tasks(user)
      user.sessions.includes(:client)
        .where(payment_status: %i[pending overdue])
        .where("price_cents > 0")
        .where(start_time: 7.days.ago(now)..14.days.from_now(now))
        .filter_map do |session_record|
          create_task_once(
            user: user,
            session: session_record,
            trigger_event: "payment_due",
            automation_key: "payment_reminder",
            scheduled_for: now,
            context_data: { "purpose" => "session_payment_reminder" }
          )
        end
    end

    def stale_confirmation_request?(session_record)
      last_outbound = session_record.messages
        .where(direction: Message.directions[:outbound])
        .where("metadata ->> 'automation_key' IN (?)", %w[confirm_session follow_up_no_response])
        .order(created_at: :desc)
        .first
      return false if last_outbound.blank? || last_outbound.created_at > 6.hours.ago(now)

      session_record.messages
        .where(direction: Message.directions[:inbound])
        .where("created_at > ?", last_outbound.created_at)
        .none?
    end

    def create_task_once(user:, session:, trigger_event:, automation_key:, scheduled_for:, context_data:)
      duplicate_scope = user.ai_tasks.where(
        session: session,
        trigger_event: trigger_event,
        automation_key: automation_key
      ).where(status: %w[pending processing completed])

      return if duplicate_scope.where("created_at >= ?", DUPLICATE_WINDOW.ago(now)).exists?

      user.ai_tasks.create!(
        client: session.client,
        session: session,
        trigger_event: trigger_event,
        automation_key: automation_key,
        scheduled_for: scheduled_for,
        context_data: context_data
      )
    end
  end
end
