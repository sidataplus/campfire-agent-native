# Open rooms enroll humans and legacy bots; native agents require explicit grants.
class Rooms::Open < Room
  after_save_commit :grant_access_to_all_users

  private
    def grant_access_to_all_users
      memberships.grant_to(User.active.where(native_agent: false)) if type_previously_changed?(to: "Rooms::Open")
    end
end
