# frozen_string_literal: true

class ApiKeyAuthenticator
  include Dummy::V1::Security::ApiKeyAuth

  # The document says the key arrives in the X-Api-Key header, so credential reads it.
  # It also lists no scopes for this alternative, so there is nothing to check.
  def authenticate(request:, scopes:)
    key = credential(request)
    key.nil? ? nil : Principal::Key.new(client: "robot-#{key}")
  end
end
