class AgentNative::Profile < AgentNative::Record
  belongs_to :user
  has_many :credentials, dependent: :destroy
  has_many :room_grants, dependent: :destroy
  has_many :operator_grants, dependent: :destroy
  validates :runtime_id, presence: true
  validate { AgentNative::Contract.validate!("IntegrationManifest", manifest) }

  def self.provision!(name:, manifest:, runtime_id: SecureRandom.uuid)
    AgentNative::Contract.validate!("IntegrationManifest", manifest)
    transaction do
      user = User.create!(name: name, role: :bot, native_agent: true)
      create!(user: user, manifest: manifest, runtime_id: runtime_id)
    end
  end

  def allowed_rooms
    Room.where(id: room_grants.select(:room_id)).where(id: user.memberships.select(:room_id))
  end

  def operator?(human, room)
    human&.active? && !human.bot? && human.rooms.exists?(room.id) &&
      operator_grants.exists?(user_id: human.id)
  end

  def authorize!(credential, scope = nil, room = nil)
    reload
    credential.reload
    raise AgentNative::Error.new("invalid_token", 401) unless enabled && user.reload.active? && credential.usable?
    raise AgentNative::Error.new("insufficient_scope", 403) if scope && !credential.scopes.include?(scope)
    if room
      raise ActiveRecord::RecordNotFound unless allowed_rooms.exists?(room.id)
      needed = scope.to_s.end_with?("read") ? "dms:read" : "dms:write"
      raise AgentNative::Error.new("insufficient_scope", 403) if room.direct? && scope && !credential.scopes.include?(needed)
    end
  end
end
