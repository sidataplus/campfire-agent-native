Rails.application.config.to_prepare do
  AgentNative::Event.include AgentNativeNotificationEvents
end
