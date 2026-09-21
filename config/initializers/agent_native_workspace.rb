Rails.application.config.filter_parameters += [ :manifest, :token, :fields, :body_text, :arguments, :proposal_digest ]
Rails.application.routes.append do
  draw :agent_workspace
  get "/agent/admin", to: "agent_native/admin#index"
  post "/agent/admin", to: "agent_native/admin#create"
  post "/agent/admin/:profile_id", to: "agent_native/admin#change"
end

Rails.application.config.to_prepare do
  MessagesHelper.prepend(Module.new do
    def message_presentation(message)
      if message.creator.native_agent? && message.attachment.attached?
        link_to message.attachment.filename.to_s, "/agent/workspace/messages/#{message.id}/content", data: { turbo: false }
      else
        super
      end
    end
  end)
end
