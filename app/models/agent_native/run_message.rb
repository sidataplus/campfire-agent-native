class AgentNative::RunMessage < AgentNative::Record
  belongs_to :run
  after_create do
    AgentNative::Event.publish!(kind: "run_message.created", resource: self, room: run.room)
  end

  def wire
    { id: id, run_id: run_id, author_kind: author_kind, author_id: author_id, body_text: body_text,
      revision: revision, created_at: created_at.iso8601, client_message_id: client_message_id }
  end
end
