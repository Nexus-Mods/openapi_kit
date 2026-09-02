# typed: strict
# frozen_string_literal: true

require "action_controller"
require "action_dispatch"

require "oapi/runtime"

module Oapi
  module Rails
    extend T::Sig

    module Codec
      class UploadedFile
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::ActionDispatch::Http::UploadedFile } }

        sig { override.params(value: T.untyped).returns(::ActionDispatch::Http::UploadedFile) }
        def from_wire(value)
          return value if value.is_a?(::ActionDispatch::Http::UploadedFile)

          raise DecodeError.new("expected an uploaded file, got #{value.class}")
        end

        sig { override.params(value: ::ActionDispatch::Http::UploadedFile).returns(Oapi::Wire) }
        def to_wire(value) = value.original_filename

        CODEC = T.let(new, UploadedFile)
      end
    end

    class MissingContainer < Error; end

    class Controller < ::ActionController::API
      extend T::Sig

      rescue_from DecodeError, with: :render_openapi_decode_error

      private

      sig { returns(T.untyped) }
      def oapi_container
        raise MissingContainer,
              "#{self.class} needs a container. Define #oapi_container on the controller base " \
              "class named by `controller_base` in your oapi.yml, returning something that " \
              "responds to resolve(key)."
      end

      sig { params(response: T.untyped).void }
      def render_openapi(response)
        body = response.to_wire
        return T.unsafe(self).head(response.status) if body.nil?

        T.unsafe(self).render(json: body, status: response.status, content_type: response.content_type)
      end

      sig { params(error: DecodeError).void }
      def render_openapi_decode_error(error)
        T.unsafe(self).render(
          json: { "title" => "Unprocessable Content", "status" => 422,
                  "detail" => error.detail, "pointer" => error.json_pointer },
          status: :unprocessable_content,
          content_type: "application/problem+json"
        )
      end
    end
  end
end
