# typed: strict
# frozen_string_literal: true

require "action_dispatch"

require "oapi/runtime"

module Oapi
  module Rails
    module Codec
      class UploadedFile
        extend T::Sig
        extend T::Generic
        include Oapi::Codec::Contract

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
  end
end
