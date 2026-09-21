module AgentNativeNotificationEvents
  extend ActiveSupport::Concern
  included do
    after_create { AgentNative::Notification.for_event!(self) }
  end
end
