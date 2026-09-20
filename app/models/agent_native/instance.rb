class AgentNative::Instance < ApplicationRecord
  def self.current
    find_or_create_by!(id: 1) do |instance|
      instance.instance_uuid = SecureRandom.uuid
      instance.stream_epoch = SecureRandom.uuid
      instance.recovery_digest = Digest::SHA256.hexdigest(ENV.fetch("CAMPFIRE_RECOVERY_EPOCH", "development"))
    end
  end

  def dispatch_allowed?
    AgentNative.enabled? && ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] == "true" && !recovery_required &&
      recovery_digest == Digest::SHA256.hexdigest(ENV.fetch("CAMPFIRE_RECOVERY_EPOCH", "development"))
  end
end
