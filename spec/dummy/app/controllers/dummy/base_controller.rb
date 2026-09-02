# frozen_string_literal: true

module Dummy
  class BaseController < ActionController::API
    rescue_from Oapi::DecodeError, with: :bad_request

    private

    def oapi_container = Rails.configuration.x.api_container

    def bad_request(error)
      render json: { "error" => error.detail, "field" => error.json_pointer }, status: :bad_request
    end
  end
end
