class AgentNative::OperatorGrant < AgentNative::Record
  belongs_to :profile
  belongs_to :user
  validate { errors.add(:user, "must be an active human") unless user&.active? && !user.bot? }
  after_save { profile.increment!(:authorization_version) }
  after_destroy { profile.increment!(:authorization_version) }
end
