require "test_helper"

class AgentNativeContractsTest < ActiveSupport::TestCase
  fixtures = JSON.parse(Rails.root.join("docs/agent-native/contracts/fixtures.json").read).fetch("fixtures")
  fixtures.each do |fixture|
    test "frozen contract fixture #{fixture.fetch('name')}" do
      definition = AgentNative::Contract::DEFINITIONS.fetch(fixture.fetch("schema"))
      assert_equal fixture.fetch("valid"), AgentNative::Contract.valid?(definition, fixture.fetch("data"))
    end
  end

  test "all frozen operations are routed to implemented methods" do
    catalog = JSON.parse(Rails.root.join("docs/agent-native/contracts/openapi-catalog.json").read).fetch("operations")
    catalog.each do |operation|
      route = Rails.application.routes.recognize_path(operation.fetch("path").gsub(/\{[^}]+\}/, "1"), method: operation.fetch("method").downcase.to_sym)
      klass = route.fetch(:controller).camelize.concat("Controller").constantize
      assert_includes klass.action_methods, operation.fetch("operation_id").underscore
    end
  end
end
