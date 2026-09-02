# typed: strict
# frozen_string_literal: true

require "bigdecimal"

require "oapi/codec/contract"

module Oapi
  module Codec
    class Decimal
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::BigDecimal } }

      sig { override.params(value: T.untyped).returns(::BigDecimal) }
      def from_wire(value)
        case value
        when ::Integer then Kernel.BigDecimal(value)
        when ::Float then Kernel.BigDecimal(value, ::Float::DIG)
        when ::String
          begin
            Kernel.BigDecimal(value)
          rescue ArgumentError, TypeError
            raise DecodeError.new("expected a decimal, got #{value.inspect}")
          end
        else raise DecodeError.new("expected a decimal, got #{value.inspect}")
        end
      end

      sig { override.params(value: ::BigDecimal).returns(Oapi::Wire) }
      def to_wire(value) = value.to_s("F")

      CODEC = T.let(new, Decimal)
    end
  end
end
