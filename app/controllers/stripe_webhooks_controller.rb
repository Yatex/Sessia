class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    event = StripeBilling.construct_event(
      payload: request.raw_post,
      signature: request.headers["Stripe-Signature"]
    )

    StripeBilling.sync_event(event)
    head :ok
  rescue Stripe::SignatureVerificationError
    head :unauthorized
  rescue JSON::ParserError
    head :bad_request
  end
end
