# frozen_string_literal: true

class HandlerContainer
  def initialize(registrations)
    @registrations = registrations
  end

  def resolve(key)
    @registrations.fetch(key) { raise KeyError, "nothing registered for #{key.inspect}" }
  end
end
