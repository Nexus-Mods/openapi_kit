# typed: strict
# frozen_string_literal: true

require "oapi/wire"

module Oapi
  module Codec
    module Contract
      extend T::Sig
      extend T::Generic
      extend T::Helpers
      interface!

      Value = type_member

      sig { abstract.params(value: T.untyped).returns(Value) }
      def from_wire(value); end

      sig { abstract.params(value: Value).returns(Oapi::Wire) }
      def to_wire(value); end
    end
  end
end
