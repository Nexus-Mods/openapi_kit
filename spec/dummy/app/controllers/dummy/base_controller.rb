# frozen_string_literal: true

module Dummy
  class BaseController < ActionController::API
    rescue_from OpenAPIKit::DecodeError, with: :bad_request
    rescue_from OpenAPIKit::SecurityError, with: :unauthorized

    private

    def unauthorized = render(json: { "error" => "unauthenticated" }, status: :unauthorized)

    def bad_request(error)
      render json: { "error" => error.detail, "field" => error.json_pointer }, status: :bad_request
    end
  end
end
