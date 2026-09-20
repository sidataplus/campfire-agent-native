class FirstRunsController < ApplicationController
  allow_unauthenticated_access

  before_action :prevent_repeats
  before_action :protect_setup_response
  rate_limit to: 10, within: 3.minutes, only: :create
  before_action :verify_bootstrap_secret, only: :create

  def show
    @user = User.new
  end

  def create
    user = FirstRun.create!(user_params)
    start_new_session_for user
    redirect_to root_url
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_url
  rescue ActiveRecord::RecordInvalid
    @user = User.new(user_params.except(:password, :avatar))
    flash.now[:alert] = "Setup could not be completed. Check the account details and try again."
    render :show, status: :unprocessable_entity
  end

  private
    def prevent_repeats
      redirect_to root_url if Account.any?
    end

    def protect_setup_response
      response.headers["Cache-Control"] = "no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def verify_bootstrap_secret
      return unless Campfire::Bootstrap.required?
      # Only a submitted body field is accepted. Never accept a setup secret in a URL.
      unless Campfire::Bootstrap.valid?(request.request_parameters["bootstrap_secret"])
        head :forbidden
      end
    end

    def user_params
      params.require(:user).permit(:name, :avatar, :email_address, :password)
    end
end
