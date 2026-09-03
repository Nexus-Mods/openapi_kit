# frozen_string_literal: true

# Rails instantiates controllers itself, so they read the registry from here rather than
# being handed one. to_prepare reassigns it on a code reload.
Rails.application.config.to_prepare do
  Dummy::V1::Registry.current = Dummy::V1::Registry::Eager.new(
    mods: ModsHandler.new,
    system: SystemHandler.new,
    bearer_auth: BearerAuthenticator.new,
    api_key_auth: ApiKeyAuthenticator.new
  )
end
