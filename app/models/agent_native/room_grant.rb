class AgentNative::RoomGrant < AgentNative::Record
  belongs_to :profile
  belongs_to :room
  validates :history_policy, inclusion: { in: %w[all_authorized since_grant] }
  after_create { room.memberships.grant_to(profile.user) }
  after_destroy { room.memberships.revoke_from(profile.user) }
  after_save :bump_authority
  after_destroy :bump_authority

  private
    def bump_authority
      profile.increment!(:authorization_version)
    end
end
