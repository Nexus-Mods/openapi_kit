# typed: strict
# frozen_string_literal: true

require "action_dispatch"

require "oapi/runtime"

module Oapi
  module Rails
    module Codec
      class UploadedFileCodec
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
      end

      UploadedFile = T.let(UploadedFileCodec.new, UploadedFileCodec)
    end
  end
end
