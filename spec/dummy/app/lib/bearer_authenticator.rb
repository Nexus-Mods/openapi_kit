# frozen_string_literal: true

# Returning nil means this alternative was not satisfied, so oapi tries the next one.
class BearerAuthenticator
  include Dummy::V1::Security::BearerAuth

  def authenticate(request:, scopes:)
    token = credential(request)
    return nil if token.nil?

    permissions = request.headers["X-Scopes"].to_s.split(",")
    return nil unless scopes.all? { |scope| permissions.include?(scope) }

    Principal::Token.new(user_id: token.hash.abs % 1000, permissions: permissions)
  end
end
