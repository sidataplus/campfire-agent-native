class AgentNative::Participant < AgentNative::Record
  belongs_to :run
  belongs_to :profile
  validate do
    errors.add(:profile, "must have current room access") unless profile&.allowed_rooms&.exists?(run&.room_id)
  end
end
