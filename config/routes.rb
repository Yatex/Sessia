Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
  get "terms", to: "home#terms", as: :terms
  get "privacy", to: "home#privacy", as: :privacy

  get "sign-up", to: "sign_ups#new", as: :sign_up
  post "sign-up", to: "sign_ups#create"
  get "sign-in", to: "user_sessions#new", as: :sign_in
  post "sign-in", to: "user_sessions#create"
  delete "sign-out", to: "user_sessions#destroy", as: :sign_out
  get "auth/google", to: "google_auth#connect", as: :google_auth
  get "auth/google/callback", to: "google_auth#callback", as: :google_auth_callback
  patch "locale", to: "locales#update", as: :locale

  get "password-reset", to: "password_resets#new", as: :new_password_reset
  post "password-reset", to: "password_resets#create", as: :password_resets
  get "password-reset/:token/edit", to: "password_resets#edit", as: :edit_password_reset
  patch "password-reset/:token", to: "password_resets#update", as: :password_reset

  get "dashboard", to: "dashboard#index", as: :dashboard
  post "dashboard/schedule-block", to: "dashboard#schedule_block", as: :dashboard_schedule_block
  delete "dashboard/schedule-blocks/:block_id", to: "dashboard#destroy_schedule_block", as: :destroy_dashboard_schedule_block
  resources :clients do
    resource :billing_profile, only: :update, controller: :client_billing_profiles
  end
  resources :sessions do
    patch :mark_paid, on: :member
    post :generate_payment_link, on: :member
    post :regenerate_payment_link, on: :member
    post :record_manual_payment, on: :member
    patch :waive_payment, on: :member
    patch :cancel_charge, on: :member
    post :sync_google_calendar, on: :member
  end
  resource :ai_assistant, controller: :ai_settings, only: %i[show update], path: "ai-assistant" do
    post :run
  end
  get "payments", to: "payments#index", as: :payments

  resource :subscription, only: :show, controller: :billing, path: "subscriptions" do
    post :checkout
    post :portal
    get :success
  end
  get "billing", to: redirect("/subscriptions")

  get "analytics", to: "reports#index", as: :analytics
  get "reports", to: redirect("/analytics")

  namespace :admin do
    root to: "analytics#index"
    resources :users, only: :index do
      post :extend_subscription, on: :member
      patch :role, action: :update_role, on: :member
    end
    get "analytics", to: "analytics#index", as: :analytics
    get "ai-messages", to: "ai_messages#index", as: :ai_messages
  end

  resource :settings, only: %i[show update] do
    patch :availability
    patch :professional_whatsapp
    post :password_reset
  end
  namespace :payment_accounts do
    resource :mercado_pago, only: [], path: "mercado-pago", controller: "mercado_pago" do
      get :connect
      get :callback
      delete :disconnect
    end
  end
  resource :google_calendar,
           controller: :google_calendar_connections,
           only: [],
           path: "google-calendar" do
    get :connect
    get :callback
    patch :settings, action: :update
    post :sync
    delete :disconnect
  end

  get "client-link/:token", to: "client_portals#show", as: :client_portal
  post "client-link/:token/messages", to: "client_portal_messages#create", as: :client_portal_messages

  post "stripe/webhook", to: "stripe_webhooks#create", as: :stripe_webhook
  post "webhooks/mercado_pago", to: "webhooks/mercado_pago#create", as: :mercado_pago_webhook
  post "webhooks/twilio/whatsapp", to: "twilio_whatsapp_webhooks#create", as: :twilio_whatsapp_webhook
end
