require "digest"

module Ai
  class IdempotencyKey
    def self.for_task(user:, client:, session:, automation_key:, trigger_event:, channel:, scheduled_window:)
      workspace_id = user.studio_id || user.id
      raw = [
        trigger_event,
        "workspace_#{workspace_id}",
        "professional_#{user.id}",
        "client_#{client&.id || 'none'}",
        "session_#{session&.id || 'none'}",
        automation_key,
        scheduled_window,
        channel
      ].join(":")
      "#{raw}:#{Digest::SHA256.hexdigest(raw).first(16)}"
    end

    def self.scheduled_window(session)
      session&.start_time&.utc&.strftime("session_%Y%m%dT%H%M") || Time.current.utc.strftime("event_%Y%m%dT%H")
    end
  end
end
