class AgentNative::MaintenanceAudit < AgentNative::Record
  before_update { raise ActiveRecord::ReadOnlyRecord, "Maintenance records are immutable" }
  before_destroy { throw :abort }
end
