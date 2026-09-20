# Disposable CI fixture. Never runs under production or against a supplied URL.
abort "Synthetic fixture requires RAILS_ENV=test" unless Rails.env.test? && ENV["AGENT_NATIVE_CI_FIXTURE"] == "true"
require "json"
path, operation = ARGV
abort "A private fixture output path is required" unless path && operation
Rails.configuration.x.agent_native.enabled = true
ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = "true"
AgentNative::Instance.current.update!(recovery_required: false)

if operation == "setup"
  Account.first || Account.create!(name: "Synthetic native qualification")
  human = User.create!(name: "Synthetic operator", email_address: "native-ci-#{SecureRandom.hex(8)}@example.test", role: :administrator, password: SecureRandom.hex(24))
  room = Rooms::Closed.create!(name: "Synthetic native qualification", creator: human)
  room.memberships.grant_to(human)
  capabilities = { "modes" => [ "notification", "interactive", "task" ], "supports_cancel" => true, "supports_pause" => false,
    "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [ "analysis" ] }
  scopes = AgentNative::Contract::DEFINITIONS.fetch("Scope").fetch("enum")
  manifest = { "name" => "CI worker", "protocol_version" => "1", "capabilities" => capabilities, "requested_scopes" => scopes, "action_types" => [ "reference.continue" ] }
  profile = AgentNative::Profile.provision!(name: "CI worker", manifest: manifest)
  profile.room_grants.create!(room: room, history_policy: "all_authorized")
  profile.operator_grants.create!(user: human)
  _, token = AgentNative::Credential.issue!(profile: profile, scopes: scopes)
  File.write(path, JSON.generate({ token: token, profile_id: profile.id, room_id: room.id.to_s, human_id: human.id.to_s }), mode: "w", perm: 0o600)
else
  data = JSON.parse(File.read(path))
  profile = AgentNative::Profile.find(data.fetch("profile_id"))
  human = User.find(data.fetch("human_id"))
  room = Room.find(data.fetch("room_id"))
  AgentNative::Instance.current.with_lock do
    AgentNative::Instance.current.touch
    case operation
    when "task", "ask", "status"
      text = operation + " synthetic HTTP qualification"
      input = { "profile_id" => profile.id, "body_text" => text, "client_message_id" => SecureRandom.uuid, "context" => { "references" => [], "include_current_request" => true } }
      message = Message.create!(room: room, creator: human, body: text)
      invocation = AgentNative::Invocation.submit!(profile: profile, human: human, room: room, input: input,
        source: { "kind" => "message", "id" => message.id.to_s, "revision" => message.agent_revision, "source_room_id" => room.id.to_s })
      puts JSON.generate({ invocation_id: invocation.id })
    when "respond"
      action = AgentNative::Action.pending.where(profile: profile, kind: "question").order(:created_at).last!
      receipt = action.decide!(human, { "proposal_digest" => action.proposal_digest, "decision" => "respond", "input" => { "choice" => "continue" } })
      puts JSON.generate({ receipt_id: receipt.id, run_id: action.run_id })
    when "cancel"
      run = AgentNative::Run.where(owner_profile: profile, state: "waiting_for_human").order(:created_at).last!
      receipt = AgentNative::Control.request!(run, human, { "control" => "cancel", "expected_run_version" => run.version })
      puts JSON.generate({ receipt_id: receipt.id, run_id: run.id })
    else
      abort "Unknown synthetic fixture operation"
    end
  end
end
