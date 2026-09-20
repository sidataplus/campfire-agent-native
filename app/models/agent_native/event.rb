class AgentNative::Event < ApplicationRecord
  belongs_to :room, optional: true

  def self.publish!(kind:, resource:, room:, profile: nil, actor: nil)
    create!(event_uuid: SecureRandom.uuid, kind: kind, resource_type: resource.class.name.demodulize.underscore,
      resource_id: resource.id.to_s, room_id: room.id, profile_id: profile&.id,
      actor_kind: actor.is_a?(AgentNative::Profile) ? "agent" : (actor ? "human" : "system"), actor_id: actor&.id&.to_s)
  end

  def wire
    { id: event_uuid, type: kind, occurred_at: created_at.iso8601,
      resource: { type: resource_type, id: resource_id }, room_id: room_id.to_s,
      actor: { kind: actor_kind, id: actor_id }.compact, metadata: {} }
  end
end
