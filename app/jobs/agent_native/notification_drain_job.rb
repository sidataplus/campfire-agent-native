class AgentNative::NotificationDrainJob < ApplicationJob
  # Notification rows are the durable queue. This job only kicks the delivery
  # jobs so a queue outage cannot turn a committed notification into lost work.
  def perform
    AgentNative::Notification.drain!
  end
end
