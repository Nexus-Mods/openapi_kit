# typed: strict
# frozen_string_literal: true

require "openapi_kit/codec/contract"

module OpenAPIKit
  module Codec
    module String
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::String } }

      sig { override.params(value: OpenAPIKit::Wire).returns(::String) }
      def self.from_wire(value)
        return value if value.is_a?(::String)

        raise DecodeError.new("expected a string, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(OpenAPIKit::Wire) }
      def self.to_wire(value) = value
    end
  end
end
