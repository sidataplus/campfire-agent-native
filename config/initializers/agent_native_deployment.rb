require_relative "../../lib/campfire/deployment"

Rails.application.config.x.agent_native.enabled = false
Rails.application.config.x.agent_native.dispatch_enabled = false
Rails.application.config.filter_parameters += [ :bootstrap_secret, :campfire_bootstrap_secret, :recovery_epoch ]

if Rails.env.production? && !Campfire::Deployment.asset_build?
  deployment = Campfire::Deployment.new
  deployment.validate!
  ENV["SKIP_TELEMETRY"] = "true"
  uri = deployment.public_uri
  config = Rails.application.config
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { Campfire::Deployment::HEALTH_PATHS.include?(request.path) } } }
  config.hosts = [ uri.host ]
  config.host_authorization = {
    exclude: ->(request) {
      Campfire::Deployment::HEALTH_PATHS.include?(request.path) &&
        %w[ healthcheck.railway.app localhost 127.0.0.1 ].include?(request.host)
    }
  }
  config.action_cable.allowed_request_origins = [ "#{uri.scheme}://#{uri.host}#{uri.port == 443 ? '' : ":#{uri.port}"}" ]
end
