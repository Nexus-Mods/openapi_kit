# frozen_string_literal: true

module Dummy
  class BaseController < ActionController::API
    rescue_from Oapi::DecodeError, with: :bad_request

    private

    def oapi_container = Rails.configuration.x.api_container

    # oapi reports what the document requires and leaves the checking here. Each
    # requirement is one alternative: satisfy every scheme in any one of them.
    def oapi_authenticate!(requirements)
      return if requirements.any? { |requirement| satisfied?(requirement) }

      render json: { "error" => "unauthenticated" }, status: :unauthorized
    end

    def satisfied?(requirement)
      requirement.anonymous? || requirement.schemes.all? do |name, scopes|
        credential(Dummy::V1::Security::SCHEMES.fetch(name)) && scopes.all? { |s| granted.include?(s) }
      end
    end

    def credential(scheme)
      case scheme
      when Oapi::Security::Http then request.headers["Authorization"]&.delete_prefix("Bearer ").presence
      when Oapi::Security::ApiKey then request.headers[scheme.parameter_name].presence
      end
    end

    def granted = request.headers["X-Scopes"].to_s.split(",")

    def bad_request(error)
      render json: { "error" => error.detail, "field" => error.json_pointer }, status: :bad_request
    end
  end
end
