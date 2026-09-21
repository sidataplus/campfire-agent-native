class AgentNative::Administration
  def self.change!(human)
    raise AgentNative::Error.new("forbidden", 403) unless human&.active? && human.administrator? && !human.native_agent?
    AgentNative::Instance.current.with_lock { AgentNative::Instance.current.touch; yield }
  end

  def self.convert_legacy!(human, user, manifest)
    change!(human) do
      raise AgentNative::Error.new("validation_failed") unless user.bot? && !user.native_agent?
      user.webhook&.destroy!
      user.sessions.delete_all
      user.memberships.delete_all
      user.update!(native_agent: true, bot_token: nil, password_digest: nil, email_address: nil)
      AgentNative::Profile.create!(user: user, runtime_id: SecureRandom.uuid, manifest: manifest)
    end
  end
end
