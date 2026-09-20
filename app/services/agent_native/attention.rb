class AgentNative::Attention
  def self.scope(human)
    AgentNative::Action.pending.where(room_id: human.rooms.select(:id))
      .joins(profile: :operator_grants).where(agent_operator_grants: { user_id: human.id })
      .where("EXISTS (SELECT 1 FROM json_each(agent_actions.reviewer_user_ids) WHERE value = ?)", human.id.to_s)
      .where(agent_profiles: { enabled: true })
  end

  def self.visible_action?(human, action)
    human&.active? && !human.bot? && action.profile.enabled && action.profile.user.active? &&
      action.reviewer_user_ids.include?(human.id.to_s) && action.profile.operator?(human, action.room) &&
      action.profile.allowed_rooms.exists?(action.room_id)
  end

  def self.page(human, after: nil, limit: 50)
    raise AgentNative::Error.new("validation_failed", 422) unless limit.between?(1, 100)
    scope = self.scope(human).order(:id)
    scope = scope.where("agent_actions.id > ?", after) if after
    scanned = scope.limit(limit + 1).to_a
    reads = AgentNative::AttentionRead.where(user: human, read: true, item_id: scanned.map(&:id)).pluck(:item_id)
    items = scanned.take(limit).filter_map do |action|
      next unless visible_action?(human, action)
      { id: action.id, room_id: action.room_id.to_s, run_id: action.run_id, action_id: action.id,
        reason: action.kind, title: action.title, read: reads.include?(action.id) }.compact
    end
    { items: items, more: scanned.size > limit, last_id: scanned.take(limit).last&.id }
  end
end
