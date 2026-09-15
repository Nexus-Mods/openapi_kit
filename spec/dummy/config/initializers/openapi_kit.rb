# frozen_string_literal: true

# Rails instantiates controllers itself, so they read the assigned registry rather than
# being handed one. to_prepare reassigns it on a code reload.
Rails.application.config.to_prepare do
  Dummy::V1::Registry.instance = Dummy::V1::Registry.new(
    mods: ModsHandler.new,
    files: FilesHandler.new,
    system: SystemHandler.new,
    bearer_auth: BearerAuthenticator.new,
    api_key_auth: ApiKeyAuthenticator.new
  )
end
