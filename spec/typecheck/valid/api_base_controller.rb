# typed: strict
# frozen_string_literal: true

class ApiBaseController < ActionController::API
  extend T::Sig

  private

  # An application builds this once and returns it here. oapi never stores it, because
  # Rails instantiates controllers itself and cannot inject anything into them.
  sig { returns(Server::Registry) }
  def oapi_registry
    Server::Registry.new(
      mods: -> { T.unsafe(nil) },
      system: -> { T.unsafe(nil) },
      bearer_auth: -> { T.unsafe(nil) },
      api_key_auth: -> { T.unsafe(nil) }
    )
  end
end
