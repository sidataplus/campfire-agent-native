require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/campfire/deployment"

class DeploymentTest < Minitest::Test
  def setup
    key = OpenSSL::PKey::EC.generate("prime256v1")
    @env = {
      "CAMPFIRE_PUBLIC_URL" => "https://chat.example.test",
      "CAMPFIRE_PROXY_MODE" => "railway",
      "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "CAMPFIRE_RECOVERY_EPOCH" => SecureRandom.hex(32),
      "CAMPFIRE_BOOTSTRAP_SECRET" => SecureRandom.hex(32),
      "VAPID_PUBLIC_KEY" => Base64.urlsafe_encode64(key.public_key.to_octet_string(:uncompressed), padding: false),
      "VAPID_PRIVATE_KEY" => Base64.urlsafe_encode64(key.private_key.to_s(2).rjust(32, "\0"), padding: false)
    }
  end

  def test_valid_environment
    assert_same @env, Campfire::Deployment.new(@env).validate!.env
  end

  def test_required_runtime_secrets
    %w[ SECRET_KEY_BASE CAMPFIRE_RECOVERY_EPOCH VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY ].each do |name|
      assert_raises(Campfire::Deployment::Invalid, name) { Campfire::Deployment.new(@env.reject { |key, _| key == name }).validate! }
    end
  end

  def test_bootstrap_can_be_removed_after_setup
    @env.delete("CAMPFIRE_BOOTSTRAP_SECRET")
    assert Campfire::Deployment.new(@env).validate!
    @env["CAMPFIRE_BOOTSTRAP_SECRET"] = "short"
    assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).validate! }
  end

  def test_origin_restrictions
    [ "http://chat.example.test", "https://user:secret@chat.example.test", "https://chat.example.test/path",
      "https://chat.example.test?secret=x", "https://chat.example.test#x", "https://bad..example.test",
      "https://chat.example.test:99999", "", "not a URL" ].each do |url|
      assert_raises(Campfire::Deployment::Invalid, url) { Campfire::Deployment.new(@env.merge("CAMPFIRE_PUBLIC_URL" => url)).validate! }
    end
  end

  def test_native_flags_fail_closed
    Campfire::Deployment::FLAGS.each do |flag|
      %w[ true 1 yes FALSE ].each do |value|
        assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge(flag => value)).validate! }
      end
    end
  end

  def test_unsafe_or_conflicting_environment
    %w[ DISABLE_SSL TLS_DOMAIN THRUSTER_TLS_DOMAIN SECRET_KEY_BASE_DUMMY DATABASE_URL ].each do |key|
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge(key => "1")).validate! }
    end
    assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge("REDIS_URL" => "redis://remote/0")).validate! }
    assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge("SKIP_TELEMETRY" => "false")).validate! }
  end

  def test_proxy_mode_must_be_explicit
    [ nil, "", "direct", "arbitrary" ].each do |mode|
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge("CAMPFIRE_PROXY_MODE" => mode)).validate! }
    end
  end

  def test_port_validation
    %w[ 80 443 -1 65536 x 3001 6379 ].each do |port|
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge("PORT" => port)).validate! }
    end
  end

  def test_listener_survives_thruster_rewriting_child_port
    @env["PORT"] = "8765"
    deployment = Campfire::Deployment.new(@env).apply!
    assert_equal "8765", @env["THRUSTER_HTTP_PORT"]
    assert_equal "3001", @env["THRUSTER_TARGET_PORT"]
    @env["PORT"] = "3001"
    deployment.validate!
    assert_equal "8765", @env["CAMPFIRE_LISTEN_PORT"]
  end

  def test_small_group_defaults_and_no_telemetry
    Campfire::Deployment.new(@env).apply!
    assert_equal "1", @env["WEB_CONCURRENCY"]
    assert_equal "1", @env["JOB_CONCURRENCY"]
    assert_equal "true", @env["SKIP_TELEMETRY"]
    assert_equal "false", @env["THRUSTER_LOG_REQUESTS"]
    assert_equal "true", @env["THRUSTER_GZIP_COMPRESSION_DISABLE_ON_AUTH"]
    assert_equal "false", @env["CAMPFIRE_AGENT_DISPATCH_ENABLED"]
  end

  def test_concurrency_is_bounded
    %w[ 0 9 -1 twenty ].each do |count|
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge("WEB_CONCURRENCY" => count)).validate! }
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env.merge("JOB_CONCURRENCY" => count)).validate! }
    end
  end

  def test_vapid_pair_is_mathematically_checked
    @env["VAPID_PRIVATE_KEY"] = Base64.urlsafe_encode64("\0" * 31 + "\1", padding: false)
    assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).validate! }
    @env["VAPID_PRIVATE_KEY"] = "%%%"
    assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).validate! }
  end

  def test_errors_do_not_echo_secret_values
    @env["SECRET_KEY_BASE"] = "DO-NOT-LOG-ME"
    error = assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).validate! }
    refute_includes error.message, "DO-NOT-LOG-ME"
  end

  def test_persistent_secret_fingerprints_allow_restart_but_not_regeneration
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "storage"))
      deployment = Campfire::Deployment.new(@env).validate!
      2.times { deployment.check_storage!(root) }
      pins = File.read(File.join(root, "storage/.campfire-secret-fingerprints.json"))
      refute_includes pins, @env["SECRET_KEY_BASE"]
      assert File.directory?(File.join(root, "storage/db"))
      @env["SECRET_KEY_BASE"] = SecureRandom.hex(64)
      assert_raises(Campfire::Deployment::Invalid) { deployment.check_storage!(root) }
    end
  end

  def test_recovery_epoch_and_bootstrap_are_not_pinned_instance_secrets
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "storage"))
      deployment = Campfire::Deployment.new(@env).validate!
      deployment.check_storage!(root)
      @env["CAMPFIRE_RECOVERY_EPOCH"] = SecureRandom.hex(32)
      @env.delete("CAMPFIRE_BOOTSTRAP_SECRET")
      assert deployment.check_storage!(root)
    end
  end

  def test_symlink_storage_is_rejected
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "outside"))
      File.symlink(File.join(root, "outside"), File.join(root, "storage"))
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).check_storage!(root) }
    end
  end

  def test_symlink_storage_child_is_rejected
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "storage"))
      File.symlink(root, File.join(root, "storage/db"))
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).check_storage!(root) }
    end
  end

  def test_symlink_fingerprint_is_rejected_without_modifying_target
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "storage"))
      target = File.join(root, "target")
      File.write(target, "unchanged")
      File.symlink(target, File.join(root, "storage/.campfire-secret-fingerprints.json"))
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).check_storage!(root) }
      assert_equal "unchanged", File.read(target)
    end
  end

  def test_corrupt_fingerprint_fails_closed
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "storage"))
      File.write(File.join(root, "storage/.campfire-secret-fingerprints.json"), "broken")
      assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new(@env).check_storage!(root) }
    end
  end
end
