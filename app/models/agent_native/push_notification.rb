class AgentNative::PushNotification < WebPush::Notification
  def initialize(tag:, **options)
    @tag = tag
    super(**options)
  end

  def deliver(connection: nil)
    endpoint_ip = @endpoint_ip_resolver.call
    raise AgentNative::Notification::DeliverySkipped, "push endpoint is unavailable" unless endpoint_ip

    resolver = @endpoint_ip_resolver
    @endpoint_ip_resolver = -> { endpoint_ip }
    super(connection: connection)
  ensure
    @endpoint_ip_resolver = resolver if resolver
  end

  private
    def encoded_message
      message = JSON.parse(super)
      message.fetch("options")["tag"] = @tag
      JSON.generate(message)
    end
end
