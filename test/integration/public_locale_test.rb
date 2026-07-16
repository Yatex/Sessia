require "test_helper"

class PublicLocaleTest < ActionDispatch::IntegrationTest
  test "guest can switch landing page language" do
    get root_url
    assert_response :success
    assert_match "Sign in", response.body

    patch locale_url, params: { locale: "es" }
    assert_redirected_to root_url

    follow_redirect!
    assert_response :success
    assert_match "Ingresar", response.body
    assert_match "Hasta 10 clientes activos", response.body
  end

  test "public legal pages are visible from sign up" do
    get sign_up_url
    assert_response :success
    assert_select "a[href='#{terms_path}']", text: "Terms"
    assert_select "a[href='#{privacy_path}']", text: "Privacy Policy"

    get terms_url
    assert_response :success
    assert_select "h1", text: "Terms of Service"
    assert_match "Google Calendar and Third-Party Services", response.body

    get privacy_url
    assert_response :success
    assert_select "h1", text: "Privacy Policy"
    assert_match "Google Calendar Data", response.body
  end

  test "authenticated dashboard shows language switcher and spanish calendar labels" do
    user = User.create!(name: "Locale Pro", email: "locale-pro@example.com", password: "password123", locale: "es")
    post sign_in_url, params: { email: user.email, password: "password123" }

    get dashboard_url

    assert_response :success
    assert_select ".language-switcher", text: "EN"
    assert_match "Semana", response.body
    assert_match "Mes", response.body
    assert_match "Anterior", response.body
    assert_match "Siguiente", response.body
    assert_match "Hora", response.body
    assert_match "No disponible", response.body
    assert_select "a.sidebar-status-card[href='#{settings_path}#professional-whatsapp']", text: /Configurar WhatsApp profesional/
    assert_no_match "Previous", response.body
    assert_no_match "Unavailable", response.body

    get settings_url(anchor: "professional-whatsapp")
    assert_response :success
    assert_select "section#professional-whatsapp"
  end
end
