# frozen_string_literal: true

# Thunks, so nothing is constructed until the first request that needs it. Omit one and
# it does not compile, which is why there is no boot-time check to run.
Rails.application.config.to_prepare do
  Rails.configuration.x.api_registry = Dummy::V1::Registry.new(
    mods: -> { ModsHandler.new },
    system: -> { SystemHandler.new },
    bearer_auth: -> { BearerAuthenticator.new },
    api_key_auth: -> { ApiKeyAuthenticator.new }
  )
end
