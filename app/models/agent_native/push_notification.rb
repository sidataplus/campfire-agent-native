class AgentNative::PushNotification < WebPush::Notification
  def initialize(tag:, **options)
    @tag = tag
    super(**options)
  end

  private
    def encoded_message
      message = JSON.parse(super)
      message.fetch("options")["tag"] = @tag
      JSON.generate(message)
    end
end
