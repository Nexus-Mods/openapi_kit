# typed: strict
# frozen_string_literal: true

require "time"

require "oapi/codec/contract"

module Oapi
  module Codec
    module DateTime
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::Time } }

      sig { override.params(value: T.untyped).returns(::Time) }
      def self.from_wire(value)
        raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}") unless
          value.is_a?(::String)

        begin
          ::Time.iso8601(value)
        rescue ArgumentError
          raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}")
        end
      end

      sig { override.params(value: ::Time).returns(Oapi::Wire) }
      def self.to_wire(value) = value.utc.iso8601
    end
  end
end
