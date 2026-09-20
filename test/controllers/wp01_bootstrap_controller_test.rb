require "test_helper"

class Wp01BootstrapControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.destroy_all
    User.destroy_all
    Room.destroy_all
    Rails.cache.clear
    @old_secret = ENV["CAMPFIRE_BOOTSTRAP_SECRET"]
    @secret = ENV["CAMPFIRE_BOOTSTRAP_SECRET"] = SecureRandom.hex(32)
    @user = { name: "Operator", email_address: "operator@example.test", password: "strong-test-password" }
  end

  teardown do
    ENV["CAMPFIRE_BOOTSTRAP_SECRET"] = @old_secret
  end

  test "secret is required and never rendered into the setup form" do
    get first_run_url
    assert_response :success
    assert_select "input[name=bootstrap_secret][type=password]"
    assert_select "input[name=bootstrap_secret][value]", count: 0
    assert_includes response.headers["Cache-Control"], "no-store"
    refute_includes response.body, @secret
    post first_run_url, params: { user: @user }
    assert_response :forbidden
    assert_equal 0, Account.count
  end

  test "query string and array values are not bootstrap authority" do
    post first_run_url(bootstrap_secret: @secret), params: { user: @user }
    assert_response :forbidden
    post first_run_url, params: { user: @user, bootstrap_secret: [ @secret ] }
    assert_response :forbidden
    assert_equal 0, Account.count
  end

  test "correct secret creates one administrator and cannot provision again" do
    post first_run_url, params: { user: @user, bootstrap_secret: @secret }
    assert_redirected_to root_url
    assert_equal 1, Account.count
    assert_equal 1, User.where(role: :administrator).count
    assert parsed_cookies.signed[:session_token]
    post first_run_url, params: { user: @user.merge(email_address: "other@example.test"), bootstrap_secret: @secret }
    assert_equal 1, Account.count
    assert_equal 1, User.where(role: :administrator).count
  end

  test "invalid administrator rolls back account and allows correction" do
    post first_run_url, params: { user: @user.merge(name: ""), bootstrap_secret: @secret }
    assert_response :unprocessable_entity
    assert_equal 0, Account.count
    assert_equal 0, User.count
    refute_includes response.body, @secret
    post first_run_url, params: { user: @user, bootstrap_secret: @secret }
    assert_redirected_to root_url
    assert_equal 1, Account.count
  end

  test "invalid setup attempts are rate limited before secret verification" do
    # The macro captures this store when the controller class loads.
    FirstRunsController.cache_store.stubs(:increment).returns(*(1..11).to_a)
    10.times do
      post first_run_url, params: { user: @user, bootstrap_secret: "incorrect" }
      assert_response :forbidden
    end
    post first_run_url, params: { user: @user, bootstrap_secret: "incorrect" }
    assert_response :too_many_requests
    assert_equal 0, Account.count
  end

  test "missing configured secret fails closed" do
    ENV["CAMPFIRE_BOOTSTRAP_SECRET"] = ""
    post first_run_url, params: { user: @user, bootstrap_secret: @secret }
    assert_response :forbidden
    assert_equal 0, Account.count
  end
end
