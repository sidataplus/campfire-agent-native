require "securerandom"

module Campfire
  class Readiness
    def self.ready?
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        return false unless connection.select_value("SELECT 1").to_i == 1
        return false unless connection.data_source_exists?("accounts")
        return false if connection.pool.migration_context.needs_migration?
      end
      path = Rails.root.join("storage", ".ready-#{SecureRandom.hex(12)}")
      begin
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write("ok") }
      ensure
        File.unlink(path) if File.exist?(path)
      end
      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), connect_timeout: 1, read_timeout: 1, write_timeout: 1)
      redis.ping == "PONG"
    rescue StandardError => error
      Rails.logger.warn("Readiness dependency check failed (#{error.class})")
      false
    ensure
      redis&.close
    end
  end
end
