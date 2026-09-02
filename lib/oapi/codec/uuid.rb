# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    class Uuid
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: ::String } }

      PATTERN = T.let(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, Regexp)

      sig { override.params(value: T.untyped).returns(::String) }
      def from_wire(value)
        return value if value.is_a?(::String) && value.match?(PATTERN)

        raise DecodeError.new("expected a UUID, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(Oapi::Wire) }
      def to_wire(value) = value

      CODEC = T.let(new, Uuid)
    end
  end
end
