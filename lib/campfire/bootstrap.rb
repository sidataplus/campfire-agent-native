require "digest"
require "openssl"

module Campfire
  class Bootstrap
    def self.required?
      Rails.env.production? || ENV.key?("CAMPFIRE_BOOTSTRAP_SECRET")
    end

    def self.configured?
      ENV.fetch("CAMPFIRE_BOOTSTRAP_SECRET", "").bytesize >= 32
    end

    def self.valid?(candidate)
      return false unless configured? && candidate.is_a?(String) && candidate.bytesize.between?(32, 4096)
      OpenSSL.fixed_length_secure_compare(
        Digest::SHA256.digest(ENV.fetch("CAMPFIRE_BOOTSTRAP_SECRET")),
        Digest::SHA256.digest(candidate)
      )
    end

    def self.check_startup!
      if Account.none? && !configured?
        abort "CAMPFIRE_BOOTSTRAP_SECRET is required until first-administrator setup completes"
      end
      if Account.any? && !User.where(role: :administrator).exists?
        abort "Account has no administrator; restore or repair it through a private operator session"
      end
    end
  end
end
