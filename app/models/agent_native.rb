module AgentNative
  def self.table_name_prefix
    "agent_"
  end

  def self.enabled?
    Rails.configuration.x.agent_native.enabled == true
  end

  class Error < StandardError
    attr_reader :code, :status
    def initialize(code, status = 422)
      @code, @status = code, status
      super(code)
    end
  end
end
