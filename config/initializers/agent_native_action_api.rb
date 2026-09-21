Rails.application.config.to_prepare do
  AgentNative::ApiController.include AgentNativeActionApi
  AgentNative::HumanController.include AgentNativeHumanActionApi
end
