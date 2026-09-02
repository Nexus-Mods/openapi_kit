# typed: strict
# frozen_string_literal: true

require "action_controller"
require "action_dispatch"

require "oapi/runtime"

module Oapi
  module Rails
    extend T::Sig

    class NoContainer < Error; end

    @container = T.let(nil, T.untyped)
    @apis = T.let([], T::Array[T.untyped])

    sig { params(container: T.untyped).void }
    def self.container=(container)
      @container = container
    end

    sig { returns(T.untyped) }
    def self.container
      found = @container
      raise NoContainer, "Oapi::Rails.container has not been set" if found.nil?

      found
    end

    sig { returns(T::Array[T.untyped]) }
    def self.apis = @apis

    sig { params(generated_container: T.untyped).void }
    def self.register(generated_container)
      @apis << generated_container unless @apis.include?(generated_container)
    end

    sig { void }
    def self.verify!
      apis.each { |api| api.verify!(container) }
    end

    sig { params(request: ::ActionDispatch::Request, names: T::Array[String]).returns(T::Hash[String, String]) }
    def self.headers(request, names)
      names.each_with_object({}) do |name, found|
        value = request.headers[name]
        found[name] = value.to_s unless value.nil?
      end
    end

    sig { params(request: ::ActionDispatch::Request, names: T::Array[String]).returns(T::Hash[String, String]) }
    def self.cookies(request, names)
      jar = request.cookie_jar
      names.each_with_object({}) do |name, found|
        value = jar[name]
        found[name] = value.to_s unless value.nil?
      end
    end

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

    class Controller < ::ActionController::API
      extend T::Sig

      rescue_from DecodeError, with: :render_openapi_decode_error

      private

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
