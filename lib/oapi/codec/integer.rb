# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    module Integer
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::Integer } }

      sig { override.params(value: Oapi::Wire).returns(::Integer) }
      def self.from_wire(value)
        return value if value.is_a?(::Integer)
        return value.to_i if value.is_a?(::String) && value.match?(/\A[+-]?\d+\z/)

        raise DecodeError.new("expected an integer, got #{value.inspect}")
      end

      sig { override.params(value: ::Integer).returns(Oapi::Wire) }
      def self.to_wire(value) = value
    end
  end
end
