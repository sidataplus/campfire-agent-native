module Authentication::SessionLookup
  def find_session_by_cookie
    if token = cookies.signed[:session_token]
      Session.joins(:user).where(users: { native_agent: false, status: :active }).find_by(token: token)
    end
  end
end
