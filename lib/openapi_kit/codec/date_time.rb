# typed: strict
# frozen_string_literal: true

require "time"

require "openapi_kit/codec/contract"

module OpenAPIKit
  module Codec
    module DateTime
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::Time } }

      sig { override.params(value: OpenAPIKit::Wire).returns(::Time) }
      def self.from_wire(value)
        raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}") unless
          value.is_a?(::String)

        begin
          ::Time.iso8601(value)
        rescue ArgumentError
          raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}")
        end
      end

      # Rails renders a Time through as_json at three decimal places
      # (ActiveSupport::JSON::Encoding.time_precision), so an application moving onto
      # openapi_kit keeps emitting the timestamps its clients already parse.
      PRECISION = 3

      sig { override.params(value: ::Time).returns(OpenAPIKit::Wire) }
      def self.to_wire(value) = value.utc.iso8601(PRECISION)
    end
  end
end
