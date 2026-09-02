# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    class Untyped
      extend T::Sig
      extend T::Generic
      include Contract

      Value = type_member { { fixed: T.untyped } }

      sig { override.params(value: T.untyped).returns(T.untyped) }
      def from_wire(value) = value

      sig { override.params(value: T.untyped).returns(Oapi::Wire) }
      def to_wire(value) = value

      CODEC = T.let(new, Untyped)
    end
  end
end
