# frozen_string_literal: true

class ApiKeyAuthenticator
  include Dummy::V1::Security::ApiKeyAuth

  def authenticate(request:, scopes:)
    key = request.headers["X-Api-Key"]
    key.blank? ? nil : Robot.new(name: "robot-#{key}")
  end
end
