require "base64"
require "digest"
require "fileutils"
require "json"
require "openssl"
require "securerandom"
require "uri"

module Campfire
  class Deployment
    class Invalid < StandardError; end
    HEALTH_PATHS = %w[ /up /healthz /readyz ].freeze
    MODES = %w[ railway external ].freeze
    FLAGS = %w[ CAMPFIRE_AGENT_ENABLED CAMPFIRE_AGENT_DISPATCH_ENABLED ].freeze
    PINNED_SECRETS = %w[ SECRET_KEY_BASE VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY ].freeze
    attr_reader :env

    def initialize(env = ENV)
      @env = env
    end

    def self.asset_build?
      ENV["SECRET_KEY_BASE_DUMMY"] == "1" && defined?(Rake) && Rake.application.top_level_tasks == [ "assets:precompile" ]
    end

    def public_uri
      URI.parse(env.fetch("CAMPFIRE_PUBLIC_URL", ""))
    rescue URI::InvalidURIError
      raise Invalid, "CAMPFIRE_PUBLIC_URL must be an HTTPS origin"
    end

    def validate!
      raise Invalid, "CAMPFIRE_PROXY_MODE must be railway or external" unless MODES.include?(env["CAMPFIRE_PROXY_MODE"])
      uri = public_uri
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && [ "", "/" ].include?(uri.path)
        raise Invalid, "CAMPFIRE_PUBLIC_URL must be an HTTPS origin without credentials, path, query or fragment"
      end
      raise Invalid, "CAMPFIRE_PUBLIC_URL must use a DNS hostname" unless uri.host.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/) && !uri.host.include?("..")
      raise Invalid, "CAMPFIRE_PUBLIC_URL has an invalid port" unless (1..65535).cover?(uri.port)
      %w[ DISABLE_SSL TLS_DOMAIN THRUSTER_TLS_DOMAIN SECRET_KEY_BASE_DUMMY DATABASE_URL ].each do |key|
        raise Invalid, "#{key} is incompatible with this deployment profile" unless env.fetch(key, "").empty?
      end
      raise Invalid, "SECRET_KEY_BASE must contain at least 64 bytes" if env.fetch("SECRET_KEY_BASE", "").bytesize < 64
      unless env.fetch("CAMPFIRE_RECOVERY_EPOCH", "").match?(/\A[A-Za-z0-9_-]{32,128}\z/)
        raise Invalid, "CAMPFIRE_RECOVERY_EPOCH must be a random 32-128 character deployment-held identifier"
      end
      bootstrap = env.fetch("CAMPFIRE_BOOTSTRAP_SECRET", "")
      raise Invalid, "CAMPFIRE_BOOTSTRAP_SECRET must contain 32-4096 bytes" if !bootstrap.empty? && !bootstrap.bytesize.between?(32, 4096)
      FLAGS.each do |key|
        value = env.fetch(key, "false")
        raise Invalid, "#{key} must be an explicit boolean" unless %w[ true false 1 0 ].include?(value)
        if %w[ true 1 ].include?(value) && env["CAMPFIRE_AGENT_EXPERIMENTAL"] != "true"
          raise Invalid, "Native features require explicit CAMPFIRE_AGENT_EXPERIMENTAL=true qualification opt-in"
        end
      end
      if %w[ true 1 ].include?(env["CAMPFIRE_AGENT_DISPATCH_ENABLED"]) && !%w[ true 1 ].include?(env["CAMPFIRE_AGENT_ENABLED"])
        raise Invalid, "Dispatch cannot be enabled without native collaboration"
      end
      raise Invalid, "SKIP_TELEMETRY must remain true" unless [ "true", "1" ].include?(env.fetch("SKIP_TELEMETRY", "true"))
      raise Invalid, "REDIS_URL must use the bundled loopback Redis" unless [ "redis://127.0.0.1:6379/0", "redis://localhost:6379/0" ].include?(env.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
      public_port = port!("CAMPFIRE_LISTEN_PORT", env.fetch("CAMPFIRE_LISTEN_PORT", env.fetch("PORT", "8080")))
      puma_port = port!("CAMPFIRE_PUMA_PORT", env.fetch("CAMPFIRE_PUMA_PORT", "3001"))
      raise Invalid, "Public, Puma and Redis ports must differ" if public_port == puma_port || [ public_port, puma_port ].include?(6379)
      %w[ WEB_CONCURRENCY JOB_CONCURRENCY ].each do |key|
        raise Invalid, "#{key} must be an integer from 1 to 8" unless env.fetch(key, "1").match?(/\A[1-8]\z/)
      end
      validate_vapid!
      self
    end

    def apply!
      validate!
      env["CAMPFIRE_LISTEN_PORT"] ||= env.fetch("PORT", "8080")
      env["THRUSTER_HTTP_PORT"] = env.fetch("CAMPFIRE_LISTEN_PORT")
      env["THRUSTER_TARGET_PORT"] = env.fetch("CAMPFIRE_PUMA_PORT", "3001")
      env["THRUSTER_FORWARD_HEADERS"] = "true"
      env["THRUSTER_GZIP_COMPRESSION_DISABLE_ON_AUTH"] = "true"
      env["THRUSTER_LOG_REQUESTS"] = "false"
      env["REDIS_URL"] ||= "redis://127.0.0.1:6379/0"
      env["WEB_CONCURRENCY"] ||= "1"
      env["JOB_CONCURRENCY"] ||= "1"
      env["SKIP_TELEMETRY"] = "true"
      FLAGS.each { |key| env[key] = %w[ true 1 ].include?(env[key]) ? "true" : "false" }
      self
    end

    def check_storage!(root)
      storage = File.join(root, "storage")
      raise Invalid, "storage must be a real directory" if File.symlink?(storage) || !File.directory?(storage)
      marker = File.join(storage, ".campfire-restore-incomplete")
      raise Invalid, "An incomplete restore must be reviewed before startup" if File.exist?(marker) || File.symlink?(marker)
      %w[ db files thruster ].each do |name|
        path = File.join(storage, name)
        raise Invalid, "storage/#{name} must not be a symlink" if File.symlink?(path)
        FileUtils.mkdir_p(path, mode: 0o700)
      end
      probe = File.join(storage, ".preflight-#{SecureRandom.hex(12)}")
      begin
        File.open(probe, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |probe_file|
          probe_file.write("ok")
          probe_file.fsync
        end
      ensure
        File.unlink(probe) if File.exist?(probe)
      end
      pins = PINNED_SECRETS.to_h { |key| [ key, Digest::SHA256.hexdigest(env.fetch(key)) ] }
      path = File.join(storage, ".campfire-secret-fingerprints.json")
      File.open(path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |file|
        file.flock(File::LOCK_EX)
        existing = file.read
        unless existing.empty? || JSON.parse(existing) == pins
          raise Invalid, "Persistent instance secrets changed; use the documented deliberate rotation procedure"
        end
        if existing.empty?
          file.write(JSON.generate(pins) + "\n")
          file.flush
          file.fsync
        end
      end
      self
    rescue SystemCallError, JSON::ParserError
      raise Invalid, "Persistent storage is inaccessible or its secret fingerprint record is invalid"
    end

    private
      def port!(name, value)
        raise Invalid, "#{name} must be an unprivileged TCP port" unless value.to_s.match?(/\A[0-9]{4,5}\z/) && (1024..65535).cover?(value.to_i)
        value.to_i
      end

      def validate_vapid!
        public_key = Base64.urlsafe_decode64(env.fetch("VAPID_PUBLIC_KEY", ""))
        private_key = Base64.urlsafe_decode64(env.fetch("VAPID_PRIVATE_KEY", ""))
        raise Invalid, "VAPID keys must be a matching P-256 key pair" unless public_key.bytesize == 65 && private_key.bytesize == 32
        group = OpenSSL::PKey::EC::Group.new("prime256v1")
        scalar = OpenSSL::BN.new(private_key, 2)
        raise Invalid, "VAPID keys must be a matching P-256 key pair" unless scalar > 0 && scalar < group.order
        derived = group.generator.mul(scalar).to_octet_string(:uncompressed)
        raise Invalid, "VAPID keys must be a matching P-256 key pair" unless OpenSSL.fixed_length_secure_compare(derived, public_key)
      rescue ArgumentError, OpenSSL::OpenSSLError
        raise Invalid, "VAPID keys must be a matching P-256 key pair"
      end
  end
end
