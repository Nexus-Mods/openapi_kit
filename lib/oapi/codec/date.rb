# typed: strict
# frozen_string_literal: true

require "date"

require "oapi/codec/contract"

module Oapi
  module Codec
    class Date
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::Date } }

      sig { override.params(value: T.untyped).returns(::Date) }
      def from_wire(value)
        raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}") unless value.is_a?(::String)

        begin
          ::Date.iso8601(value)
        rescue ::Date::Error
          raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}")
        end
      end

      sig { override.params(value: ::Date).returns(Oapi::Wire) }
      def to_wire(value) = value.iso8601

      CODEC = T.let(new, Date)
    end
  end
end
