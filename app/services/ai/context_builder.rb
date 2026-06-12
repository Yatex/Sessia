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
        billing_context: serialize_billing_context,
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
        payment_instructions: user.payment_instructions.presence,
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
        payment_link: session.main_charge&.payment_url.presence,
        due_date: session.main_charge&.due_date&.iso8601,
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

    def serialize_billing_context
      return if client.blank?

      charges = user.charges.where(client: client).includes(:session, :payments)
      unpaid_charges = charges.select { |charge| charge.pending? || charge.partially_paid? || charge.overdue? }
      next_unpaid_charge = unpaid_charges
        .select { |charge| charge.session.blank? || charge.session.start_time >= 7.days.ago }
        .min_by { |charge| charge.session&.start_time || charge.due_date || Date.current }
      last_payment = user.payments.where(client: client).recent.first

      {
        current_balance_cents: unpaid_charges.sum { |charge| [charge.amount_cents - charge.approved_payment_total_cents, 0].max },
        credit_balance_cents: client.credit_balance_cents,
        unpaid_sessions: unpaid_charges.filter_map { |charge| serialize_charge_session(charge) },
        overdue_charges: charges.select(&:overdue?).map { |charge| serialize_charge(charge) },
        next_session_payment_status: session&.payment_status || next_unpaid_charge&.status,
        payment_link_for_next_unpaid_session: next_unpaid_charge&.payment_url.presence,
        last_payment_status: last_payment&.status
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

    def serialize_charge_session(charge)
      return serialize_charge(charge) if charge.session.blank?

      {
        session_id: charge.session_id.to_s,
        title: charge.session.title,
        starts_at: charge.session.start_time.iso8601,
        payment_status: charge.session.payment_status,
        amount_cents: charge.amount_cents,
        remaining_cents: [charge.amount_cents - charge.approved_payment_total_cents, 0].max,
        currency: charge.currency,
        due_date: charge.due_date&.iso8601,
        payment_link: charge.payment_url.presence
      }.compact
    end

    def serialize_charge(charge)
      {
        charge_id: charge.id.to_s,
        status: charge.status,
        amount_cents: charge.amount_cents,
        remaining_cents: [charge.amount_cents - charge.approved_payment_total_cents, 0].max,
        currency: charge.currency,
        due_date: charge.due_date&.iso8601,
        payment_link: charge.payment_url.presence
      }.compact
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
