class FirstRun
  ACCOUNT_NAME = "Campfire"
  FIRST_ROOM_NAME = "All Talk"

  def self.create!(user_params)
    # The account's unique singleton_guard consumes setup in the same transaction
    # as administrator/room creation. Validation failure must not strand an account.
    Account.transaction do
      Account.create!(name: ACCOUNT_NAME)
      room = Rooms::Open.new(name: FIRST_ROOM_NAME)
      administrator = room.creator = User.new(user_params.merge(role: :administrator))
      validate_administrator!(administrator)
      room.save!
      room.memberships.grant_to administrator
      administrator
    end
  end

  def self.validate_administrator!(administrator)
    %i[ name email_address password ].each do |attribute|
      administrator.errors.add(attribute, :blank) if administrator.public_send(attribute).blank?
    end
    if administrator.password.to_s.bytesize > 72
      administrator.errors.add(:password, :too_long, count: 72)
    end
    raise ActiveRecord::RecordInvalid.new(administrator) if administrator.errors.any?
  end
  private_class_method :validate_administrator!
end
