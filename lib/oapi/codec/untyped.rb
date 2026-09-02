# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    module Untyped
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: T.untyped } }

      sig { override.params(value: Oapi::Wire).returns(T.untyped) }
      def self.from_wire(value) = value

      sig { override.params(value: Oapi::Wire).returns(Oapi::Wire) }
      def self.to_wire(value) = value
    end
  end
end
