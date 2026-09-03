# frozen_string_literal: true

module Dummy
  class BaseController < ActionController::API
    rescue_from Oapi::DecodeError, with: :bad_request
    rescue_from Oapi::Security::Unauthenticated, with: :unauthorized

    private

    # Rails instantiates controllers itself, so the registry cannot be injected. This is
    # the seam: override it for a per-request or multi-tenant lookup.
    def oapi_registry = Rails.configuration.x.api_registry

    def unauthorized = render(json: { "error" => "unauthenticated" }, status: :unauthorized)

    def bad_request(error)
      render json: { "error" => error.detail, "field" => error.json_pointer }, status: :bad_request
    end
  end
end
