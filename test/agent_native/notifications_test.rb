require "test_helper"

class AgentNativeNotificationsTest < ActiveSupport::TestCase
  test "notification drain runner invokes the durable drain" do
    AgentNative::Notification.expects(:drain!).once
    AgentNative::NotificationDrainJob.perform_now
  end

  test "an unavailable push endpoint is a delivery failure" do
    notification = AgentNative::PushNotification.new(
      tag: "agent-test", title: "Agent workspace", body: "Review an update.", path: "/agent/workspace", badge: 1,
      endpoint: "https://fcm.googleapis.com/fcm/send/test", endpoint_ip_resolver: -> { nil },
      p256dh_key: "test-key", auth_key: "test-auth")

    assert_raises(AgentNative::Notification::DeliverySkipped) { notification.deliver }
  end

end
