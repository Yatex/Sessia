module GoogleCalendar
  class SyncUpcomingSessions
    def initialize(user)
      @user = user
    end

    def call
      synced = 0
      failed = 0

      upcoming_sessions.find_each do |session_record|
        session_record.update_column(:sync_to_google_calendar, true) unless session_record.sync_to_google_calendar?
        if SyncSession.new(session_record).call
          synced += 1
        else
          failed += 1
        end
      end

      user.calendar_connection&.update_columns(last_synced_at: Time.current, updated_at: Time.current)
      { synced: synced, failed: failed }
    end

    private

    attr_reader :user

    def upcoming_sessions
      user.sessions
          .includes(:client)
          .where("start_time >= ?", Time.current.beginning_of_day)
          .where.not(status: [:cancelled, :no_show])
          .order(:start_time)
    end
  end
end
