module Admin
  class AiMessagesController < Admin::BaseController
    TASK_LIMIT = 80
    MESSAGE_LIMIT = 80

    def index
      @filters = filter_params.to_h
      @metrics = message_metrics
      @tasks = filtered_tasks.limit(TASK_LIMIT)
      @failed_messages = failed_messages.limit(MESSAGE_LIMIT)
      @open_alerts = AiAlert.includes(:user, :client, :session).status_open.recent_first.limit(30)
    end

    def show
      @task = AiTask.includes(:user, :client, :session, :messages, :delivery_attempts).find(params[:id])
      @trace = @task.ai_traces.order(created_at: :desc).first
    end

    private

    def filter_params
      params.permit(:query, :task_status, :message_status, :trigger, :decision_status,
        :validation_status, :execution_status, :delivery_status, :workspace,
        :channel, :date_from, :date_to, :error_category, :retry, :fallback)
    end

    def message_metrics
      ai_messages = Message.outbound.where.not(ai_task_id: nil)
      {
        recent_tasks: AiTask.where("created_at >= ?", 24.hours.ago).count,
        pending_tasks: AiTask.where(status: %w[pending processing]).count,
        failed_tasks: AiTask.status_failed.count,
        queued_messages: ai_messages.queued.count,
        sent_messages: ai_messages.sent.count,
        failed_messages: ai_messages.failed.count,
        open_alerts: AiAlert.status_open.count
      }
    end

    def filtered_tasks
      scope = AiTask
        .includes(:user, :client, :session, :messages)
        .order(Arel.sql("COALESCE(ai_tasks.processed_at, ai_tasks.scheduled_for) DESC"), created_at: :desc)

      scope = scope.where(status: @filters[:task_status]) if AiTask.statuses.key?(@filters[:task_status])
      %w[trigger_event decision_status validation_status execution_status delivery_status error_category].each do |column|
        key = column == "trigger_event" ? "trigger" : column
        scope = scope.where(column => @filters[key]) if @filters[key].present?
      end
      scope = scope.where(user_id: @filters[:workspace]) if @filters[:workspace].present?
      scope = scope.where("ai_tasks.created_at >= ?", Date.parse(@filters[:date_from]).beginning_of_day) if @filters[:date_from].present?
      scope = scope.where("ai_tasks.created_at <= ?", Date.parse(@filters[:date_to]).end_of_day) if @filters[:date_to].present?
      scope = scope.where("retry_count > 0") if @filters[:retry] == "yes"
      scope = scope.where(retry_count: 0) if @filters[:retry] == "no"
      scope = scope.joins(:ai_traces).where(ai_traces: { fallback_used: @filters[:fallback] == "yes" }) if @filters[:fallback].in?(%w[yes no])
      scope = scope.joins(:messages).where(messages: { channel: @filters[:channel] }).distinct if @filters[:channel].present?
      scope = filter_by_query(scope, @filters[:query]) if @filters[:query].present?
      scope = filter_by_message_status(scope, @filters[:message_status]) if @filters[:message_status].present?
      scope
    rescue Date::Error
      scope
    end

    def failed_messages
      Message
        .outbound
        .failed
        .includes(:user, :client, :session, :ai_task)
        .where.not(ai_task_id: nil)
        .recent_first
    end

    def filter_by_query(scope, query)
      escaped = "%#{User.sanitize_sql_like(query)}%"
      scope
        .left_joins(:user, :client)
        .where("users.email ILIKE :query OR users.name ILIKE :query OR clients.name ILIKE :query OR clients.email ILIKE :query", query: escaped)
    end

    def filter_by_message_status(scope, status)
      case status
      when "sent", "queued", "failed"
        scope.where(id: Message.outbound.where(status: Message.statuses[status]).where.not(ai_task_id: nil).select(:ai_task_id))
      when "not_sent"
        scope.where.not(id: Message.outbound.where.not(ai_task_id: nil).select(:ai_task_id))
      else
        scope
      end
    end
  end
end
