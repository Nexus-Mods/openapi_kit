# typed: strict
# frozen_string_literal: true

require "bigdecimal"

require "openapi_kit/codec/contract"

module OpenAPIKit
  module Codec
    module Decimal
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::BigDecimal } }

      sig { override.params(value: OpenAPIKit::Wire).returns(::BigDecimal) }
      def self.from_wire(value)
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

      sig { override.params(value: ::BigDecimal).returns(OpenAPIKit::Wire) }
      def self.to_wire(value) = value.to_s("F")
    end
  end
end
