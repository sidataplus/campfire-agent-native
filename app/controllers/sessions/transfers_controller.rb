class Sessions::TransfersController < ApplicationController
  allow_unauthenticated_access

  def show
  end

  def update
    if user = User.active.where(native_agent: false).find_by_transfer_id(params[:id])
      start_new_session_for user
      redirect_to post_authenticating_url
    else
      head :bad_request
    end
  end
end
