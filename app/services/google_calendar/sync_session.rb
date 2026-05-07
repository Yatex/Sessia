module GoogleCalendar
  class SyncSession
    def initialize(session_record)
      @session_record = session_record
    end

    def call
      return false unless connection&.connected?

      event = Client.new(connection).upsert_session_event(session_record)
      session_record.update_columns(
        sync_to_google_calendar: true,
        google_calendar_event_id: event.fetch("id"),
        google_calendar_synced_at: Time.current,
        google_calendar_sync_error: nil,
        updated_at: Time.current
      )
      true
    rescue Client::Error => error
      session_record.update_columns(
        google_calendar_sync_error: error.message.truncate(500),
        updated_at: Time.current
      )
      connection&.update_columns(status: CalendarConnection.statuses[:errored], error_message: error.message.truncate(500), updated_at: Time.current)
      false
    end

    private

    attr_reader :session_record

    def connection
      @connection ||= session_record.user.calendar_connection
    end
  end
end
