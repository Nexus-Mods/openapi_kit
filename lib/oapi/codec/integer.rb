# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    class Integer
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::Integer } }

      sig { override.params(value: T.untyped).returns(::Integer) }
      def from_wire(value)
        return value if value.is_a?(::Integer)
        return value.to_i if value.is_a?(::String) && value.match?(/\A[+-]?\d+\z/)

        raise DecodeError.new("expected an integer, got #{value.inspect}")
      end

      sig { override.params(value: ::Integer).returns(Oapi::Wire) }
      def to_wire(value) = value

      CODEC = T.let(new, Integer)
    end
  end
end
