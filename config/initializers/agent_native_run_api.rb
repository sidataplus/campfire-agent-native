Rails.application.config.to_prepare do
  AgentNative::ApiController.include AgentNativeRunApi
  AgentNative::HumanController.include AgentNativeHumanRunApi
end
