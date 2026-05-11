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
end
