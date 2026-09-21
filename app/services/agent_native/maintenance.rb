class AgentNative::Maintenance
  def self.startup!
    instance = AgentNative::Instance.current
    expected = Digest::SHA256.hexdigest(ENV.fetch("CAMPFIRE_RECOVERY_EPOCH", "development"))
    if instance.recovery_digest != expected
      instance.with_lock do
        now = Time.current
        Session.delete_all
        AgentNative::Credential.update_all(revoked_at: now, updated_at: now)
        AgentNative::Profile.update_all("enabled=0, authorization_version=authorization_version+1")
        AgentNative::Action.where(state: "pending").update_all("state='invalidated', version=version+1")
        AgentNative::Invocation.where(disposition: "pending").update_all("disposition='invalidated', version=version+1")
        AgentNative::Run.where.not(state: AgentNative::Run::TERMINAL).update_all("needs_reconciliation=1, owner_generation=owner_generation+1, version=version+1")
        AgentNative::Notification.where.not(state: "sent").update_all(state: "discarded")
        instance.update!(recovery_required: true, recovery_digest: expected, stream_epoch: SecureRandom.uuid)
        audit!("epoch_changed", "system", "deployment-held recovery epoch changed", { "stream_epoch" => instance.stream_epoch })
      end
    end
    AgentNative::Notification.drain! if AgentNative.enabled?
  end

  def self.reconcile_run!(human, run_id:, state:, source_revision:, evidence_reference:)
    AgentNative::Administration.change!(human) do
      run = AgentNative::Run.find(run_id)
      raise AgentNative::Error.new("reconciliation_not_required", 409) unless run.needs_reconciliation
      allowed = AgentNative::Run::TRANSITIONS.keys + AgentNative::Run::TERMINAL
      raise AgentNative::Error.new("validation_failed", 422) unless allowed.include?(state) && source_revision.is_a?(Integer) && source_revision > run.source_revision
      audit!("reconcile_run", human.id.to_s, evidence_reference, { "run_id" => run.id, "state" => state, "source_revision" => source_revision, "owner_generation" => run.owner_generation })
      run.update!(state: state, source_revision: source_revision, needs_reconciliation: false, version: run.version + 1, last_reported_at: Time.current)
    end
  end

  def self.complete_recovery!(human, evidence_reference:)
    AgentNative::Administration.change!(human) do
      instance = AgentNative::Instance.current
      expected = Digest::SHA256.hexdigest(ENV.fetch("CAMPFIRE_RECOVERY_EPOCH", "development"))
      raise AgentNative::Error.new("stream_reset", 409) unless instance.recovery_digest == expected
      raise AgentNative::Error.new("reconciliation_required", 409) if AgentNative::Run.where(needs_reconciliation: true).exists?
      audit!("complete_recovery", human.id.to_s, evidence_reference, { "stream_epoch" => instance.stream_epoch })
      instance.update!(recovery_required: false)
    end
  end

  def self.prune_events!(human, older_than_days: 30, keep_latest: 10_000)
    raise AgentNative::Error.new("validation_failed", 422) unless older_than_days.between?(1, 3650) && keep_latest.between?(10_000, 10_000_000)
    AgentNative::Administration.change!(human) do
      instance = AgentNative::Instance.current
      retained = AgentNative::Event.order(id: :desc).offset(keep_latest).pick(:id)
      next 0 unless retained
      earliest_fresh = AgentNative::Event.where(created_at: older_than_days.days.ago..).minimum(:id)
      age_boundary = earliest_fresh ? earliest_fresh - 1 : (AgentNative::Event.maximum(:id) || 0)
      boundary = [ retained, age_boundary ].min
      next 0 if boundary <= instance.event_floor
      removed = AgentNative::Event.where(id: ..boundary).delete_all
      instance.update!(event_floor: boundary)
      audit!("prune_events", human.id.to_s, "configured retention", { "floor" => boundary, "deleted" => removed })
      removed
    end
  end

  def self.diagnostics
    instance = AgentNative::Instance.current
    { build_revision: ENV.fetch("GIT_REVISION", "unreleased"), protocol_version: "1", instance_id: instance.instance_uuid,
      stream_epoch: instance.stream_epoch, dispatch_allowed: instance.dispatch_allowed?, recovery_required: instance.recovery_required,
      event_count: AgentNative::Event.count, oldest_event_at: AgentNative::Event.minimum(:created_at), event_floor: instance.event_floor,
      profiles: AgentNative::Profile.count, active_credentials: AgentNative::Credential.where(revoked_at: nil).count,
      runs_requiring_reconciliation: AgentNative::Run.where(needs_reconciliation: true).count,
      stale_nonterminal_run_observations: AgentNative::Run.where.not(state: AgentNative::Run::TERMINAL).where("last_reported_at < ?", 5.minutes.ago).count,
      notification_backlog: AgentNative::Notification.where(state: %w[ pending failed attempting ]).count,
      consumers: AgentNative::Consumer.limit(100).map { |c| { id: c.id, checkpoint: c.checkpoint, delivered: c.delivered, ingest_lag: [ (AgentNative::Event.maximum(:id) || 0) - c.checkpoint, 0 ].max } } }
  end

  def self.audit!(operation, actor, reference, metadata)
    raise AgentNative::Error.new("evidence_reference_required", 422) unless reference.is_a?(String) && reference.bytesize.between?(8, 1024)
    AgentNative::MaintenanceAudit.create!(operation: operation, actor_id: actor, evidence_reference: reference, metadata: metadata)
  end
end
