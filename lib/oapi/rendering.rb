# typed: strict
# frozen_string_literal: true

require "oapi/body"
require "oapi/response"

module Oapi
  module Rendering
    extend T::Sig

    Controller = T.type_alias do
      T.all(::ActionController::Metal, ::ActionController::Head, ::ActionController::Rendering)
    end

    sig { params(result: Oapi::Response).void }
    def render_response(result)
      T.bind(self, Controller)

      case (body = result.to_body)
      when Oapi::Body::Empty
        head(result.status)
      when Oapi::Body::Json
        render(json: body.wire, status: result.status, content_type: result.content_type)
      when Oapi::Body::Stream
        response.headers["Content-Type"] = result.content_type.to_s
        response.status = result.status
        self.response_body = body
      when Oapi::Body::File
        response.headers["Content-Type"] = result.content_type.to_s
        response.headers["Content-Length"] = body.size.to_s
        response.status = result.status
        response.send_file(body.path.to_s)
      else T.absurd(body)
      end
    end
  end
end
