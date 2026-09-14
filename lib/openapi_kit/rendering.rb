# typed: strict
# frozen_string_literal: true

require "openapi_kit/body"
require "openapi_kit/response"

module OpenAPIKit
  module Rendering
    extend T::Sig

    Controller = T.type_alias do
      T.all(::ActionController::Metal, ::ActionController::Head, ::ActionController::Rendering)
    end

    sig { params(result: OpenAPIKit::Response).void }
    def render_response(result)
      T.bind(self, Controller)

      case (body = result.to_body)
      when OpenAPIKit::Body::Empty
        head(result.status)
      when OpenAPIKit::Body::Json
        render(json: body.wire, status: result.status, content_type: result.content_type)
      when OpenAPIKit::Body::Stream
        response.headers["Content-Type"] = result.content_type.to_s
        response.status = result.status
        self.response_body = body
      when OpenAPIKit::Body::File
        response.headers["Content-Type"] = result.content_type.to_s
        response.headers["Content-Length"] = body.size.to_s
        response.status = result.status
        response.send_file(body.path.to_s)
      else T.absurd(body)
      end
    end
  end
end
