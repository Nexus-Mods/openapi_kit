# frozen_string_literal: true

# Eager, so a wrong implementation is a TypeError at boot rather than on the first
# request that endpoint receives. Build it in oapi_registry instead if you would rather
# defer construction.
Rails.application.config.to_prepare do
  Rails.configuration.x.api_registry = Dummy::V1::Registry.new(
    mods: ModsHandler.new,
    system: SystemHandler.new,
    bearer_auth: BearerAuthenticator.new,
    api_key_auth: ApiKeyAuthenticator.new
  )
end
