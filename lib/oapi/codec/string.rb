# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    class String
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::String } }

      sig { override.params(value: T.untyped).returns(::String) }
      def from_wire(value)
        return value if value.is_a?(::String)

        raise DecodeError.new("expected a string, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(Oapi::Wire) }
      def to_wire(value) = value

      CODEC = T.let(new, String)
    end
  end
end
