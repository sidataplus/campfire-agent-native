# Deliberately does not inherit chat authentication, redirects or browser checks.
class HealthController < ActionController::Base
  def live
    response.headers["Cache-Control"] = "no-store"
    render json: { status: "ok" }
  end

  def ready
    response.headers["Cache-Control"] = "no-store"
    if Campfire::Readiness.ready?
      render json: { status: "ready" }
    else
      render json: { status: "unavailable" }, status: :service_unavailable
    end
  end
end
