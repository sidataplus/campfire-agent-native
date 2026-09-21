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

  def visible_to_profile?(profile)
    case resource_type
    when "run"
      visible_run?(profile, AgentNative::Run.find_by(id: resource_id))
    when "run_message"
      message = AgentNative::RunMessage.find_by(id: resource_id)
      visible_run?(profile, message&.run)
    when "activity"
      activity = AgentNative::Activity.find_by(id: resource_id)
      visible_run?(profile, activity&.run)
    when "artifact"
      artifact = AgentNative::Artifact.find_by(id: resource_id)
      return false unless artifact
      return true unless artifact.run

      visible_run?(profile, artifact.run)
    when "action"
      action = AgentNative::Action.find_by(id: resource_id)
      return false unless action
      return true unless action.run

      visible_run?(profile, action.run)
    when "invocation"
      invocation = AgentNative::Invocation.find_by(id: resource_id)
      return false unless invocation
      return true unless invocation.run

      visible_run?(profile, invocation.run)
    when "receipt"
      receipt = AgentNative::Receipt.find_by(id: resource_id)
      return false unless receipt

      case receipt.subject_type
      when "run"
        visible_run?(profile, AgentNative::Run.find_by(id: receipt.subject_id))
      when "action"
        action = AgentNative::Action.find_by(id: receipt.subject_id)
        return false unless action
        return true unless action.run

        visible_run?(profile, action.run)
      when "invocation"
        invocation = AgentNative::Invocation.find_by(id: receipt.subject_id)
        return false unless invocation
        return true unless invocation.run

        visible_run?(profile, invocation.run)
      else
        true
      end
    else
      true
    end
  end

  private
    def visible_run?(profile, run)
      !!run && AgentNative::Run.visible_to(profile).where(id: run.id).exists?
    end
end
