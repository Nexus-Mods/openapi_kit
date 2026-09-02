# frozen_string_literal: true

# Returning nil means this alternative was not satisfied, so oapi tries the next one.
class BearerAuthenticator
  include Dummy::V1::Security::BearerAuth

  def authenticate(request:, scopes:)
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")
    return nil if token.blank?

    granted = request.headers["X-Scopes"].to_s.split(",")
    return nil unless scopes.all? { |scope| granted.include?(scope) }

    Person.new(id: token.hash.abs % 1000, scopes: granted)
  end
end
