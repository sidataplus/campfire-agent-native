class AgentNative::NotificationJob < ApplicationJob
  def perform(id)
    AgentNative::Notification.find_by(id: id)&.deliver_pending!
  end
end
