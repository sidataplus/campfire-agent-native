class AgentNative::Notification < AgentNative::Record
  after_create_commit :enqueue_delivery

  def self.for_event!(event)
    return unless AgentNative.enabled?
    if event.kind == "action.created"
      action = AgentNative::Action.find_by(id: event.resource_id)
      return unless action
      human_ids = action.reviewer_user_ids
      run = action.run
    elsif event.kind == "run.updated"
      run = AgentNative::Run.find_by(id: event.resource_id)
      return unless run && run.parent_run_id.nil? && (run.state == "failed" || (run.state == "completed" && ENV["CAMPFIRE_AGENT_COMPLETION_PUSH"] == "true"))
      human_ids = run.owner_profile.operator_grants.pluck(:user_id)
    else
      return
    end
    users = User.active.where(native_agent: false, id: human_ids).where(id: Membership.where(room_id: event.room_id).select(:user_id))
    Push::Subscription.where(user_id: users.select(:id)).find_each do |subscription|
      create!(event_uuid: event.event_uuid, user_id: subscription.user_id, subscription_id: subscription.id,
        room_id: event.room_id, action_id: action&.id, run_id: run&.id, ready_at: Time.current)
    end
  end

  def self.drain!
    where(state: "attempting").where("updated_at < ?", 5.minutes.ago).update_all(state: "pending", ready_at: Time.current)
    where(state: %w[ pending failed ]).where("ready_at <= ?", Time.current).limit(100).find_each(&:enqueue_delivery)
  end

  def enqueue_delivery
    AgentNative::NotificationJob.perform_later(id)
  rescue StandardError => error
    Rails.logger.warn("Native notification queue unavailable: #{error.class.name}")
  end

  def deliver_pending!
    claimed = with_lock do
      next false unless %w[ pending failed ].include?(state) && ready_at <= Time.current
      update!(state: "attempting", attempts: attempts + 1)
      true
    end
    return unless claimed
    human = User.find_by(id: user_id)
    subscription = Push::Subscription.find_by(id: subscription_id, user_id: user_id)
    action = AgentNative::Action.find_by(id: action_id)
    run = AgentNative::Run.find_by(id: run_id)
    allowed = human&.active? && !human.bot? && human.rooms.exists?(room_id) && subscription
    allowed &&= action ? (action.state == "pending" && action.expires_at.future? && AgentNative::Attention.visible_action?(human, action)) : (run && run.owner_profile.operator?(human, run.room))
    unless allowed
      update!(state: "discarded")
      return
    end
    path = run ? "/agent/workspace/runs/#{run.id}" : "/agent/workspace"
    notification = AgentNative::PushNotification.new(
      tag: "agent-#{action_id || run_id}", title: "Agent workspace", body: "A task has an update for you. Open the workspace to review.",
      path: path, badge: 1, endpoint: subscription.endpoint, endpoint_ip_resolver: subscription.method(:resolved_endpoint_ip),
      p256dh_key: subscription.p256dh_key, auth_key: subscription.auth_key)
    notification.deliver
    update!(state: "sent", last_error_class: nil)
  rescue WebPush::ExpiredSubscription
    subscription&.destroy
    update!(state: "discarded")
  rescue StandardError => error
    update!(state: "failed", last_error_class: error.class.name, ready_at: [ attempts * 60, 3600 ].min.seconds.from_now)
  end
end
