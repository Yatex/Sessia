module Ai
  class ContextBuilder
    RECENT_MESSAGE_LIMIT = 24

    def initialize(task:)
      @task = task
      @user = task.user
      @session = task.session
      @client = task.client || task.session&.client
      @payment_record = resolve_payment_record
    end

    def call
      recent_messages = serialize_recent_messages
      payload = {
        trigger_event: task.trigger_event,
        professional: serialize_professional,
        client: serialize_client,
        session: serialize_session,
        payment_record: serialize_payment_record,
        recent_messages: recent_messages,
        availability_options: serialize_availability_options,
        task_context: task.context_data,
        current_time: Time.current.iso8601,
        timezone: user.time_zone
      }

      {
        task: task,
        user: user,
        client: client,
        session: session,
        payment_record: payment_record,
        recent_messages: recent_messages,
        payload: payload
      }
    end

    private

    attr_reader :task, :user, :client, :session, :payment_record

    def serialize_professional
      ai_setting = user.ai_setting
      {
        id: user.id.to_s,
        name: user.name,
        locale: user.locale,
        time_zone: user.time_zone,
        instructions: ai_setting&.instructions.presence
      }.compact
    end

    def serialize_client
      return if client.blank?

      {
        id: client.id.to_s,
        name: client.name,
        email: client.email.presence,
        phone: client.phone.presence,
        notes: client.notes.presence
      }.compact
    end

    def serialize_session
      return if session.blank?

      {
        id: session.id.to_s,
        title: session.title,
        starts_at: session.start_time.iso8601,
        ends_at: session.end_time.iso8601,
        status: session.status,
        confirmation_status: session.confirmation_status,
        payment_status: session.payment_status,
        price_cents: session.price_cents.to_i,
        currency: session.currency,
        notes: session.notes.presence
      }.compact
    end

    def serialize_payment_record
      return if payment_record.blank?

      {
        id: payment_record.id.to_s,
        status: payment_record.status,
        amount_cents: payment_record.amount_cents.to_i,
        currency: payment_record.currency,
        due_on: payment_record.due_on&.iso8601,
        paid_at: payment_record.paid_at&.iso8601
      }.compact
    end

    def serialize_recent_messages
      scope = user.messages
      scope = scope.where(client: client) if client.present?
      scope = scope.where(session: session).or(scope.where(session_id: nil)) if session.present? && client.present?
      scope.recent_first.limit(RECENT_MESSAGE_LIMIT).to_a.reverse.map do |message|
        {
          id: message.id.to_s,
          direction: message.direction,
          author_role: author_role_for(message),
          channel: message.channel,
          subject: message.subject.presence,
          body: message.body.to_s,
          occurred_at: (message.sent_at || message.created_at).iso8601
        }.compact
      end
    end

    def serialize_availability_options
      return [] if session.blank?

      duration = session.duration_minutes.positive? ? session.duration_minutes : 50
      Availability::FreeSlotFinder.new(user).call(
        from: Time.current,
        days: 21,
        duration_minutes: duration,
        limit: 8,
        exclude_session: session
      ).map.with_index(1) do |slot, index|
        {
          id: index.to_s,
          label: slot.label,
          starts_at: slot.starts_at.iso8601,
          ends_at: slot.ends_at.iso8601
        }
      end
    end

    def author_role_for(message)
      return "client" if message.inbound?
      return "system" if message.internal_note?
      return "assistant" if message.ai_task_id.present? || message.metadata.to_h["source"] == "ai"

      "professional"
    end

    def resolve_payment_record
      return if session.blank?

      session.payment_records.recent.first ||
        user.payment_records.where(client: session.client, session: session).recent.first
    end
  end
end
