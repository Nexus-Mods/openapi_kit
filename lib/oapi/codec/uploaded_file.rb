# typed: strict
# frozen_string_literal: true

require "action_dispatch"

require "oapi/codec/contract"

module Oapi
  module Codec
    module UploadedFile
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::ActionDispatch::Http::UploadedFile } }

      sig { override.params(value: T.untyped).returns(::ActionDispatch::Http::UploadedFile) }
      def self.from_wire(value)
        return value if value.is_a?(::ActionDispatch::Http::UploadedFile)

        raise DecodeError.new("expected an uploaded file, got #{value.class}")
      end

      sig { override.params(value: ::ActionDispatch::Http::UploadedFile).returns(Oapi::Wire) }
      def self.to_wire(value) = value.original_filename
    end
  end
end
