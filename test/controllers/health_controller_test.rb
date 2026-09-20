require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "liveness does not expose configuration or require a login" do
    get "/healthz"
    assert_response :success
    assert_equal({ "status" => "ok" }, response.parsed_body)
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "readiness succeeds only when dependencies are available" do
    Campfire::Readiness.stubs(:ready?).returns(true)
    get "/readyz"
    assert_response :success
    assert_equal({ "status" => "ready" }, response.parsed_body)
  end

  test "failed readiness is generic and uncacheable" do
    Campfire::Readiness.stubs(:ready?).returns(false)
    get "/readyz"
    assert_response :service_unavailable
    assert_equal({ "status" => "unavailable" }, response.parsed_body)
    assert_includes response.headers["Cache-Control"], "no-store"
  end
end
