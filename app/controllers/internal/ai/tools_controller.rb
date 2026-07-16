module Internal
  module Ai
    class ToolsController < ActionController::Base
      protect_from_forgery with: :null_session
      rescue_from ActionController::InvalidAuthenticityToken do |error|
        render json: { error: { code: "unauthorized", message: error.message } }, status: :unauthorized
      end

      def show
        authenticate_service!
        result = ::Ai::Grounded::ToolRunner.new(
          context_token: params.require(:context_token),
          tool_name: params.require(:tool_name)
        ).call
        render json: result
      rescue ActionController::ParameterMissing, ArgumentError, ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature => error
        render json: { error: { code: "invalid_tool_request", message: error.message } }, status: :unprocessable_entity
      end

      private

      def authenticate_service!
        expected = ENV["SESSIA_AI_TOOL_SECRET"].to_s
        actual = request.headers["X-Sessia-AI-Tool-Secret"].to_s
        raise ActionController::InvalidAuthenticityToken, "AI tool service is not authorized." if expected.blank? || actual.blank?
        raise ActionController::InvalidAuthenticityToken, "AI tool service is not authorized." unless ActiveSupport::SecurityUtils.secure_compare(actual, expected)
      end
    end
  end
end
