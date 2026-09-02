# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    class Byte
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::String } }

      sig { override.params(value: T.untyped).returns(::String) }
      def from_wire(value)
        raise DecodeError.new("expected base64, got #{value.inspect}") unless value.is_a?(::String)

        decoded = value.unpack1("m0")
        raise DecodeError.new("expected base64, got #{value.inspect}") if decoded.nil?

        decoded
      rescue ArgumentError
        raise DecodeError.new("expected base64, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(Oapi::Wire) }
      def to_wire(value) = [value].pack("m0")

      CODEC = T.let(new, Byte)
    end
  end
end
