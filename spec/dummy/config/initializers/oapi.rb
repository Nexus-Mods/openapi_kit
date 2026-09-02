# frozen_string_literal: true

Rails.application.config.to_prepare do
  container = HandlerContainer.new(
    "v1.handlers.mods" => ModsHandler.new,
    "v1.handlers.system" => SystemHandler.new
  )

  Rails.configuration.x.api_container = container
  Dummy::V1::Container.verify!(container)
end
