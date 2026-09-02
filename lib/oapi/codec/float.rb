# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    module Float
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::Float } }

      sig { override.params(value: Oapi::Wire::In).returns(::Float) }
      def self.from_wire(value)
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

      sig { override.params(value: ::Float).returns(Oapi::Wire::Out) }
      def self.to_wire(value) = value
    end
  end
end
