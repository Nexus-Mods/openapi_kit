# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    module Byte
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::String } }

      sig { override.params(value: T.untyped).returns(::String) }
      def self.from_wire(value)
        raise DecodeError.new("expected base64, got #{value.inspect}") unless value.is_a?(::String)

        decoded = value.unpack1("m0")
        raise DecodeError.new("expected base64, got #{value.inspect}") if decoded.nil?

        decoded
      rescue ArgumentError
        raise DecodeError.new("expected base64, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(Oapi::Wire) }
      def self.to_wire(value) = [value].pack("m0")
    end
  end
end
