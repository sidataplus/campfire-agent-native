require "minitest/autorun"
require "securerandom"
require_relative "../../lib/campfire/bootstrap"

class BootstrapSecretTest < Minitest::Test
  def setup
    @old_secret = ENV["CAMPFIRE_BOOTSTRAP_SECRET"]
    @secret = ENV["CAMPFIRE_BOOTSTRAP_SECRET"] = SecureRandom.hex(32)
  end

  def teardown
    ENV["CAMPFIRE_BOOTSTRAP_SECRET"] = @old_secret
  end

  def test_exact_secret_only
    assert Campfire::Bootstrap.valid?(@secret)
    refute Campfire::Bootstrap.valid?(@secret.reverse)
    refute Campfire::Bootstrap.valid?(" #{@secret}")
  end

  def test_invalid_types_sizes_and_missing_secret
    [ nil, {}, [], 123, "", "x" * 4097 ].each { |value| refute Campfire::Bootstrap.valid?(value) }
    ENV.delete("CAMPFIRE_BOOTSTRAP_SECRET")
    refute Campfire::Bootstrap.valid?(@secret)
  end

  def test_short_configuration_is_not_accepted
    ENV["CAMPFIRE_BOOTSTRAP_SECRET"] = "short"
    refute Campfire::Bootstrap.configured?
    refute Campfire::Bootstrap.valid?("short")
  end
end
