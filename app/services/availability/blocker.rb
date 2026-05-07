module Availability
  class Blocker
    Result = Struct.new(:schedule_block, :affected_sessions, keyword_init: true)

    def initialize(user:, attributes:)
      @user = user
      @attributes = attributes
    end

    def call
      ScheduleBlock.transaction do
        block = user.schedule_blocks.create!(attributes)
        sessions = overlapping_sessions(block).to_a
        sessions.each { |session_record| cancel_and_queue_rebooking!(session_record, block) }

        Result.new(schedule_block: block, affected_sessions: sessions)
      end
    end

    private

    attr_reader :user, :attributes

    def overlapping_sessions(block)
      user.sessions.includes(:client)
        .where.not(status: [Session.statuses.fetch("cancelled"), Session.statuses.fetch("no_show")])
        .where("start_time < ? AND end_time > ?", block.ends_at, block.starts_at)
        .chronological
    end

    def cancel_and_queue_rebooking!(session_record, block)
      previous_start_time = session_record.start_time
      previous_end_time = session_record.end_time

      session_record.update!(
        status: "cancelled",
        confirmation_status: "declined"
      )

      user.ai_tasks.create!(
        client: session_record.client,
        session: session_record,
        trigger_event: "schedule_blocked",
        automation_key: "blocked_time_rebooking",
        scheduled_for: Time.current,
        context_data: {
          "schedule_block_id" => block.id,
          "previous_start_time" => previous_start_time.iso8601,
          "previous_end_time" => previous_end_time.iso8601
        }
      )
    end
  end
end
