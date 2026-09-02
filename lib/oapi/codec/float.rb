# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    class Float
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::Float } }

      sig { override.params(value: T.untyped).returns(::Float) }
      def from_wire(value)
        return value.to_f if value.is_a?(::Numeric)

        if value.is_a?(::String)
          begin
            return Kernel.Float(value)
          rescue ArgumentError, TypeError
            raise DecodeError.new("expected a number, got #{value.inspect}")
          end
        end

        raise DecodeError.new("expected a number, got #{value.inspect}")
      end

      sig { override.params(value: ::Float).returns(Oapi::Wire) }
      def to_wire(value) = value

      CODEC = T.let(new, Float)
    end
  end
end
