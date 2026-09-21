module AgentNative::WorkspaceHelper
  def native_profile_name(id)
    AgentNative::Profile.find_by(id: id)&.user&.name || "Retired integration"
  end

  def native_reference_label(reference)
    [ reference["kind"], reference["id"], reference["revision"] && "revision #{reference['revision']}" ].compact.join(" · ")
  end
end
