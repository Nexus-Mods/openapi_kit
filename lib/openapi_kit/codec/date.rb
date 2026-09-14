# typed: strict
# frozen_string_literal: true

require "date"

require "openapi_kit/codec/contract"

module OpenAPIKit
  module Codec
    module Date
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::Date } }

      sig { override.params(value: OpenAPIKit::Wire).returns(::Date) }
      def self.from_wire(value)
        raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}") unless value.is_a?(::String)

        begin
          ::Date.iso8601(value)
        rescue ::Date::Error
          raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}")
        end
      end

      sig { override.params(value: ::Date).returns(OpenAPIKit::Wire) }
      def self.to_wire(value) = value.iso8601
    end
  end
end
