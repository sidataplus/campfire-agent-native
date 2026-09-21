Rails.application.config.to_prepare do
  [ ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController ].each { |controller| controller.include AgentNativeStorageGuard }
end
