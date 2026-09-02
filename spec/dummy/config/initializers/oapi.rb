# frozen_string_literal: true

Rails.application.config.to_prepare do
  container = HandlerContainer.new(
    "v1.handlers.mods" => ModsHandler.new,
    "v1.handlers.system" => SystemHandler.new,
    "v1.security.bearer_auth" => BearerAuthenticator.new,
    "v1.security.api_key_auth" => ApiKeyAuthenticator.new
  )

  Rails.configuration.x.api_container = container
  Dummy::V1::Container.verify!(container)
end
