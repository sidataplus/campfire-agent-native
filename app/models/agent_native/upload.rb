class AgentNative::Upload < AgentNative::Record
  belongs_to :profile
  belongs_to :room
  has_one_attached :file

  def consume!(by:, in_room:)
    raise ActiveRecord::RecordNotFound unless profile == by && room == in_room
    raise AgentNative::Error.new("upload_unavailable", 409) if consumed_at || expires_at.past?
    update!(consumed_at: Time.current)
    file.blob
  end
end
