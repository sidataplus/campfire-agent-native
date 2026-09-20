Rails.application.config.to_prepare do
  AgentNative::ApiController.include AgentNativeEventApi
end
