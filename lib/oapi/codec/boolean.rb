# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    module Boolean
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: T::Boolean } }

      TRUTHY = T.let(%w[true 1].freeze, T::Array[::String])
      FALSEY = T.let(%w[false 0].freeze, T::Array[::String])

      sig { override.params(value: T.untyped).returns(T::Boolean) }
      def self.from_wire(value)
        return value if value.is_a?(::TrueClass) || value.is_a?(::FalseClass)

        if value.is_a?(::String)
          return true if TRUTHY.include?(value.downcase)
          return false if FALSEY.include?(value.downcase)
        end

        raise DecodeError.new("expected a boolean, got #{value.inspect}")
      end

      sig { override.params(value: T::Boolean).returns(Oapi::Wire) }
      def self.to_wire(value) = value
    end
  end
end
